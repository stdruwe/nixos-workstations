# NixOS workstation configuration

Declarative NixOS configuration for three technical hardware profiles with a
shared system base, explicit desktop selection and a version-matched Home
Manager installation workflow.

## Hardware profiles

- `thinkpad-x1-carbon-gen13` — Lenovo ThinkPad X1 Carbon Gen 13, Intel Lunar Lake, KDE Plasma 6 / Wayland, WWAN/GNSS.
- `hp-z2-tower-g9` — HP Z2 Tower G9, Intel Core i7-12700K, Intel UHD 770 + Radeon RX 7600 XT, KDE Plasma 6 / Wayland.
- `apple-macbook-air-8-1` — Apple MacBookAir8,1 (2018/T2), Intel Core i5-8210Y, Intel UHD Graphics 617, COSMIC / Wayland.

Hardware profile, hostname, username and deployment-specific infrastructure are
independent. Ignored `profile.nix` selects only the technical hardware profile,
ignored `identity.json` supplies machine/user identity, and optional ignored
`deployment.json` supplies local infrastructure such as SSH authorized keys,
remote-builder data, desktop integration endpoints and Topgrade policy.

## Repository layout

```text
configuration.nix              # hardware/identity-neutral entry point
profile.nix                    # local, ignored hardware selector
identity.json                  # local, ignored hostname/user identity
deployment.json                # optional, ignored deployment infrastructure
lon.nix / lon.lock             # tracked bootstrap external-source state
.local-sources/                # ignored machine-local Topgrade source state

hosts/                         # hardware-specific profiles
modules/common/                # shared desktop-neutral modules
modules/desktops/              # Plasma / COSMIC selection
modules/features/              # optional reusable features
pkgs/                          # local Nix packages
assets/                        # tracked Plymouth scripts and ignored local assets
audio/                         # EasyEffects metadata and ignored local tuning
scripts/                       # maintenance/install helper scripts
docs/                          # operational documentation

install.sh                     # canonical profile-selecting installer
install-thinkpad-x1-carbon-gen13.sh
install-hp-z2-tower-g9.sh
install-apple-macbook-air-8-1.sh
```

The tracked `lon.nix`, `lon.lock` and `pkgs/filebot-source.nix` files are
bootstrap/fallback state for clean checkouts and installations. After the first
Topgrade run, each machine uses ignored copies under
`/etc/nixos/.local-sources/`; later local dependency updates do not modify or
publish repository files.

## Public repositories and releases

The public repository pair is intended to be:

- `stdruwe/nixos-workstations`
- `stdruwe/home-manager-workstations`

Both repositories use the same semantic-version tag. The public history starts
at `v0.1.0`; version numbers from the private development repositories are not
continued.

Publishing a NixOS release builds and attaches:

```text
nixos-install-vX.Y.Z.tar.zst
nixos-install-vX.Y.Z.tar.zst.sha256
```

The archive contains a clean NixOS checkout, the matching Home Manager state as
a local Git bundle, snapshot metadata and the same tracked `install.sh`
dispatcher used by a normal checkout. Public HTTPS read remotes are used, so a
consumer does not need a GitHub account or SSH key for normal updates.

See [`docs/install-package.md`](docs/install-package.md) and
[`docs/home-manager-install-bundle.md`](docs/home-manager-install-bundle.md).

## Preferred fresh-install workflow

`install.sh` is the preferred user-facing entry point. It selects one of the
three technical hardware profiles and forwards profile-specific arguments
unchanged. The hardware-specific scripts remain executable implementation entry
points for development and recovery.

The ThinkPad and HP installers select the target disk at runtime. They contain
no SSD serial numbers or fixed `/dev/disk/by-id` targets. Before destructive
execution, the selected device is displayed and the installer requires an exact
`ERASE /dev/...` confirmation.

Examples:

```bash
sudo ./install.sh thinkpad-x1-carbon-gen13
sudo ./install.sh hp-z2-tower-g9 /dev/nvme0n1
```

The MacBook installer is intentionally different. It is bound to the internal
T2 dual-boot disk, validates Apple EFI p1 and macOS/APFS p2 structurally, and
may recreate or format only the Linux p3/p4 area. It stores no machine-specific
Apple PARTUUIDs or fixed sector boundaries in Git. Read-only validation is
available with:

```bash
sudo ./install.sh apple-macbook-air-8-1 --layout-check
```

## Installation preflight

Before destructive disk confirmation the installer:

- validates the supplied Home Manager bundle and selected Home Manager profile;
- writes ignored local `identity.json` and `profile.nix` into the working copy;
- downloads the shared wallpaper from its documented KDE Store source;
- downloads and extracts SF Pro, SF Mono and New York from Apple's Developer CDN;
- on the ThinkPad, downloads the pinned Lenovo audio package, extracts the matching tuning XML and generates all local EasyEffects presets/IRS files;
- evaluates the selected NixOS configuration;
- performs a Disko dry run where applicable.

A failure in these preparation steps therefore occurs before the installer is
allowed to erase a disk.

## Home Manager before first graphical login

Home Manager is part of the installation contract. The installer validates the
selected `homeConfigurations.<profile>.activationPackage` before destructive
disk confirmation, copies the matching repository into the target home and
builds the activation closure directly into the target Nix store.

`modules/common/home-manager-initial.nix` provides a one-shot service ordered
before the display manager. The first Plasma/COSMIC login cannot start until the
prepared Home Manager activation has completed successfully.

## Storage and boot

All three systems use LUKS2 + Btrfs with `@root`, `@home`, `@nix` and `@swap`
subvolumes. ThinkPad and HP use a 40 GiB Btrfs swapfile; the MacBook profile uses
16 GiB.

ThinkPad and HP use Disko plus Lanzaboote/Secure Boot/TPM2. The post-install
sequence is documented in [`docs/secure-boot-tpm2.md`](docs/secure-boot-tpm2.md).

The `apple-macbook-air-8-1` profile uses a separate dual-boot model: Apple EFI
p1 and macOS/APFS p2 are protected, p3 is a 2 GiB `NIXOS-ESP` derived from the
first aligned sector after p2, p4 uses the remaining disk space as
`NIXOS-LUKS`, and NixOS writes no EFI-NVRAM boot entry. Unknown existing p3/p4
partitions are never deleted automatically.

See [`docs/apple-macbook-air-8-1-install.md`](docs/apple-macbook-air-8-1-install.md)
and [`docs/apple-macbook-air-8-1-postinstall.md`](docs/apple-macbook-air-8-1-postinstall.md).

## Wallpaper and Plymouth assets

The shared wallpaper is not stored in Git. `scripts/fetch-wallpaper.sh` resolves
KDE Store content `1189184` through the OCS API and stores the downloaded image
under ignored `assets/local/`.

Installation fetches the image before the first NixOS build. A best-effort
systemd service can restore a missing local copy later. Clean checkouts remain
buildable without it and use a black Plymouth fallback.

The ThinkPad, HP and Apple Plymouth backgrounds are generated during the Nix
build from the same local wallpaper at the profile's required aspect ratio and
resolution. Vendor logos are also local-only and optional. See
[`docs/third-party-material.md`](docs/third-party-material.md).

## ThinkPad audio profiles

Device-specific EasyEffects tuning is generated locally from the documented
Lenovo driver source with `scripts/generate-thinkpad-easyeffects-local.sh`.
The generated 27 preset JSON files and 27 IRS files live under ignored
`audio/easyeffects/local/` and are not stored in Git.

The ThinkPad installer performs this generation during preflight. The generated
`Dolby-Dynamic-Balanced` preset is the default on a fresh installation. A later
user-adjusted copy can be saved with
`scripts/save-thinkpad-easyeffects-default.sh`; that override remains under
ignored `audio/easyeffects/local/override/` and is layered over the generated
baseline locally.

A clean checkout without local tuning remains buildable and does not install an
autoload rule that would reference a missing IRS file.

## Optional local deployment infrastructure

`deployment.json` is optional and ignored. Hardware profiles remain buildable
without it.

It can provide personal user SSH authorized keys, Nix builder data, local
display layout information, desktop integration data and user-level service
endpoints consumed by Home Manager. Example:

```json
{
  "plasma": {
    "dolphinBookmark": {
      "title": "fileserver",
      "url": "smb://fileserver"
    }
  },
  "hermes": {
    "habUrl": "http://homeassistant.example:8123",
    "ollamaBaseUrl": "http://ollama.example:11434/v1"
  },
  "topgrade": {
    "updateManagedDependencies": true
  }
}
```

Personal SSH keys, addresses, SSH host keys, builder authorization keys, service
endpoints and display identities therefore do not need to be embedded in the
hardware profiles.

## Fonts

All three systems use the same Apple font defaults:

- sans-serif: SF Pro
- serif: New York
- monospace: SF Mono

The font files are not stored in Git. Installation and
`scripts/update-apple-fonts.sh` retrieve SF Pro, SF Mono and New York directly
from Apple's official Developer CDN and populate ignored `fonts/apple/`.

## Updates

Topgrade is the central manual update path.

- every machine pulls its configured NixOS and Home Manager upstreams with `--ff-only`;
- no normal Topgrade run commits or pushes dependency updates upstream;
- NixOS managed-source state is machine-local under `/etc/nixos/.local-sources/`;
- Home Manager keeps tracked `flake.lock.bootstrap`, while live `flake.lock` is ignored;
- local managed-dependency candidates are retained only after current-profile validation;
- Topgrade's built-in NixOS `system` step is disabled; `topgrade.nix` owns the guarded update path;
- before advancing the root channel, the current profile is fully built against the current `nixos-unstable` candidate;
- if that candidate fails, Topgrade reports `NixOS system update: SKIPPED`, leaves the installed channel/system unchanged, exposes the build failure/log and continues the remaining update steps;
- after a successful channel update, the installed channel is built again before activation; a failed second check rolls the channel back;
- `deployment.json` can set `topgrade.updateManagedDependencies = false` without disabling the NixOS candidate safety build;
- `nixos-needsreboot --dry-run` reports whether reboot is required; reboot is never automatic.

This model allows a public-repository consumer to update without write access to
the upstream repositories and keeps per-machine dependency state independent
from repository releases.

When checking package versions, compare the configured `nixos-unstable` channel
with `nixos-unstable`, never nixpkgs `master`.

## CI and release packaging

`.github/workflows/ci.yml` performs Bash syntax/ShellCheck validation for the
tracked Bash installer/support surface, Zsh syntax validation for the macOS
helper, Python syntax validation for the EFIRES helper, actionlint validation,
NixOS evaluation of all three profiles, and a real build of every profile's
Plymouth theme package.

CI deliberately tests the tracked bootstrap/fallback state, proving a clean
checkout does not require machine-local `.local-sources/`, `deployment.json`,
wallpaper, vendor logos or ThinkPad tuning.

`.github/workflows/release-install-package.yml` checks out the matching tag from
the public Home Manager repository and builds the combined installation archive.
No cross-repository read secret is required for public releases.

## Local/non-Git data

The following are intentionally machine-local and ignored:

- `profile.nix`
- `identity.json`
- optional `deployment.json`
- `.local-sources/`
- `fonts/apple/`
- `assets/local/` including wallpaper and optional vendor logos
- `audio/easyeffects/local/` including generated tuning and optional user override
- secrets, private keys, credentials and agent sockets

`/etc/nixos` remains administratively owned by `root:wheel` with group-write,
setgid and ACL handling for administrators.

Third-party provenance and licensing boundaries for the material that is
referenced, downloaded or redistributed are documented in
[`docs/third-party-material.md`](docs/third-party-material.md).

For the durable operational baseline, read [`CURRENT-STATE.md`](CURRENT-STATE.md).
