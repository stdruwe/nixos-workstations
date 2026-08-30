{ lib, pkgs, ... }:

let
  sources = import ./lon.nix;

  # Lanzaboote 1.1.0 pins a rust-overlay revision that still uses the deprecated
  # stdenv.isLinux/isDarwin aliases. Override only that upstream input with the
  # fixed, Lon-pinned revision; remove this override once a Lanzaboote release
  # ships a corrected rust-overlay pin itself.
  lanzaboote = import sources.lanzaboote {
    inherit pkgs;
    rust-overlay = sources.rust-overlay;
  };
in
{
  imports = [
    lanzaboote.nixosModules.lanzaboote
  ];

  # Lanzaboote assumes the responsibilities of systemd-boot.
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # Start the current default entry directly on all Secure Boot systems without
  # a boot-menu delay. The menu remains reachable through the normal
  # systemd-boot/Lanzaboote key sequence when needed.
  boot.loader.timeout = lib.mkForce 0;

  # The root LUKS volume is discovered through the Discoverable Partitions
  # Specification by systemd-gpt-auto-generator. systemd-cryptsetup uses the
  # TPM2 token stored in the LUKS2 header automatically, so no fixed UUID or
  # boot.initrd.luks.devices entry is required.

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    configurationLimit = 8;

    measuredBoot = {
      enable = true;

      pcrs = [
        4
        7
      ];

      # No autoCryptenroll: TPM2 is enrolled manually with a PIN later.
    };
  };

}
