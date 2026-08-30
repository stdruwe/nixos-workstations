# Hardware configuration for a later reinstallation.
#
# Intentionally contains no fileSystems, swapDevices or LUKS UUIDs.
# On the running system, mounts are defined centrally through
# modules/common/storage.nix. The physical GPT/LUKS/Btrfs layout for a
# reinstallation remains described in hosts/thinkpad-x1-carbon-gen13/disko.nix.

{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "thunderbolt"
    "nvme"
    "usb_storage"
    "sd_mod"
  ];

  boot.initrd.kernelModules = [ ];

  boot.kernelModules = [
    "kvm-intel"
  ];

  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  hardware.cpu.intel.npu.enable = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
