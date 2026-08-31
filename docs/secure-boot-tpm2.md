# Secure Boot / TPM2 after installation

Last updated: 2026-08-31

This guide applies to:

- `thinkpad-x1-carbon-gen13` — Lenovo ThinkPad X1 Carbon Gen 13
- `hp-z2-tower-g9` — HP Z2 Tower G9

It does **not** apply to `apple-macbook-air-8-1`. The MacBook profile uses a separate systemd-boot/T2/dual-boot architecture without EFI NVRAM writes. See `apple-macbook-air-8-1-install.md` and `apple-macbook-air-8-1-postinstall.md` for that system.

## Before reinstallation

For ThinkPad/HP:

- disable Secure Boot in UEFI;
- place the firmware in Secure Boot Setup Mode;
- boot the NixOS installation medium in UEFI mode;
- preferably use the version-matched installation package from the NixOS release.

The combined release package contains the matching NixOS state plus Home Manager at the same release tag. See `install-package.md`.

The direct root installers remain available for development/recovery:

```bash
sudo ./install-thinkpad-x1-carbon-gen13.sh
sudo ./install-hp-z2-tower-g9.sh
```

Both x86 installers select the target disk at runtime. With no disk argument they display available whole disks and ask for a selection; an explicit whole-disk path may be supplied as the optional first argument. No disk serial or fixed disk ID is stored in Git.

## Local identity and deployment data

After activation, all canonical machine-local NixOS recovery state lives below `/etc/nixos/local/`:

```text
/etc/nixos/local/
├── profile.nix
├── identity.json
└── deployment.json
```

`configuration.nix` imports `local/profile.nix`. `local/identity.json` contains the hostname, local username and display name:

```json
{
  "hostName": "<hostname>",
  "userName": "<user>",
  "fullName": "Example User"
}
```

Optional deployment-specific infrastructure is stored in `local/deployment.json`. Use it for values such as Nix remote-builder endpoints or authorized builder client keys rather than embedding those values into hardware profiles. An empty deployment is `{}`.

During installer bootstrap only, root-level `profile.nix`, `identity.json` and optional `deployment.json` are accepted temporarily. NixOS activation migrates them into `local/` automatically.

There is no committed initial password hash. After `nixos-install`, the installer sets a fresh local user password.

## First boot

Check the base state:

```bash
systemctl --failed
findmnt /
findmnt /home
findmnt /nix
findmnt /swap
swapon --show
bootctl status
lsblk -f
cat /etc/nixos/local/profile.nix
cat /etc/nixos/local/identity.json
cat /etc/nixos/local/deployment.json
```

## Prepare Secure Boot / Lanzaboote

```bash
sudo /etc/nixos/post-install-security.sh prepare
```

This step verifies UEFI Setup Mode, disabled Secure Boot, canonical local profile/identity files and the Secure Boot module. It creates sbctl keys when required, changes `local/profile.nix` from the installation profile to the normal hardware profile and runs `nixos-rebuild switch`. If the rebuild fails, the previous profile selector is restored.

## Enroll Secure Boot keys

```bash
sudo /etc/nixos/post-install-security.sh enroll-secureboot
```

Then reboot and verify:

```bash
sudo /etc/nixos/post-install-security.sh status
sudo bootctl status
```

Secure Boot should be enabled and the UKI should be measured.

## TPM2 + PIN

Enroll TPM2 only after Secure Boot is working and the PCRLock policy exists at `/var/lib/systemd/pcrlock.json`:

```bash
sudo /etc/nixos/post-install-security.sh enroll-tpm
```

The LUKS recovery passphrase remains available.

## `/etc/nixos` permissions

The repository remains administratively owned by `root:wheel`. Shared NixOS configuration provides group access, setgid behavior and ACL inheritance. Do not work around permissions by recursively changing ownership to a personal user.

The canonical `local/` directory is created as `root:wheel` and is not tracked by Git.

## Disk layout

ThinkPad and HP use:

- 2 GiB ESP
- LUKS2
- Btrfs
- `@root`
- `@home`
- `@nix`
- `@swap`
- 40 GiB swapfile

Verify with:

```bash
findmnt /
findmnt /home
findmnt /nix
findmnt /swap
swapon --show
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPE,PARTLABEL,MOUNTPOINTS
```

## ThinkPad-specific checks

```bash
mmcli -L
nmcli connection show
usb-pd-status
```

A `nixos-rebuild switch` can briefly interrupt the WWAN connection.

Device-specific EasyEffects tuning is generated during installer preflight and kept below ignored `audio/easyeffects/local/`. A fresh installation uses the generated `Dolby-Dynamic-Balanced` baseline. An optional user-adjusted default may later be saved under ignored `audio/easyeffects/local/override/`. A clean checkout without local generated tuning remains buildable and does not enable an autoload rule that requires a missing IRS file.

## HP Z2-specific checks

```bash
lspci -nnk | grep -A3 -E 'VGA|Display|3D'
vainfo
nvtop
```

Expected graphics are Intel UHD 770 using `i915` and Radeon RX 7600 XT using `amdgpu`.

The profile can expose the restricted `nix-ssh` builder service when `local/deployment.json` supplies authorized client keys. No client key or remote-builder address is part of the hardware profile itself.

## Home Manager

On a fresh installation, Home Manager is already prepared and activated before the first graphical login. A manual `home-manager switch` is therefore no longer part of the normal initial-install workflow.

On an installed system, Topgrade selects the local hardware profile automatically.

## Backup

The NixOS recovery backup helper is available at:

```bash
sudo /etc/nixos/scripts/backup-config.sh /path/to/external-backup-target
```

It backs up exactly `/etc/nixos/local/`: `profile.nix`, `identity.json` and `deployment.json`. The public repository, release/update locks, downloaded Apple fonts, wallpaper, optional vendor assets and generated EasyEffects baseline are reproducible and deliberately excluded.

Secure Boot keys and TPM enrollment are also not part of this backup; they are recreated during a fresh installation.
