{ config, pkgs, ... }:

let
  homeDirectory = config.workstation.homeDirectory;
  userName = config.workstation.userName;
in
{
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "de_DE.UTF-8";

  i18n.extraLocaleSettings = {
    LC_CTYPE = "de_DE.UTF-8";
    LC_ADDRESS = "de_DE.UTF-8";
    LC_IDENTIFICATION = "de_DE.UTF-8";
    LC_MEASUREMENT = "de_DE.UTF-8";
    LC_MONETARY = "de_DE.UTF-8";
    LC_NAME = "de_DE.UTF-8";
    LC_NUMERIC = "de_DE.UTF-8";
    LC_PAPER = "de_DE.UTF-8";
    LC_TELEPHONE = "de_DE.UTF-8";
    LC_TIME = "de_DE.UTF-8";
  };

  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };

  console.keyMap = "de";

  # The shared wallpaper is obtained from its documented KDE Store source and
  # kept only in the machine-local ignored asset directory. Installation
  # normally downloads it before the first build; this service repairs a
  # missing local copy after networking becomes available.
  systemd.services.workstation-wallpaper-fetch = {
    description = "Fetch shared workstation wallpaper";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.python3
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ -f /etc/nixos/scripts/fetch-wallpaper.sh ]; then
        bash /etc/nixos/scripts/fetch-wallpaper.sh /etc/nixos/assets/local || true
      fi
    '';
  };

  systemd.tmpfiles.rules = [
    "d ${homeDirectory}/Schreibtisch 0755 ${userName} users -"
    "L+ ${homeDirectory}/Schreibtisch/NixOS-Post-Install-README.md - ${userName} users - /etc/nixos/README-POST-INSTALL.md"
  ];
}
