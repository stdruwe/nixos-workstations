{ config, pkgs, ... }:

let
  wallpaperSource = config.workstation.wallpaper.source;
  wallpaperPath = config.workstation.wallpaper.runtimePath;
  wallpaperAvailable = wallpaperSource != null && wallpaperPath != null;

  cosmicWallpaper = ''
    (
        output: "all",
        source: Path("${if wallpaperAvailable then wallpaperPath else ""}"),
        filter_by_theme: false,
        rotation_frequency: 300,
        filter_method: Lanczos,
        scaling_mode: Zoom,
        sampling_method: Alphanumeric,
    )
  '';
in
{
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  # COSMIC runs natively on Wayland. XWayland remains available through the
  # COSMIC module without enabling an X11 desktop server.
  services.xserver.enable = false;

  # Keep the user's COSMIC desktop and lock screen on the same machine-local
  # wallpaper used by Plymouth. The activation service runs on every NixOS
  # switch, including the verified switch performed by Topgrade.
  system.userActivationScripts.syncCosmicWallpaper = {
    text = if wallpaperAvailable then ''
      config_dir="$HOME/.config/cosmic/com.system76.CosmicBackground/v1"
      ${pkgs.coreutils}/bin/mkdir -p "$config_dir"
      ${pkgs.coreutils}/bin/cat > "$config_dir/all.tmp" <<'EOF_WALLPAPER'
${cosmicWallpaper}
EOF_WALLPAPER
      ${pkgs.coreutils}/bin/mv "$config_dir/all.tmp" "$config_dir/all"
    '' else ''
      :
    '';
  };

  # The login greeter runs as its own system user and therefore needs the same
  # COSMIC background configuration in its dedicated home directory.
  system.activationScripts.syncCosmicGreeterWallpaper = {
    deps = [ "users" ];
    text = if wallpaperAvailable then ''
      config_dir="/var/lib/cosmic-greeter/.config/cosmic/com.system76.CosmicBackground/v1"
      ${pkgs.coreutils}/bin/install -d \
        -m 0750 \
        -o cosmic-greeter \
        -g cosmic-greeter \
        "$config_dir"
      ${pkgs.coreutils}/bin/cat > "$config_dir/all.tmp" <<'EOF_WALLPAPER'
${cosmicWallpaper}
EOF_WALLPAPER
      ${pkgs.coreutils}/bin/chown cosmic-greeter:cosmic-greeter "$config_dir/all.tmp"
      ${pkgs.coreutils}/bin/chmod 0644 "$config_dir/all.tmp"
      ${pkgs.coreutils}/bin/mv "$config_dir/all.tmp" "$config_dir/all"
    '' else ''
      :
    '';
  };
}
