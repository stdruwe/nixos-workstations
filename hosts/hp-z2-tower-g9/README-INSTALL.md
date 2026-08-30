# Installation – `hp-z2-tower-g9`

Last updated: 2026-08-29

The preferred fresh-install path is the combined version-matched package attached to the NixOS release. It contains the matching NixOS state and Home Manager at the same release tag.

After extracting the package:

```bash
sudo ./install.sh hp-z2-tower-g9
```

The dispatcher starts the hardware-specific root installer:

```text
install-hp-z2-tower-g9.sh
```

## Target disk

No SSD serial number or fixed `/dev/disk/by-id` path is stored in the repository.

When the hardware installer is started without a disk argument, it lists available whole-disk block devices with size/model/transport information and asks for a target selection. It rejects a selected disk if any filesystem on it is mounted.

For direct development/recovery use, a whole-disk path may instead be supplied explicitly:

```bash
sudo ./install-hp-z2-tower-g9.sh /dev/nvme0n1
```

Before destructive execution the installer validates:

- UEFI / Secure Boot Setup Mode;
- the selected target as an existing whole-disk block device;
- that no filesystem on the selected target is mounted;
- the complete NixOS target configuration;
- the matching Home Manager activation package;
- the pinned Disko runner and the Disko configuration with the selected `device` argument.

Only after all preflight checks succeed does it accept the exact destructive confirmation:

```text
ERASE /dev/<selected-disk>
```

The Disko layout is:

- 2 GiB ESP;
- LUKS2;
- Btrfs with `@root`, `@home`, `@nix`, `@swap`;
- 40 GiB swapfile.

The chosen disk is supplied to `hosts/hp-z2-tower-g9/disko.nix` at runtime with Disko's `device` argument. Other installed disks are not declared as Disko targets.

## Secure Boot / TPM2

Installation initially uses the technical installation profile `hosts/hp-z2-tower-g9/installation.nix`. After the first boot, continue with:

```bash
sudo /etc/nixos/post-install-security.sh prepare
```

This changes local `profile.nix` to `hosts/hp-z2-tower-g9/default.nix`, creates Secure Boot keys when required, and builds the Lanzaboote configuration.

Then run `enroll-secureboot`, reboot/verify, and finally `enroll-tpm` as documented in `../../docs/secure-boot-tpm2.md`.

There is no need to make `configuration.nix` hostname-specific or to add `secureboot.nix` manually.

## Direct development/recovery invocation

If a valid local Home Manager bundle is already available, the installer may be started directly from the repository root with either interactive disk selection:

```bash
sudo ./install-hp-z2-tower-g9.sh
```

or an explicit target disk:

```bash
sudo ./install-hp-z2-tower-g9.sh /dev/nvme0n1
```

Hostname, username and display name are collected locally during installation and stored in untracked `profile.nix` and `identity.json` files.
