{ config, pkgs, ... }:

let
  nvtopIntelAmd = pkgs.callPackage (pkgs.path + "/pkgs/tools/system/nvtop/build-nvtop.nix") {
    amd = true;
    intel = true;
    nvidia = false;
  };

  hpLogoPath = ../../assets/local/hp-logo.svg;
  hpLogoAvailable = builtins.pathExists hpLogoPath;
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

  hpPlymouthTheme = pkgs.runCommandLocal "hp-z2-tower-g9-plymouth" {
    nativeBuildInputs = [ pkgs.librsvg pkgs.imagemagick ];
  } ''
    themeDir="$out/share/plymouth/themes/hp-z2-tower-g9"
    mkdir -p "$themeDir"

    install -m 0644 \
      ${../../assets/plymouth/hp-z2-tower-g9.script} \
      "$themeDir/hp-z2-tower-g9.script"

    # The hostname comes from the evaluated local identity and is injected only
    # into the built theme. No deployment-specific hostname is tracked in Git.
    cat >> "$themeDir/hp-z2-tower-g9.script" <<'EOF_HOSTNAME'

    // Machine-local hostname, injected by Nix at theme build time.
    hostname_img = Image.Text(${plymouthHostName}, 0.72, 0.72, 0.72, 1, "Sans 28");
    hostname_sprite = Sprite(hostname_img);
    hostname_sprite.SetX(Math.Int(SCREEN_W - hostname_img.GetWidth() - SCREEN_W * 0.025));
    hostname_sprite.SetY(Math.Int(SCREEN_H - hostname_img.GetHeight() - SCREEN_H * 0.025));
    hostname_sprite.SetZ(3);
    hostname_sprite.SetOpacity(1);
    EOF_HOSTNAME

    ${if wallpaperAvailable then ''
      magick \
        ${wallpaperPath} \
        -resize '1920x1080^' \
        -gravity center \
        -extent 1920x1080 \
        -strip \
        "$themeDir/background.png"
    '' else ''
      # A clean checkout remains buildable before the machine-local wallpaper
      # has been downloaded. Installation normally populates it before build.
      magick \
        -size 1920x1080 xc:black \
        "$themeDir/background.png"
    ''}

    ${if hpLogoAvailable then ''
      # Optional local vendor asset downloaded from the documented source.
      magick \
        ${hpLogoPath} \
        -alpha off \
        -threshold 50% \
        -transparent white \
        -fill white \
        -opaque black \
        -trim +repage \
        -resize 1200x \
        -strip \
        "$themeDir/hp-logo.png"
    '' else ''
      # Keep Plymouth fully functional without redistributing the HP logo.
      # The transparent image is never displayed; the script is rewritten to
      # skip the initial logo-only delay and hide the HP sprite throughout.
      magick \
        -size 1x1 xc:none \
        "$themeDir/hp-logo.png"

      ${pkgs.gnused}/bin/sed -i \
        -e 's/phase = PHASE_DELAY;/phase = PHASE_LUKS_TYPE;/' \
        -e 's/hp_sprite.SetOpacity(1);/hp_sprite.SetOpacity(0);/g' \
        "$themeDir/hp-z2-tower-g9.script"
    ''}

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

    cat > "$themeDir/hp-z2-tower-g9.plymouth" <<EOF
    [Plymouth Theme]
    Name=HP Z2 Tower G9
    Description=HP LUKS boot animation
    ModuleName=script

    [script]
    ImageDir=$themeDir
    ScriptFile=$themeDir/hp-z2-tower-g9.script
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
  # Watchdogs are intentionally disabled on the HP and ThinkPad profiles. This
  # is a deliberate workstation policy retained from earlier boot/shutdown and
  # power-management diagnostics, not a claim that the current kernel requires
  # NMI watchdogs to be disabled. See docs/operational-invariants.md before
  # changing this policy.
  boot.kernelParams = [
    "nmi_watchdog=0"
    "quiet"
    "systemd.show_status=false"
    "rd.systemd.show_status=false"
  ];

  boot.initrd.verbose = false;
  boot.consoleLogLevel = 3;

  # Keep systemd from arming runtime/reboot/kexec watchdog timers. Re-enable and
  # test each mechanism deliberately rather than treating these explicit values
  # as redundant defaults; clean HP reboot/shutdown behavior has been verified
  # with this no-watchdog policy, including while a virtual machine was active.
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "off";
    RebootWatchdogSec = "off";
    KExecWatchdogSec = "off";
  };

  boot.plymouth = {
    enable = true;
    theme = "hp-z2-tower-g9";
    themePackages = [ hpPlymouthTheme ];
  };

  # If the optional HP logo is not present locally, try to obtain the exact
  # documented source asset after networking is available. A downloaded logo
  # is picked up automatically by the next regular rebuild/Topgrade run.
  systemd.services.hp-plymouth-logo-fetch = {
    description = "Fetch optional HP Plymouth logo";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/etc/nixos/assets/local/hp-logo.svg";
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.gnugrep
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -f /etc/nixos/scripts/fetch-hp-plymouth-logo.sh ]; then
        bash /etc/nixos/scripts/fetch-hp-plymouth-logo.sh || true
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

  services.fwupd.enable = true;
  hardware.bluetooth.enable = true;

  # Intel UHD Graphics 770 and Radeon RX 7600 XT run in parallel through the
  # generic nixos-hardware profiles imported by base.nix. ROCm CLR adds the
  # AMD OpenCL ICD so compute applications can use the discrete RDNA3 GPU.
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.rocmPackages.clr.icd ];
  };

  environment.systemPackages = [ nvtopIntelAmd ];
}
