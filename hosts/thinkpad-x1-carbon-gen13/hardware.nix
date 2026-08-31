{ config, pkgs, ... }:

let
  thinkpadLogoPath = ../../assets/local/thinkpad-logo.svg;
  thinkpadLogoAvailable = builtins.pathExists thinkpadLogoPath;
  wallpaperPath = config.workstation.wallpaper.source;
  wallpaperAvailable = wallpaperPath != null;
  rawPlymouthHostName = config.networking.hostName;
  displayPlymouthHostName =
    if rawPlymouthHostName == "" then
      ""
    else
      pkgs.lib.strings.toUpper (builtins.substring 0 1 rawPlymouthHostName)
      + builtins.substring 1 (builtins.stringLength rawPlymouthHostName - 1) rawPlymouthHostName;
  plymouthHostName = builtins.toJSON displayPlymouthHostName;

  thinkpadPlymouthTheme = pkgs.runCommandLocal "thinkpad-x1-carbon-gen13-plymouth" {
    nativeBuildInputs = [ pkgs.librsvg pkgs.imagemagick ];
  } ''
    themeDir="$out/share/plymouth/themes/thinkpad-x1-carbon-gen13"
    mkdir -p "$themeDir"

    install -m 0644 \
      ${../../assets/plymouth/thinkpad-x1-carbon-gen13.script} \
      "$themeDir/thinkpad-x1-carbon-gen13.script"

    # The hostname comes from the evaluated local identity and is injected only
    # into the built theme. No deployment-specific hostname is tracked in Git.
    cat >> "$themeDir/thinkpad-x1-carbon-gen13.script" <<'EOF_HOSTNAME'

    // Machine-local hostname, injected by Nix at theme build time.
    hostname_img = Image.Text(${plymouthHostName}, 0.72, 0.72, 0.72, 1, "Sans 28");
    hostname_sprite = Sprite(hostname_img);
    hostname_sprite.SetX(Math.Int(SCREEN_W - hostname_img.GetWidth() - SCREEN_W * 0.025));
    hostname_sprite.SetY(Math.Int(SCREEN_H - hostname_img.GetHeight() - SCREEN_H * 0.025));
    hostname_sprite.SetZ(3);
    hostname_sprite.SetOpacity(1);
    EOF_HOSTNAME

    ${if thinkpadLogoAvailable then ''
      # Render the locally downloaded upstream logo at the final target width.
      # The source wordmark is black; recolour only black pixels to white while
      # preserving the red TrackPoint dot for the dark Plymouth theme.
      rsvg-convert \
        --width 520 \
        --output "$TMPDIR/thinkpad-source.png" \
        ${thinkpadLogoPath}

      magick \
        "$TMPDIR/thinkpad-source.png" \
        -fill white \
        -opaque black \
        -strip \
        "$themeDir/thinkpad.png"
    '' else ''
      # Keep Plymouth fully functional without redistributing the ThinkPad logo.
      # The transparent placeholder leaves all animation timing unchanged.
      magick \
        -size 1x1 xc:none \
        "$themeDir/thinkpad.png"
    ''}

    ${if wallpaperAvailable then ''
      magick \
        ${wallpaperPath} \
        -resize '2880x1800^' \
        -gravity center \
        -extent 2880x1800 \
        -strip \
        "$themeDir/background.png"
    '' else ''
      # A clean checkout remains buildable before the machine-local wallpaper
      # has been downloaded. Installation normally populates it before build.
      magick \
        -size 2880x1800 xc:black \
        "$themeDir/background.png"
    ''}

    cat > "$TMPDIR/lenovo-bg.svg" <<'EOF'
    <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">
      <rect width="32" height="32" fill="#e2231a"/>
    </svg>
    EOF

    cat > "$TMPDIR/underline.svg" <<'EOF'
    <svg xmlns="http://www.w3.org/2000/svg" width="960" height="4" viewBox="0 0 960 4">
      <rect width="960" height="4" rx="2" fill="#ffffff" fill-opacity="0.82"/>
    </svg>
    EOF

    cat > "$TMPDIR/spinner.svg" <<'EOF'
    <svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96">
      <circle cx="48" cy="48" r="36" fill="none" stroke="#ffffff" stroke-width="7"
              stroke-linecap="round" stroke-dasharray="145 82"/>
    </svg>
    EOF

    rsvg-convert --output "$themeDir/lenovo-bg.png" "$TMPDIR/lenovo-bg.svg"
    rsvg-convert --output "$themeDir/underline.png" "$TMPDIR/underline.svg"
    rsvg-convert --output "$themeDir/spinner.png" "$TMPDIR/spinner.svg"

    cat > "$themeDir/thinkpad-x1-carbon-gen13.plymouth" <<EOF
    [Plymouth Theme]
    Name=ThinkPad X1 Carbon Gen 13
    Description=ThinkPad LUKS boot animation
    ModuleName=script

    [script]
    ImageDir=$themeDir
    ScriptFile=$themeDir/thinkpad-x1-carbon-gen13.script
    EOF
  '';

  deactivatePlymouthIfRunning = pkgs.writeShellScript "deactivate-plymouth-if-running" ''
    if ${config.boot.plymouth.package}/bin/plymouth --ping >/dev/null 2>&1; then
      exec ${config.boot.plymouth.package}/bin/plymouth deactivate
    fi
  '';

  # Keep the retained splash across the Plasma login-manager hand-off. The
  # five-second bridge is deliberate and is validated visually on cold boot;
  # changing it can expose an intermediate console/transition frame. See
  # docs/operational-invariants.md before simplifying the quit overrides.
  finishPlymouthAfterPlasma = pkgs.writeShellScript "finish-plymouth-after-plasma" ''
    ${pkgs.coreutils}/bin/sleep 5
    exec ${config.boot.plymouth.package}/bin/plymouth quit --retain-splash
  '';
in
{
  boot.kernelParams = [
    "nmi_watchdog=0"
    "quiet"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "plymouth.force-scale=1"
  ];

  boot.initrd.verbose = false;
  boot.consoleLogLevel = 3;

  systemd.settings.Manager = {
    RuntimeWatchdogSec = "off";
    RebootWatchdogSec = "off";
    KExecWatchdogSec = "off";
  };

  boot.plymouth = {
    enable = true;
    theme = "thinkpad-x1-carbon-gen13";
    themePackages = [ thinkpadPlymouthTheme ];
  };

  # If the optional ThinkPad logo is not present locally, try to obtain the
  # documented upstream asset after networking is available. The next regular
  # rebuild/Topgrade run then picks up the locally stored logo automatically.
  systemd.services.thinkpad-plymouth-logo-fetch = {
    description = "Fetch optional ThinkPad Plymouth logo";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/etc/nixos/assets/local/thinkpad-logo.svg";
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gnugrep
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -f /etc/nixos/scripts/fetch-thinkpad-plymouth-logo.sh ]; then
        bash /etc/nixos/scripts/fetch-thinkpad-plymouth-logo.sh || true
      fi
    '';
  };

  systemd.services.plymouth-quit.serviceConfig.ExecStart = [
    ""
    "${deactivatePlymouthIfRunning}"
  ];

  systemd.services.plymouth-quit-wait.serviceConfig.ExecStart = [
    ""
    "${pkgs.coreutils}/bin/true"
  ];

  systemd.services.plasmalogin.wants = [ "plymouth-final-quit.service" ];

  systemd.services.plymouth-final-quit = {
    description = "Finish Plymouth after Plasma starts";
    after = [ "plasmalogin.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = finishPlymouthAfterPlasma;
    };
  };

  boot.extraModprobeConfig = ''
    options snd_hda_intel power_save=10
  '';

  services.fwupd.enable = true;
  hardware.bluetooth.enable = true;
  services.fprintd.enable = true;

  # The nixos-hardware profile enables thermald by default. On the X1 Carbon
  # Gen 13 it exits as incompatible because of Lenovo DYTC. Preserve this
  # override until thermald is explicitly retested on the real model; see
  # docs/operational-invariants.md.
  services.thermald.enable = false;

  # This profile has Intel graphics only.
  environment.systemPackages = [ pkgs.nvtopPackages.intel ];
}
