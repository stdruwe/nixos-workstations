# MacBookAir8,1 (2018/T2) – NixOS dual-boot installation

Last updated: 2026-08-31

This guide describes installing NixOS on the verified Apple MacBookAir8,1 (2018, T2) while retaining the existing macOS installation. The technical profile name is `apple-macbook-air-8-1`; hostname and username are chosen locally during installation.

## Verified hardware

- model: MacBookAir8,1 (2018 Retina)
- CPU: Intel Core i5-8210Y
- RAM: 16 GiB
- graphics: Intel UHD Graphics 617
- Apple T2
- SSD: APPLE SSD AP1536M, 1.5 TB, 4096-byte logical sector size
- macOS: Sonoma 14.8.9 (23J631) in the verified dual-boot layout
- T2 firmware: 23P6068

The NixOS profile uses the stable T2 kernel, Sonoma firmware, COSMIC/Wayland and systemd-boot on a separate Linux ESP.

## Installation medium

Verified T2 NixOS ISO:

- release: `t2linux/nixos-t2-iso` v6.18.35
- file: `nixos-t2-iso-minimal.iso`
- SHA256: `29ec02ed3a1e35efd72089b9df339c00cf9a93e8474646e700d60d2a49683194`
- boot with `copytoram`

Use USB Ethernet during installation. The live ISO does not contain all firmware required by the internal Broadcom WLAN; the installed system obtains that firmware declaratively.

## Preferred configuration transport

The public repositories are:

```text
https://github.com/stdruwe/nixos-workstations.git
https://github.com/stdruwe/home-manager-workstations.git
```

The preferred installation path is the version-matched combined package attached to the NixOS release. Public versioning starts at `v0.1.0`, and both repositories use the same release tag.

For example, the `v0.1.0` NixOS release produces:

```text
nixos-install-v0.1.0.tar.zst
nixos-install-v0.1.0.tar.zst.sha256
```

Download both release assets and transfer them to the live system. Then run:

```bash
sha256sum -c nixos-install-v0.1.0.tar.zst.sha256
tar --zstd -xf nixos-install-v0.1.0.tar.zst
cd nixos-install
```

The archive contains the exact NixOS release state, Home Manager at the matching release tag as a local Git bundle, and `INSTALL-SNAPSHOT.txt` containing both commit SHAs. See [`install-package.md`](install-package.md).

Direct hardware-installer use with `HOME_MANAGER_BUNDLE` or `/tmp/home-manager.bundle` remains available for development and recovery.

## Installation over SSH

The MacBook installer refuses an unprotected SSH session for a real installation. If installation is controlled over SSH, run it inside tmux.

If tmux is not available in the live environment:

```bash
nix shell nixpkgs#tmux
```

Then start a session:

```bash
tmux new -s nixos-install
```

Run the installer inside that session. Detach with `Ctrl+B`, then `D`; reconnect with:

```bash
tmux attach -t nixos-install
```

## Protected Apple layout

The installer is bound to the internal disk of the verified MacBookAir8,1 model, but it does not embed machine-specific Apple PARTUUIDs or fixed sector boundaries.

The protected structure is:

- p1 must be a standard EFI System Partition;
- p2 must use the Apple APFS GPT type;
- p1 and p2 must appear in that order and must not overlap;
- neither p1 nor p2 may be mounted when installation begins;
- partitions numbered above p4 are rejected.

At startup the installer reads the current PARTUUID, GPT type, sector bounds and partition name of p1 and p2 and keeps that information only in memory. It rechecks this runtime baseline after the NixOS preflight, immediately before partitioning, after removing/recreating Linux partitions, immediately before formatting and after Linux formatting. Any change to p1 or p2 causes an immediate abort.

No machine-specific p1/p2 identifiers are required in Git.

## Derived Linux area

The Linux layout is derived from the actual end of p2:

- p3 `NIXOS-ESP` starts at the first 1 MiB-aligned sector after p2 and is exactly 2 GiB;
- p4 `NIXOS-LUKS` starts immediately after p3 and extends to the end of the disk.

If compatible `NIXOS-ESP` and `NIXOS-LUKS` partitions already exist at the derived positions, only their filesystems are recreated.

If p3/p4 are missing or their geometry differs, the installer may remove and recreate them only when any existing p3/p4 are already explicitly named `NIXOS-ESP` and `NIXOS-LUKS`. An unknown p3 or p4 is never deleted automatically; the installer aborts instead.

The destructive confirmation remains exactly:

```text
FORMAT ONLY P3 P4
```

## Read-only layout check

The partition-safety logic can be tested without modifying the disk:

```bash
sudo ./install-apple-macbook-air-8-1.sh --layout-check
```

This mode verifies the model, sector size, p1/p2 GPT types, protected runtime baseline, existing p3/p4 identities and the derived future Linux geometry. It exits before channel updates, identity prompts, LUKS handling or any `parted` write command.

## Filesystem layout

- p3: FAT32, label `NIXOS-ESP`
- p4: LUKS2, PARTLABEL `NIXOS-LUKS`
- Btrfs inside LUKS, label `NIXOS`
- subvolumes: `@root`, `@home`, `@nix`, `@swap`
- 16 GiB Btrfs swapfile at `/swap/swapfile`

The profile refers to `/dev/disk/by-partlabel/NIXOS-ESP` and `/dev/disk/by-partlabel/NIXOS-LUKS`. Automatic GPT discovery is intentionally not used for this dual-boot layout.

## T2 ISO caveat: nixpkgs

The T2 ISO may continue resolving `<nixpkgs>` through its `NIX_PATH` to the embedded ISO snapshot even after a channel update.

The MacBook installer therefore updates `nixos-unstable` and explicitly passes that channel path during evaluation and installation with `-I nixpkgs=...`.

Do not use the embedded ISO snapshot as the target package set, and do not confuse `nixos-unstable` with nixpkgs `master`.

## Machine-local recovery state

The installed system keeps exactly three canonical recovery files under ignored `/etc/nixos/local/`:

```text
/etc/nixos/local/profile.nix
/etc/nixos/local/identity.json
/etc/nixos/local/deployment.json
```

The installer initially creates historical root-level bootstrap files because NixOS must evaluate the target before activation. `modules/common/local-state.nix` migrates that bootstrap state into `local/` during the first activation and rewrites the profile import from `./hosts/...` to `../hosts/...`.

Downloaded fonts, wallpaper, the optional Apple logo, managed dependency pins and other reproducible state are deliberately not part of this recovery set. `scripts/backup-config.sh` therefore archives only `/etc/nixos/local/`.

## Shared wallpaper

The wallpaper is not shipped in the repository or installation archive. During non-destructive preflight, the shared installer helper resolves KDE Store content `1189184` through the OCS API and stores exactly one canonical image below ignored `assets/local/` as `wallpaper.png`, `wallpaper.jpg` or `wallpaper.jpeg`.

That same machine-local image is the source for the MacBook Plymouth background, COSMIC desktop/lock screen and COSMIC greeter. The Plymouth build crops it proportionally to 2560×1600. A clean checkout without the local wallpaper remains buildable and uses a black Plymouth fallback.

## Apple fonts

No Apple font archive is shipped in the repository or installation package. The shared installer helper downloads the required families for all three hardware profiles directly from Apple's official Developer servers:

- `SF-Pro.dmg`
- `SF-Mono.dmg`
- `NY.dmg` (New York)

The local source under `fonts/apple/` is replaced only after all three families have been extracted and verified successfully. On an installed system the same process can be repeated with `/etc/nixos/scripts/update-apple-fonts.sh`.

System-wide defaults are SF Pro for sans-serif, SF Mono for monospace and New York at Medium weight (`wght=500`) for normal serif requests. The `New York Medium` semantic Fontconfig alias is owned by NixOS; COSMIC has no separate native serif setting and therefore inherits that system mapping.

## Apple logo / Plymouth

The Apple logo is not redistributed in Git. On the MacBook it is extracted locally from the machine's own macOS/Apple boot resources into ignored `assets/local/apple-logo-2x.png`.

`scripts/import-apple-boot-logo-linux.sh` mounts the selected p1 read-only and validates it structurally as an EFI System Partition instead of pinning a machine-specific PARTUUID. If the optional source asset is unavailable, the Plymouth profile remains buildable through its no-logo fallback.

Asset provenance and licensing notes are tracked in [`third-party-material.md`](third-party-material.md).

## Home Manager before the first login

The bundled Home Manager repository is part of the installation preflight. Before destructive confirmation, the installer verifies the bundle, requires `refs/heads/main`, and evaluates `homeConfigurations.apple-macbook-air-8-1.activationPackage` using the locally entered user identity.

After `nixos-install`, Home Manager is cloned to `~/.config/home-manager` in the target system, its origin is set to the public HTTPS repository, and the selected activation package is built directly into `/mnt/nix`. On the first real boot, `home-manager-initial-activation.service` activates that already-built package as the local user. The service is a required dependency of `display-manager.service`, so COSMIC cannot start before Home Manager activation succeeds.

The first boot therefore needs neither GitHub access nor another download of the activation closure. See [`home-manager-install-bundle.md`](home-manager-install-bundle.md).

## Avoid a full build in the live RAM store

With `copytoram`, the live Nix store resides in a relatively small tmpfs. A full `nixos-rebuild build` can exhaust it.

Before destructive actions the installer therefore performs only the required NixOS and Home Manager evaluations. The actual system build is performed by `nixos-install --root /mnt`, so the large closure is written to the target store under `/mnt/nix`.

## Installation

After networking, package transfer and checksum verification:

```bash
sudo ./install.sh apple-macbook-air-8-1
```

For an SSH-controlled installation, run this command inside the tmux session described above.

The dispatcher sets `HOME_MANAGER_BUNDLE` to the bundled repository automatically and starts `install-apple-macbook-air-8-1.sh` from the packaged NixOS checkout.

The installer:

1. verifies the machine and structurally validates protected p1/p2;
2. snapshots p1/p2 runtime identity and derives p3/p4 geometry;
3. rejects unknown existing p3/p4 partitions;
4. explicitly updates `nixos-unstable`;
5. verifies the local Home Manager bundle;
6. asks for hostname, username and full name;
7. downloads the shared wallpaper from KDE Store;
8. downloads SF Pro, SF Mono and New York directly from Apple;
9. creates root-level profile/identity bootstrap inputs for target evaluation;
10. evaluates NixOS and the selected Home Manager profile;
11. revalidates protected p1/p2 and requires the exact destructive confirmation for p3/p4;
12. asks for the new LUKS recovery passphrase twice;
13. recreates/formats only the recognized Linux p3/p4 area when necessary;
14. creates the Btrfs subvolumes and 16 GiB swapfile;
15. installs NixOS into `/mnt/nix`;
16. sets a fresh local user password;
17. prepares Home Manager and its activation package in the target system;
18. records the one-shot Home Manager activation for the first boot;
19. migrates the bootstrap selector/identity/deployment state into `/etc/nixos/local/` during target activation;
20. configures `/etc/nixos` as `root:wheel` with administrative group access.

All network-dependent wallpaper/font preparation occurs before destructive confirmation.

## User and SSH

The user is created from the locally entered identity that becomes `/etc/nixos/local/identity.json`. Hostname and username are not part of the technical profile name.

There is no committed password hash or personal SSH public key. Optional user SSH authorized keys are read from `/etc/nixos/local/deployment.json` field `userAuthorizedKeys`; private keys and agent sockets remain outside the repository.

## Bootloader

The MacBook profile uses its own Linux ESP and systemd-boot. The Apple EFI partition is not mounted as `/boot`.

```nix
boot.loader.efi.canTouchEfiVariables = false;
```

NixOS creates no EFI NVRAM entries. The Linux ESP contains the fallback loader `EFI/BOOT/BOOTX64.EFI`, which Apple's Startup Manager can select.

## After the first boot

```bash
systemctl --failed
systemctl status home-manager-initial-activation.service
findmnt /
findmnt /home
findmnt /nix
findmnt /swap
swapon --show
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTUUID,PARTTYPE,PARTLABEL,MOUNTPOINTS
bootctl status
cat /etc/nixos/local/profile.nix
cat /etc/nixos/local/identity.json
cat /etc/nixos/local/deployment.json
```

After successful initial Home Manager activation, `/var/lib/nixos/home-manager-initial-activation` must no longer exist.

Verified T2 runtime constraints and workarounds are documented in [`apple-macbook-air-8-1-postinstall.md`](apple-macbook-air-8-1-postinstall.md).
