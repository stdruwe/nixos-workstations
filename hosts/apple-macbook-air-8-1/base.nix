{ lib, ... }:

let
  localSources = ../../.local-sources/lon.nix;
  sources = import (if builtins.pathExists localSources then localSources else ../../lon.nix);
in
{
  imports = [
    ./boot-picker.nix
    ./hardware.nix
    ./networking.nix
    ./plymouth.nix
    ./power.nix
    ./remote-builder.nix
    ./storage.nix
    ../../modules/common
    ../../modules/desktops/cosmic.nix
    "${sources."nixos-hardware"}/apple/t2"
  ];

  workstation.profile = "apple-macbook-air-8-1";

  # This hardware profile has no WWAN modem. Keep ModemManager and its
  # WWAN-specific helper packages out of the system closure.
  networking.modemmanager.enable = false;

  # The MacBook uses systemd-boot exclusively on a separate Linux ESP. Do not
  # create EFI NVRAM entries; the Apple Startup Manager finds the fallback
  # loader at EFI/BOOT/BOOTX64.EFI.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.loader.systemd-boot.consoleMode = "keep";
}
