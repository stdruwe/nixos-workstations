{ ... }:

{
  # The system drive follows the Discoverable Partitions Specification.
  # systemd finds the root partition by its GPT type (8304), opens an existing
  # LUKS2 volume as /dev/mapper/root and mounts it as / in the initrd. The
  # physical SSD therefore does not need to be known here.
  boot.initrd.systemd.root = "gpt-auto";

  # Because / is not declared through fileSystems."/", NixOS cannot infer the
  # filesystem driver required by the initrd automatically.
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  # Without an explicit boot.initrd.luks.devices entry, LUKS support still has
  # to be included in the initrd. systemd-gpt-auto-generator and
  # systemd-cryptsetup then handle discovery and decryption.
  boot.initrd.luks.forceLuksSupportInInitrd = true;

  # The root partition contains several Btrfs subvolumes. The automatically
  # discovered root filesystem therefore has to select @root explicitly.
  boot.kernelParams = [
    "rootfstype=btrfs"
    "rootflags=subvol=@root,compress=zstd,noatime"
  ];

  fileSystems = {
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
      options = [
        "subvol=@swap"
      ];
    };
  };

  swapDevices = [
    {
      device = "/swap/swapfile";
    }
  ];

  # /boot is intentionally not listed in fileSystems. After leaving the initrd,
  # systemd-gpt-auto-generator automatically mounts the boot disk's ESP at
  # /boot, including the appropriate umask=0077 option.
}
