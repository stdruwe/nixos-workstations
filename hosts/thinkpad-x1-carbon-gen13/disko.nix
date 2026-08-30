{ device, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    inherit device;

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          label = "ESP";
          size = "2G";
          type = "EF00";

          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";

            mountOptions = [
              "umask=0077"
            ];
          };
        };

        root = {
          label = "root-x86-64";
          size = "100%";
          type = "8304";

          content = {
            type = "luks";
            name = "root";
            passwordFile = "/tmp/luks-password";

            extraFormatArgs = [
              "--type=luks2"
            ];

            content = {
              type = "btrfs";

              extraArgs = [
                "-L"
                "nixos"
              ];

              subvolumes = {
                "@root" = {
                  mountpoint = "/";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };

                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };

                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };

                "@swap" = {
                  mountpoint = "/swap";
                  swap.swapfile.size = "40G";
                };
              };
            };
          };
        };
      };
    };
  };
}
