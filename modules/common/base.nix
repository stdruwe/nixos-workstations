{ lib, pkgs, ... }:

{
  boot.loader.systemd-boot = {
    enable = true;
    configurationLimit = 8;
  };

  boot.loader.timeout = 0;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
  boot.initrd.systemd.enable = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  security.sudo.extraConfig = ''
    Defaults timestamp_timeout=15
  '';

  programs.git = {
    enable = true;
    config.safe.directory = "/etc/nixos";
  };

  system.stateVersion = "26.05";
}
