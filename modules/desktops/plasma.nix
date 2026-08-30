{ config, lib, pkgs, ... }:

let
  deployment = config.workstation.deployment;
  dolphinBookmark = lib.attrByPath [ "plasma" "dolphinBookmark" ] null deployment;

  dolphinBookmarkUrl =
    if dolphinBookmark == null then
      ""
    else if builtins.isAttrs dolphinBookmark && dolphinBookmark ? url && builtins.isString dolphinBookmark.url then
      dolphinBookmark.url
    else
      throw "deployment.json plasma.dolphinBookmark must contain a string 'url' value";

  dolphinBookmarkTitle =
    if dolphinBookmark == null then
      ""
    else if dolphinBookmark ? title then
      if builtins.isString dolphinBookmark.title then
        dolphinBookmark.title
      else
        throw "deployment.json plasma.dolphinBookmark.title must be a string"
    else
      "Network share";

  wallpaperPng = ../../assets/local/wallpaper.png;
  wallpaperJpg = ../../assets/local/wallpaper.jpg;
  wallpaperPath =
    if builtins.pathExists wallpaperPng then
      wallpaperPng
    else if builtins.pathExists wallpaperJpg then
      wallpaperJpg
    else
      null;
  wallpaperAvailable = wallpaperPath != null;

  kateWithPipeWire = pkgs.symlinkJoin {
    name = "kate-with-pipewire";
    paths = [ pkgs.kdePackages.kate ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/kate \
        --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath [ pkgs.pipewire ]}
    '';
  };

  setDefaultDisplayScale = pkgs.writeShellScript "set-default-display-scale" ''
    set -u

    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nixos"
    marker="$state_dir/default-display-scale-initialized"

    [ -e "$marker" ] && exit 0

    outputs_text=""
    valid=false

    for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
      if outputs_text="$(${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor -j 2>/dev/null \
        | ${pkgs.python3}/bin/python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

active_outputs = [
    output
    for output in data.get("outputs", [])
    if output.get("connected") and output.get("enabled") and output.get("name")
]

if not active_outputs:
    raise SystemExit(1)

for output in active_outputs:
    if abs(float(output.get("scale", 1.0)) - 1.5) > 0.001:
        print(output["name"])
' 2>/dev/null)"; then
        valid=true
        break
      fi

      ${pkgs.coreutils}/bin/sleep 0.2
    done

    [ "$valid" = true ] || exit 0

    if [ -n "$outputs_text" ]; then
      args=()
      while IFS= read -r output; do
        [ -n "$output" ] || continue
        args+=("output.''${output}.scale.1.5")
      done <<< "$outputs_text"

      [ "''${#args[@]}" -gt 0 ] || exit 0
      ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor "''${args[@]}" >/dev/null 2>&1 || exit 0
    fi

    mkdir -p "$state_dir"
    touch "$marker"
  '';

  setDefaultWallpaper = pkgs.writeShellScript "set-default-wallpaper" ''
    set -u

    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/nixos"
    marker="$state_dir/default-wallpaper-initialized"

    [ -e "$marker" ] && exit 0

    ${if wallpaperAvailable then ''
      wallpaper=${wallpaperPath}

      for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
        if ${pkgs.kdePackages.plasma-workspace}/bin/plasma-apply-wallpaperimage \
          "$wallpaper" >/dev/null 2>&1; then
          mkdir -p "$state_dir"
          touch "$marker"
          exit 0
        fi

        ${pkgs.coreutils}/bin/sleep 0.2
      done
    '' else ''
      # Installation normally fetches the local wallpaper before the first
      # build. Leave the marker absent so a later login can retry if it was not
      # available yet.
      :
    ''}

    exit 0
  '';

  setDolphinDefaults = pkgs.writeShellScript "set-dolphin-defaults" ''
    set -eu

    mkdir -p \
      "$HOME/.config" \
      "$HOME/.local/share/dolphin/view_properties/global"

    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
      --file "$HOME/.config/dolphinrc" \
      --group General \
      --key GlobalViewProps \
      --type bool \
      true

    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
      --file "$HOME/.local/share/dolphin/view_properties/global/.directory" \
      --group Dolphin \
      --key ViewMode \
      1

    ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 \
      --file "$HOME/.config/dolphinrc" \
      --group DetailsMode \
      --key PreviewSize \
      16

    places="$HOME/.local/share/user-places.xbel"
    for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
      if [ -e "$places" ]; then
        break
      fi
      ${pkgs.coreutils}/bin/sleep 0.2
    done

${lib.optionalString (dolphinBookmarkUrl != "") ''
    if [ -e "$places" ]; then
      ${pkgs.python3}/bin/python3 - \
        "$places" \
        ${lib.escapeShellArg dolphinBookmarkUrl} \
        ${lib.escapeShellArg dolphinBookmarkTitle} <<'PYTHON'
from html import escape
from pathlib import Path
import os
import re
import sys

path = Path(sys.argv[1])
url = sys.argv[2]
title = sys.argv[3]
text = path.read_text(encoding="utf-8")

normalized_url = url.rstrip("/")
if re.search(r'href=["\']' + re.escape(normalized_url) + r'/?["\']', text):
    raise SystemExit(0)

bookmark = (
    f'  <bookmark href="{escape(url, quote=True)}">\n'
    f'    <title>{escape(title)}</title>\n'
    '  </bookmark>\n'
)

closing = "</xbel>"
pos = text.rfind(closing)
if pos < 0:
    raise SystemExit("user-places.xbel does not contain a closing </xbel> element")

new_text = text[:pos] + bookmark + text[pos:]
tmp = path.with_name(path.name + ".nixos-tmp")
tmp.write_text(new_text, encoding="utf-8")
os.replace(tmp, path)
PYTHON
    fi
''}
  '';
in
{
  services.displayManager.plasma-login-manager.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.xserver.enable = false;

  environment.plasma6.excludePackages = [
    pkgs.kdePackages.kate
  ];

  # KDE applications belong to the Plasma layer and are therefore not
  # installed on COSMIC systems.
  environment.systemPackages = [
    kateWithPipeWire
    pkgs.kdePackages.filelight
    pkgs.kdePackages.ksystemlog
    pkgs.kdePackages.kfind
  ];

  programs.partition-manager.enable = true;
  programs.kdeconnect.enable = true;

  environment.etc."xdg/autostart/nixos-default-display-scale.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=NixOS Display Defaults
    Exec=${setDefaultDisplayScale}
    OnlyShowIn=KDE;
    NoDisplay=true
  '';

  environment.etc."xdg/autostart/nixos-default-wallpaper.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=NixOS Wallpaper Default
    Exec=${setDefaultWallpaper}
    OnlyShowIn=KDE;
    NoDisplay=true
  '';

  environment.etc."xdg/autostart/nixos-dolphin-defaults.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=NixOS Dolphin Defaults
    Exec=${setDolphinDefaults}
    OnlyShowIn=KDE;
    NoDisplay=true
  '';
}
