{ pkgs, ... }:

{
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  services.fstrim.enable = true;

  nix = {
    settings.auto-optimise-store = true;

    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  services.printing.enable = true;

  services.openssh = {
    enable = true;
    openFirewall = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  # Flatpak itself is enabled in programs.nix. Keep Flathub available
  # declaratively on every desktop host. A host can be considered "online"
  # before external connectivity is actually usable, so retry transient
  # network failures automatically.
  systemd.services.flatpak-flathub = {
    description = "Ensure Flathub system remote exists";

    wantedBy = [ "multi-user.target" ];
    after = [
      "local-fs.target"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];

    path = [ pkgs.flatpak ];

    script = ''
      flatpak remote-add \
        --system \
        --if-not-exists \
        flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };

  # Flatseal is not packaged in the current nixos-unstable package set.
  # Provision it from the already-managed Flathub remote instead of carrying
  # a local package. Updates remain owned by the normal Flatpak/Topgrade path.
  systemd.services.flatpak-required-apps = {
    description = "Ensure required system Flatpak applications are installed";

    wantedBy = [ "multi-user.target" ];
    after = [ "flatpak-flathub.service" ];
    requires = [ "flatpak-flathub.service" ];

    path = [ pkgs.flatpak ];

    script = ''
      if ! flatpak info --system com.github.tchx84.Flatseal >/dev/null 2>&1; then
        flatpak install \
          --system \
          --noninteractive \
          flathub \
          com.github.tchx84.Flatseal
      fi
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "15s";
    };
  };
}
