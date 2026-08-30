# Combined NixOS / Home Manager installation package

Last updated: 2026-08-30

Fresh installations should normally use one transportable package containing a clean NixOS checkout, including Git metadata, plus the matching state of the Home Manager repository as a local Git bundle.

The bundle keeps initial installation independent from live GitHub access. It is not copied into `/etc/nixos`; it is only a transport source for preflight validation, the target checkout and the initial activation-package build.

## Public release packages

The public repository pair is:

```text
NixOS:        stdruwe/nixos-workstations
Home Manager: stdruwe/home-manager-workstations
```

The public version history starts at `v0.1.0`. The same release tag must exist in both repositories, for example:

```text
NixOS:        v0.1.0
Home Manager: v0.1.0
```

The release workflow checks out both public tags and invokes the package helper in release mode:

```bash
./prepare-install-package.sh --release-tag v0.1.0 ./dist
```

The NixOS release then receives two assets:

```text
nixos-install-v0.1.0.tar.zst
nixos-install-v0.1.0.tar.zst.sha256
```

`INSTALL-SNAPSHOT.txt` inside the archive records the release tag and the exact NixOS and Home Manager commit SHAs.

The packaged NixOS checkout has a local `main` branch pointing exactly at the release commit. This keeps the installation version-bound while allowing later normal updates from `origin/main`. The Home Manager bundle intentionally exports its release commit as `refs/heads/main`, because the installation flow expects that branch as both transport and target branch.

For Home Manager releases using the machine-local dependency model, tracked `flake.lock.bootstrap` records the exact release-time starting state. During installation it is copied to the target machine's ignored live `flake.lock`; subsequent Topgrade dependency updates are local to that machine and do not require a new repository release.

### GitHub access for the release workflow

Both repositories are public. The NixOS release workflow checks out the matching Home Manager tag directly through public HTTPS access and therefore requires no cross-repository read token or repository secret.

The normal NixOS workflow `GITHUB_TOKEN` is used only to attach the generated assets to the NixOS release. If the matching Home Manager tag is missing or either checkout does not resolve exactly to the requested tag, the release job fails and does not publish an installation package.

## Creating a manual package from `main`

For testing or installations outside a release, a package can still be generated from current `main`. Both local repositories must be on `main`, clean and exactly at `origin/main`.

Default locations:

- NixOS: the directory containing `prepare-install-package.sh`, normally `/etc/nixos`
- Home Manager: `$HOME/.config/home-manager`

Create the package with:

```bash
cd /etc/nixos
./prepare-install-package.sh /path/to/output-directory
```

Because the live Home Manager `flake.lock` is ignored, machine-local dependency drift does not make the Home Manager Git checkout dirty and is not bundled as repository state. The package carries the tracked `flake.lock.bootstrap` belonging to the selected commit.

Before packaging, the helper runs `git fetch origin main` for both repositories and stops if either repository is dirty or if `HEAD` differs from `origin/main`.

It creates:

```text
nixos-install-<timestamp>-<nixos-sha>-<hm-sha>.tar.zst
nixos-install-<timestamp>-<nixos-sha>-<hm-sha>.tar.zst.sha256
```

## Package contents

The archive contains:

```text
nixos-install/
├── install.sh
├── INSTALL-SNAPSHOT.txt
├── home-manager.bundle
└── nixos/
    ├── .git/
    ├── install.sh
    ├── scripts/
    │   ├── install-common.sh
    │   └── install-disk.sh
    ├── install-thinkpad-x1-carbon-gen13.sh
    ├── install-hp-z2-tower-g9.sh
    └── install-apple-macbook-air-8-1.sh
```

`nixos/` is a real clean Git checkout. Its `origin` is set to:

```text
https://github.com/stdruwe/nixos-workstations.git
```

The Home Manager target checkout receives:

```text
https://github.com/stdruwe/home-manager-workstations.git
```

Both are public read remotes, so normal installed-system updates require neither a GitHub account nor an SSH key. Contributors may still configure separate SSH push remotes in their development checkouts.

The package-level `install.sh` is copied from the exact tracked `nixos/install.sh` at package creation time. There is therefore only one dispatcher implementation to maintain.

## On the live system

Transfer the archive and checksum together, then run:

```bash
sha256sum -c nixos-install-*.tar.zst.sha256
tar --zstd -xf nixos-install-*.tar.zst
cd nixos-install
```

Start the installation with one of:

```bash
sudo ./install.sh thinkpad-x1-carbon-gen13
sudo ./install.sh hp-z2-tower-g9
sudo ./install.sh apple-macbook-air-8-1
```

The dispatcher selects the hardware-specific implementation and, inside the combined package, automatically points `HOME_MANAGER_BUNDLE` at the bundled repository. No separate copy to `/tmp/home-manager.bundle` is required.

Profile-specific arguments are forwarded unchanged. For ThinkPad and HP, omitting the disk keeps interactive whole-disk selection; a direct target disk can also be supplied through the shared dispatcher:

```bash
sudo ./install.sh thinkpad-x1-carbon-gen13 /dev/nvme0n1
sudo ./install.sh hp-z2-tower-g9 /dev/nvme0n1
```

The selected disk must have no mounted filesystems and still requires the hardware installer's exact destructive confirmation.

For MacBookAir8,1, the shared dispatcher also forwards the existing read-only layout check:

```bash
sudo ./install.sh apple-macbook-air-8-1 --layout-check
```

For a MacBookAir8,1 installation over SSH, the hardware installer additionally requires an active tmux session. If tmux is missing from the live system:

```bash
nix shell nixpkgs#tmux
```

## Home Manager during installation

The safety flow is:

1. verify the bundle and require `refs/heads/main`;
2. clone it for preflight;
3. if `flake.lock` is absent, require `flake.lock.bootstrap` and seed the ignored live lock from it;
4. evaluate the matching `homeConfigurations.<profile>.activationPackage` before destructive actions;
5. after `nixos-install`, clone Home Manager from the bundle into `~/.config/home-manager` in the target system;
6. set its `origin` to the public Home Manager read remote;
7. seed the target's live lock from `flake.lock.bootstrap` when necessary;
8. build the complete activation package directly into `/mnt/nix`;
9. on the first real boot, activate the already-built package as the target user before the display manager starts.

No GitHub connection is required before the first graphical login.

## Development/recovery fallback

The same tracked `install.sh` can be used directly from a normal NixOS checkout. Outside a combined package it leaves the established Home Manager bundle lookup untouched: `HOME_MANAGER_BUNDLE` may point to another local bundle, otherwise `/tmp/home-manager.bundle` remains the default.

The three hardware-specific scripts remain executable implementation entry points for development/recovery compatibility, but the shared dispatcher is the preferred user-facing entry point.
