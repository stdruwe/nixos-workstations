{ ... }:

{
  # The MacBook intentionally uses no automatic GPT discovery for root or ESP.
  # In the dual-boot system the Apple EFI and a separate Linux ESP coexist, so
  # only the explicitly named Linux partitions are used.
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  boot.initrd.luks.devices.root = {
    device = "/dev/disk/by-partlabel/NIXOS-LUKS";
    allowDiscards = true;
  };

  fileSystems = {
    "/" = {
      device = "/dev/mapper/root";
      fsType = "btrfs";
      options = [
        "subvol=@root"
        "compress=zstd"
        "noatime"
      ];
    };

    "/home" = {
      device = "/dev/mapper/root";
      fsType = "btrfs";
      options = [
        "subvol=@home"
        "compress=zstd"
        "noatime"
      ];
    };

    "/nix" = {
      device = "/dev/mapper/root";
      fsType = "btrfs";
      options = [
        "subvol=@nix"
        "compress=zstd"
        "noatime"
      ];
    };

    "/swap" = {
      device = "/dev/mapper/root";
      fsType = "btrfs";
      options = [ "subvol=@swap" ];
    };

    "/boot" = {
      device = "/dev/disk/by-partlabel/NIXOS-ESP";
      fsType = "vfat";
      options = [ "umask=0077" ];
      neededForBoot = true;
    };
  };

  # The machine has 16 GiB RAM. A 16 GiB swapfile is sufficient for the
  # current non-hibernating configuration without reserving unnecessary space.
  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 16 * 1024;
    }
  ];
}
