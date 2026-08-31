{ ... }:

{
  imports = [
    ./identity.nix
    ./deployment.nix
    ./wallpaper.nix
    ./base.nix
    ./desktop.nix
    ./networking.nix
    ./services.nix
    ./home-manager-initial.nix
    ./rapl-access.nix
    ./programs.nix
    ./fastfetch.nix
    ./users.nix
    ./packages.nix
    ./fonts.nix
    ./audio.nix
    ./spotify.nix
    ../../topgrade.nix
    ./topgrade-guard.nix
  ];
}
