# Current State

Last updated: 2026-08-31

This file is the durable operational baseline for the NixOS repository. Read it
before persistent changes. Keep transient debugging experiments out of this
file.

## Repository role

- intended public repository: `stdruwe/nixos-workstations`
- matching public Home Manager repository: `stdruwe/home-manager-workstations`
- canonical installed path: `/etc/nixos`
- traditional NixOS configuration, not a NixOS flake
- public version history starts at `v0.1.0`
- `configuration.nix` is tracked and hardware/identity-neutral
- ignored local `profile.nix` selects one technical hardware profile
- ignored local `identity.json` provides hostname and local user identity
- optional ignored local `deployment.json` provides deployment-specific infrastructure
- tracked `lon.nix`, `lon.lock` and `pkgs/filebot-source.nix` are clean-checkout/bootstrap state
- ignored `.local-sources/` contains machine-local managed source state

Hardware profile, hostname, username and deployment infrastructure are
independent. Documentation and tracked code use technical profile names or
hardware classes rather than deployment-specific hostnames, addresses or
personal usernames.

## Managed profiles

### `thinkpad-x1-carbon-gen13`

- Lenovo ThinkPad X1 Carbon Gen 13 / Intel Lunar Lake
- OLED 2880x1800
- KDE Plasma 6 / Wayland
- WWAN/GNSS support
- runtime target disk selection; no disk serial or fixed disk ID in Git
- local ThinkPad logo fetched from documented upstream source when available
- local EasyEffects tuning generated from the pinned Lenovo package during installer preflight
- fresh install generates 27 preset JSON files and 27 IRS files under ignored `audio/easyeffects/local/`
- generated `Dolby-Dynamic-Balanced` is the fresh-install default
- optional user-adjusted default lives only under ignored `audio/easyeffects/local/override/`
- clean checkout remains buildable without local tuning

### `hp-z2-tower-g9`

- HP Z2 Tower G9
- Intel Core i7-12700K
- Intel UHD Graphics 770 + Radeon RX 7600 XT
- KDE Plasma 6 / Wayland
- runtime target disk selection; no disk serial or fixed disk ID in Git
- fixed 96 kHz PipeWire graph for the profile
- ESPHome Device Builder remote-build worker remains profile-specific
- optional builder authorization comes only from local `deployment.json`
- HP Plymouth logo is optional machine-local data

### `apple-macbook-air-8-1`

- Apple MacBookAir8,1 / T2
- Intel Core i5-8210Y / Intel UHD Graphics 617
- COSMIC / Wayland
- macOS/APFS retained in dual boot
- Apple EFI p1 and macOS/APFS p2 are protected by the installer
- NixOS uses derived p3 `NIXOS-ESP` and p4 `NIXOS-LUKS`
- no machine-specific Apple PARTUUIDs or fixed sector boundaries in Git
- optional `ssh-ng` remote builder is deployment-local
- Apple Plymouth logo is optionally extracted from the machine's own EFIRES resource

## Local identity and deployment

`modules/common/identity.nix` validates local identity and provides hostname,
username, full name and home directory.

`modules/common/deployment.nix` reads optional ignored `deployment.json`. A
missing file is valid. It can supply:

- user SSH authorized keys
- Nix remote-builder endpoint/key data
- desktop integration data
- user-level service endpoints consumed by Home Manager
- Topgrade policy

Example Topgrade policy:

```json
{
  "topgrade": {
    "updateManagedDependencies": true
  }
}
```

`topgrade.updateManagedDependencies` defaults to `true`. Setting it to `false`
freezes machine-local managed dependency advancement while repository sync and
normal activation remain enabled.

No password hash, personal SSH key, deployment hostname/address or service
endpoint belongs in the tracked hardware profiles.

## Local assets and fonts

The following are intentionally ignored and machine-local:

- `fonts/apple/`
- `assets/local/`
- `audio/easyeffects/local/`
- `.local-sources/`
- `profile.nix`
- `identity.json`
- optional `deployment.json`

### Shared wallpaper

The wallpaper is not stored in Git. `scripts/fetch-wallpaper.sh` resolves KDE
Store content `1189184` through the OCS API. Exactly one of these canonical
machine-local files may exist under ignored `assets/local/`:

```text
wallpaper.png
wallpaper.jpg
wallpaper.jpeg
```

Multiple variants are rejected as a configuration error. Zero variants remain
valid for a clean checkout so CI and fallback builds do not require third-party
local data.

Fresh installers fetch the wallpaper during non-destructive preflight. A
best-effort systemd repair service can restore a missing local copy later. The
selected source is shared by:

- Plymouth
- Plasma desktop
- Plasma lock screen
- Plasma Login Manager
- COSMIC desktop and lock screen
- COSMIC greeter

Plasma synchronizes the selected wallpaper during NixOS activation and again at
login. Plasma Login Manager receives the native KConfig drop-in
`/etc/plasmalogin.conf.d/zz-nixos-wallpaper.conf`; nested KDE KConfig groups are
not rendered through the generic Nix INI formatter.

Plymouth derives profile-specific backgrounds from the same source:

- ThinkPad: 2880x1800
- HP: 1920x1080
- MacBook: 2560x1600

Clean checkouts remain buildable without the wallpaper and use a black Plymouth
fallback.

### Apple fonts

All three profiles use the same system font policy:

- SF Pro as sans-serif
- SF Mono as monospace
- New York at Medium weight (`wght=500`) as normal serif

`New York Medium` is a semantic Fontconfig alias backed by Apple's New York
variable family. Normal serif requests are promoted to the Medium instance;
explicit stronger weights are not flattened to Medium. Firefox, Zen Browser and
Thunderbird use the same SF Pro / New York Medium / SF Mono generic defaults.

Installation and `scripts/update-apple-fonts.sh` obtain SF Pro, SF Mono and New
York from Apple's Developer CDN. Font binaries are never stored in Git.

## ThinkPad EasyEffects model

`scripts/generate-thinkpad-easyeffects-local.sh`:

1. downloads the pinned Lenovo audio-driver package;
2. verifies its SHA-256;
3. extracts the exact SoundWire tuning XML with `innoextract`;
4. checks out the pinned `speaker-tuning-to-easyeffects` release/commit;
5. generates all 27 preset JSON files and all 27 IRS files;
6. atomically refreshes only ignored `audio/easyeffects/local/output/` and `irs/`.

The ThinkPad installer performs this before destructive disk confirmation. The
local generator output is copied into the target configuration and participates
in the first NixOS build.

`scripts/save-thinkpad-easyeffects-default.sh` optionally saves the current
runtime `Dolby-Dynamic-Balanced.json` to ignored
`audio/easyeffects/local/override/`. The audio module layers this local override
over the generated baseline when present.

No device-specific Dolby/OEM-derived tuning output is stored in Git.

## Storage and boot

All systems use LUKS2 + Btrfs with `@root`, `@home`, `@nix` and `@swap`.
ThinkPad and HP use 40 GiB swapfiles; MacBook uses 16 GiB.

ThinkPad and HP use Disko plus Lanzaboote/Secure Boot/TPM2. Their installers
accept/select a whole-disk target at runtime and require exact
`ERASE /dev/...` confirmation.

The MacBook installer validates the fixed T2 dual-boot structure and only
recreates/formats Linux p3/p4. Unknown existing p3/p4 partitions are not
automatically removed. `--layout-check` is read-only.

## Home Manager installation contract

The installer requires a matching Home Manager bundle, validates the selected
`homeConfigurations.<profile>.activationPackage` before destructive actions,
and builds the activation closure directly into the target Nix store.

`modules/common/home-manager-initial.nix` activates that prepared configuration
before the first graphical login.

For public releases, the read remote is:

```text
https://github.com/stdruwe/home-manager-workstations.git
```

No cross-repository read token is required when both repositories are public.
The Home Manager live `flake.lock` remains ignored and machine-local; manual
Home Manager evaluation against an installed checkout therefore uses explicit
`path:.#<profile>` references.

## Public release model

The public repository pair starts again at `v0.1.0` rather than continuing the
private development version sequence. Both repositories must carry the same
release tag.

The NixOS release workflow builds:

```text
nixos-install-vX.Y.Z.tar.zst
nixos-install-vX.Y.Z.tar.zst.sha256
```

The archive contains the matching NixOS checkout, a matching Home Manager Git
bundle, exact snapshot metadata and the canonical `install.sh` dispatcher.

Public repository history starts from a clean public baseline; the private
development repositories are not used as installed-system upstreams.

## CI

`.github/workflows/ci.yml` validates:

- all tracked Bash `.sh` files with `bash -n` and ShellCheck
- the macOS Zsh helper with `zsh -n`
- Python helper syntax
- GitHub Actions syntax via actionlint
- all three NixOS profile evaluations
- one real Plymouth theme build per profile

Clean-checkout CI must not depend on local identity beyond CI fixtures,
`deployment.json`, `.local-sources/`, wallpaper, vendor logos or ThinkPad tuning.

## Topgrade

Topgrade is the central manual update workflow.

- repository pulls are fast-forward-only
- normal clients never commit/push dependency updates upstream
- managed NixOS source state is machine-local under `.local-sources/`
- Home Manager live `flake.lock` is ignored and machine-local
- candidate managed-source updates are retained only after current-profile validation
- Topgrade's built-in NixOS `system` step is disabled
- the current profile is fully built against the current `nixos-unstable` candidate before the root channel is advanced
- a rejected candidate reports `NixOS system update: SKIPPED`, leaves the installed channel/system unchanged and allows unrelated Topgrade steps to continue
- after channel update, a second full build is required before activation; failure rolls the channel back
- reboot is never automatic

Topgrade-owned messages and subprocess messages are requested in English. The
system/user locale remains configured for German where intended.

## Third-party provenance

Current third-party, upstream-derived and locally acquired material is described
in `docs/third-party-material.md`. That document describes the present public
model only.

Machine-local vendor logos, Apple fonts, shared wallpaper and device-specific
ThinkPad tuning are not stored in Git. Redistributable upstream-derived tracked
material retains explicit provenance/license context.
