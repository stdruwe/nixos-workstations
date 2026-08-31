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
- canonical machine-local recovery state lives only under `/etc/nixos/local/`
- `local/profile.nix` selects one technical hardware profile
- `local/identity.json` provides hostname and local user identity
- `local/deployment.json` provides optional deployment-specific infrastructure; an empty deployment is `{}`
- tracked `lon.nix`, `lon.lock` and `pkgs/filebot-source.nix` are clean-checkout/bootstrap state
- ignored `.local-sources/` contains machine-local managed source state

Exactly three files make up the canonical NixOS recovery state:

```text
/etc/nixos/local/profile.nix
/etc/nixos/local/identity.json
/etc/nixos/local/deployment.json
```

Root-level `profile.nix`, `identity.json` and `deployment.json` are accepted only
as installer/bootstrap inputs. `modules/common/local-state.nix` migrates them to
`local/` during activation. Generated assets, downloaded fonts, local tuning,
managed-source pins and tracked release/bootstrap state are deliberately outside
this recovery set because they are reproducible or maintained separately.

Hardware profile, hostname, username and deployment infrastructure are
independent. Documentation and tracked code use technical profile names or
hardware classes rather than deployment-specific hostnames, addresses or
personal usernames.

## Managed profiles

### `thinkpad-x1-carbon-gen13`

- Lenovo ThinkPad X1 Carbon Gen 13 / Intel Lunar Lake
- OLED 2880x1800
- KDE Plasma 6 / Wayland
- WWAN/GNSS hardware support remains profile-specific
- WWAN carrier connection name/APN are optional deployment-local data under `networking.wwan`; no provider is embedded in the hardware profile
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
- optional builder authorization comes only from `local/deployment.json`
- HP Plymouth logo is optional machine-local data
- Radeon-specific `amdgpu_top` is installed only for this hardware profile
- the deployment-specific KScreen layout is intentionally applied 30 seconds after login
- the matching Home Manager one-time second-panel bootstrap waits 35 seconds
- the 30 s / 35 s ordering prevents Plasma from creating unnecessary duplicate application bars/panels while the monitor topology is still settling

The HP Plasma timing is a deliberate cross-repository invariant. Plasma first
starts with the login-time display state; only after 30 seconds does NixOS apply
the final two-monitor KScreen layout. Home Manager then leaves a five-second
margin and performs the one-time second-panel bootstrap at 35 seconds. This
ordering was introduced because applying the final layout and creating panels
too early caused Plasma to create or migrate multiple application bars while
screen topology was changing. Do not change `plasmaDisplayLayout.delaySeconds`
or the Home Manager bootstrap delay independently; review and test both sides
together.

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

`modules/common/identity.nix` validates `local/identity.json` and provides
hostname, username, full name and home directory. During installer evaluation it
accepts the historical root-level `identity.json` as a bootstrap fallback only.

`modules/common/deployment.nix` reads `local/deployment.json`. During installer
evaluation it may fall back to root-level `deployment.json`; absence is treated
as an empty deployment. Activation ensures that canonical
`local/deployment.json` exists and contains at least `{}`.

Deployment data can supply:

- user SSH authorized keys
- local physical subnets that must outrank overlapping overlay routes
- optional WWAN connection name/APN for the WWAN-capable ThinkPad profile
- Nix remote-builder endpoint/key data
- desktop integration data
- user-level service endpoints consumed by Home Manager
- Topgrade policy

The canonical key reference and examples are in `docs/deployment-json.md`.

`networking.localSubnets` installs policy-routing rules at priority `2500` that
prefer specific routes from the main table while suppressing that table's
default route. This keeps directly connected LAN traffic local when a Tailscale
subnet route overlaps the same prefix, while still allowing the Tailscale route
to win when the workstation is away from that LAN.

`networking.wwan` is optional and currently consumed only by the ThinkPad
profile. When present it contains the deployment-specific NetworkManager
connection name and APN. ModemManager/FCC unlock, GNSS, the RM520N-GL D3cold
workaround and the bounded ModemManager shutdown timeout remain hardware/profile
behavior even when no carrier connection is declared.

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

No password hash, personal SSH key, deployment hostname/address, service
endpoint, mobile carrier connection name or APN belongs in the tracked hardware
profiles.

## Local generated assets and fonts

The following are ignored and machine-local but are **not** part of the
canonical NixOS recovery state:

- `fonts/apple/`
- `assets/local/`
- `audio/easyeffects/local/`
- `.local-sources/`

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
York from Apple's Developer CDN. Font binaries are never stored in Git and are
not required in recovery backups.

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

## Diagnostics and mobile-device tooling

Shared diagnostics are kept in dedicated common modules rather than expanding
the generic package list indiscriminately.

`modules/common/diagnostics.nix` provides hardware/firmware, storage/recovery,
network, graphics/display, TPM/UEFI and performance tools. Wireshark is enabled
through the NixOS module and the configured workstation user receives capture
access through the `wireshark` group. Kernel `perf` is taken from the selected
kernel package set.

`modules/common/mobile-tools.nix` provides:

- Android `adb` and `fastboot` via `android-tools`
- `scrcpy`
- `picocom` and `dfu-util`
- `usbmuxd`
- `libimobiledevice`, `ifuse`, `idevicerestore`, `libirecovery`,
  `ideviceinstaller` and `libplist`

`pymobiledevice3` is intentionally not installed while its current nixpkgs
`pyimg4` dependency is marked broken because of the upstream `asn1 >= 3`
compatibility issue. Do not enable global `allowBroken` for this package; re-add
it when nixpkgs carries a working dependency chain.

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

## Backup and recovery

`scripts/backup-config.sh` backs up only `/etc/nixos/local/`. It requires the
three canonical files and creates a compressed archive, SHA-256 checksum and
manifest. The public Git checkout, `.local-sources/`, downloaded/generated
assets, release locks and other reproducible state are intentionally excluded.

This keeps recovery responsibilities explicit: restore the three local files,
obtain the public repository state, then let the normal installer/update paths
regenerate everything else.

## Public release model

The public repository pair starts again at `v0.1.0` rather than continuing the
private development version sequence. Both repositories must carry the same
release tag.

The required publication order is Home Manager first and NixOS second. The
matching Home Manager tag must already exist when the NixOS GitHub release is
published because the NixOS release workflow immediately checks out that tag to
build the combined installation package. `docs/release-process.md` is the
canonical pre-release, publication and post-release checklist.

Tracked `lon.nix`, `lon.lock` and `pkgs/filebot-source.nix` together form the
NixOS clean-checkout/release bootstrap dependency state. The `Refresh NixOS
release lock` workflow can be run manually before a release and also checks
weekly. It refreshes `lon` state and the tracked FileBot release/source checksum,
then evaluates all three profiles against the complete candidate bootstrap
state. Any changed bootstrap files are committed together only after successful
validation. Installed systems continue to update their independent ignored
`.local-sources/` copies through Topgrade.

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
- all three NixOS profiles with canonical `local/` recovery-state fixtures
- all three NixOS profiles again through the installer/bootstrap root fallback
- the deployment-local overlapping-subnet policy during profile evaluation
- the ThinkPad deployment-local WWAN connection with documentation-only carrier data
- one real Plymouth theme build per profile

Clean-checkout CI must not depend on real local identity, `.local-sources/`,
wallpaper, vendor logos, ThinkPad tuning, private network ranges or a real mobile
carrier. CI deployment fixtures use only documentation/example values.

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

## Documentation publication

Markdown under `docs/` is the canonical long-form documentation source. Selected
pages may later be mirrored to the repository's GitHub Wiki for navigation and
presentation, but the Wiki must not become an independently edited source of
truth.

## Third-party provenance

Current third-party, upstream-derived and locally acquired material is described
in `docs/third-party-material.md`. That document describes the present public
model only.

Machine-local vendor logos, Apple fonts, shared wallpaper and device-specific
ThinkPad tuning are not stored in Git. Redistributable upstream-derived tracked
material retains explicit provenance/license context.
