{ ... }:

let
  localSources = ../../.local-sources/lon.nix;
  sources = import (if builtins.pathExists localSources then localSources else ../../lon.nix);
in
{
  imports = [
    ./hardware-installation.nix
    ./hardware.nix
    ./networking.nix
    ./desktop.nix
    ./services.nix
    ./audio.nix
    ../../modules/features/usb-pd-plasmoid.nix
    ../../modules/features/keyboard-backlight.nix
    ../../modules/common
    ../../modules/common/storage.nix
    ../../modules/desktops/plasma.nix
    ../../modules/features/gaming.nix
    ../../modules/features/virtualization.nix
    ../../modules/features/kate.nix
    "${sources."nixos-hardware"}/lenovo/thinkpad/x1/13th-gen"
  ];

  workstation.profile = "thinkpad-x1-carbon-gen13";

  # WWAN is actual hardware on this profile; keep ModemManager enabled here
  # explicitly instead of inheriting a workstation-wide default.
  networking.modemmanager.enable = true;

  boot.loader.systemd-boot.consoleMode = "keep";
}
