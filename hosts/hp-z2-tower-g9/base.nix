{ ... }:

let
  localSources = ../../.local-sources/lon.nix;
  sources = import (if builtins.pathExists localSources then localSources else ../../lon.nix);
in
{
  imports = [
    ./hardware-configuration.nix
    ./hardware.nix
    ./networking.nix
    ./nix-builder.nix
    ./desktop.nix
    ./audio.nix
    ./esphome.nix
    ../../modules/common
    ../../modules/common/storage.nix
    ../../modules/desktops/plasma.nix
    ../../modules/features/gaming.nix
    ../../modules/features/virtualization.nix
    ../../modules/features/kate.nix

    "${sources."nixos-hardware"}/common/gpu/intel"
    "${sources."nixos-hardware"}/common/gpu/amd"
  ];

  workstation.profile = "hp-z2-tower-g9";

  # This desktop profile has no WWAN modem. Keep ModemManager and its
  # WWAN-specific helper packages out of the system closure.
  networking.modemmanager.enable = false;
}
