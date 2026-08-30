{ config, pkgs, ... }:

let
  appleLogoPath = ../../assets/local/apple-logo-2x.png;
  appleLogoAvailable = builtins.pathExists appleLogoPath;
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
  rawPlymouthHostName = config.networking.hostName;
  displayPlymouthHostName =
    if rawPlymouthHostName == "" then
      ""
    else
      pkgs.lib.strings.toUpper (builtins.substring 0 1 rawPlymouthHostName)
      + builtins.substring 1 (builtins.stringLength rawPlymouthHostName - 1) rawPlymouthHostName;
  plymouthHostName = builtins.toJSON displayPlymouthHostName;

  appleMacBookAirPlymouthTheme = pkgs.runCommandLocal "apple-macbook-air-8-1-plymouth" {
    nativeBuildInputs = [ pkgs.librsvg pkgs.imagemagick ];
  } ''
    themeDir="$out/share/plymouth/themes/apple-macbook-air-8-1"
    mkdir -p "$themeDir"

    install -m 0644 \
      ${../../assets/plymouth/apple-macbook-air-8-1.script} \
      "$themeDir/apple-macbook-air-8-1.script"

    # The hostname comes from the evaluated local identity and is injected only
    # into the built theme. No deployment-specific hostname is tracked in Git.
    cat >> "$themeDir/apple-macbook-air-8-1.script" <<'EOF_HOSTNAME'

    // Machine-local hostname, injected by Nix at theme build time.
    hostname_img = Image.Text(${plymouthHostName}, 0.72, 0.72, 0.72, 1, "Sans 28");
    hostname_sprite = Sprite(hostname_img);
    hostname_sprite.SetX(Math.Int(SCREEN_W - hostname_img.GetWidth() - SCREEN_W * 0.025));
    hostname_sprite.SetY(Math.Int(SCREEN_H - hostname_img.GetHeight() - SCREEN_H * 0.025));
    hostname_sprite.SetZ(3);
    hostname_sprite.SetOpacity(1);
    EOF_HOSTNAME

    # The internal panel is 2560x1600 (16:10). Scale the shared wallpaper
    # proportionally until the complete panel is covered, then crop it from
    # the center to exactly 2560x1600. Never stretch the image.
    ${if wallpaperAvailable then ''
      magick \
        ${wallpaperPath} \
        -resize '2560x1600^' \
        -gravity center \
        -extent 2560x1600 \
        -strip \
        "$themeDir/background.png"
    '' else ''
      # A clean checkout remains buildable before the machine-local wallpaper
      # has been downloaded. Installation normally populates it before build.
      magick \
        -size 2560x1600 xc:black \
        "$themeDir/background.png"
    ''}

    ${if appleLogoAvailable then ''
      # Optional local vendor asset. The 168x206 Retina image is extracted
      # from appleLogo.efires and intentionally kept outside Git.
      install -m 0644 \
        ${appleLogoPath} \
        "$themeDir/apple-logo.png"
    '' else ''
      # Keep the Plymouth script loadable without redistributing an Apple
      # logo. The transparent placeholder is never shown: the script is also
      # rewritten to skip the complete logo-delay/movement phase.
      magick \
        -size 1x1 xc:none \
        "$themeDir/apple-logo.png"

      ${pkgs.gnused}/bin/sed -i \
        -e 's/phase = PHASE_LOGO_DELAY;/phase = PHASE_LUKS_TYPE;/' \
        -e 's/apple_sprite.SetOpacity(1);/apple_sprite.SetOpacity(0);/g' \
        "$themeDir/apple-macbook-air-8-1.script"
    ''}

    # Match the other workstation themes' LUKS2 password line and final
    # spinner exactly.
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

    rsvg-convert --output "$themeDir/underline.png" "$TMPDIR/underline.svg"
    rsvg-convert --output "$themeDir/spinner.png" "$TMPDIR/spinner.svg"

    cat > "$themeDir/apple-macbook-air-8-1.plymouth" <<EOF_THEME
    [Plymouth Theme]
    Name=Apple MacBook Air 8,1
    Description=MacBook Air boot and LUKS2 animation
    ModuleName=script

    [script]
    ImageDir=$themeDir
    ScriptFile=$themeDir/apple-macbook-air-8-1.script
    EOF_THEME
  '';
in
{
  # Load i915 in stage 1 instead of waiting until the real root is available.
  # This shortens the simpledrm phase and gives Plymouth the native Intel DRM
  # device already during the encrypted-root prompt.
  boot.initrd.kernelModules = [ "i915" ];

  boot.kernelParams = [
    "quiet"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
    "vt.global_cursor_default=0"
    "plymouth.force-scale=1"
  ];

  boot.initrd.verbose = false;
  boot.consoleLogLevel = 3;

  boot.plymouth = {
    enable = true;
    theme = "apple-macbook-air-8-1";
    themePackages = [ appleMacBookAirPlymouthTheme ];
  };

  # If the optional Apple logo has not been imported yet, check the verified
  # Apple EFI partition once during normal boot. The importer mounts p1
  # read-only and silently leaves Plymouth logo-less when appleLogo.efires is
  # not present. A logo imported here is picked up by the next rebuild.
  systemd.services.apple-boot-logo-import = {
    description = "Import optional Apple Plymouth boot logo";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    unitConfig.ConditionPathExists = "!/etc/nixos/assets/local/apple-logo-2x.png";
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.python3
      pkgs.util-linux
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -f /etc/nixos/scripts/import-apple-boot-logo-linux.sh ]; then
        bash /etc/nixos/scripts/import-apple-boot-logo-linux.sh
      fi
    '';
  };

  # Keep the splash visible long enough to bridge the gap between the end of
  # the boot animation and the COSMIC greeter instead of exposing tty output.
  systemd.services.plymouth-quit.serviceConfig.ExecStartPre = [
    "${pkgs.coreutils}/bin/sleep 5"
  ];
}
