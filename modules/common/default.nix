{ ... }:

{
  imports = [
    ./identity.nix
    ./deployment.nix
    ./local-state.nix
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
    ./diagnostics.nix
    ./mobile-tools.nix
    ./fonts.nix
    ./audio.nix
    ./spotify.nix
    ../../topgrade.nix
    ./topgrade-guard.nix
  ];
}
