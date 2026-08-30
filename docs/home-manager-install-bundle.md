# Home Manager during fresh installations

Last updated: 2026-08-30

The three hardware-specific NixOS installers integrate the separate Home Manager configuration into the installation flow. User files, toolkit/desktop settings, MIME associations and other Home Manager settings are therefore prepared before the first graphical login.

## Preferred transport: combined release package

The public repositories are:

```text
https://github.com/stdruwe/nixos-workstations.git
https://github.com/stdruwe/home-manager-workstations.git
```

For stable installations, the preferred path is the version-matched NixOS release package. NixOS and Home Manager use the same release tag, beginning with public release `v0.1.0`.

The package contains:

- a clean NixOS checkout at the NixOS release commit, including `.git`;
- the Home Manager release commit from the same tag as a local Git bundle exported under `refs/heads/main`;
- `INSTALL-SNAPSHOT.txt` containing both exact commit SHAs;
- a top-level `install.sh` that passes the bundled Home Manager repository to the selected hardware installer.

Home Manager tracks `flake.lock.bootstrap` as the clean-checkout/release dependency baseline. The installed checkout receives its own ignored live `flake.lock` derived from that bootstrap state.

The NixOS release also contains the archive SHA256 file. See [`install-package.md`](install-package.md) for the complete workflow.

For testing, `prepare-install-package.sh` can create a package manually from two clean, current `main` checkouts. That mode is not version-bound and does not replace a release package for stable installation.

## Safety and validation flow

Before any destructive action:

1. the installer validates the bundle with `git bundle verify`;
2. the bundle must contain `refs/heads/main`;
3. the bundle is cloned temporarily;
4. if the clone has no `flake.lock`, the installer requires `flake.lock.bootstrap` and copies it to the ignored live `flake.lock`;
5. the `homeConfigurations.<profile>.activationPackage` matching the selected technical hardware profile is evaluated with the locally entered user/home identity;
6. if this evaluation fails, installation stops before disk confirmation.

After a successful `nixos-install`:

1. the bundle is cloned to `~/.config/home-manager` in the target system;
2. `origin` is set to `https://github.com/stdruwe/home-manager-workstations.git`;
3. the target checkout's ignored live `flake.lock` is seeded from `flake.lock.bootstrap` when necessary;
4. the selected Home Manager activation package is built directly into the target store `/mnt/nix` using `nix --store /mnt build`;
5. its logical `/nix/store/...` path is written to `/var/lib/nixos/home-manager-initial-activation`.

The transport bundle itself remains outside the NixOS checkout and is not copied into `/etc/nixos`.

## Ownership after installation

The installed machine owns its live `~/.config/home-manager/flake.lock`. It is ignored by Git and may later be advanced locally by Topgrade without creating a repository commit or requiring upstream write access.

The tracked `flake.lock.bootstrap` remains unchanged as the clean-checkout/release baseline. A new repository release is therefore not required for every Home Manager dependency update performed on an installed machine.

## First boot

`home-manager-initial-activation.service` is a shared NixOS one-shot unit. It starts only when the pending file written by the installer exists.

The unit:

- runs after `nix-daemon.socket` and user management are available;
- is a required dependency of `display-manager.service`;
- fixes ownership of `~/.config/home-manager` for the new user;
- executes the already-built Home Manager activation package as that user;
- removes the pending file only after successful activation.

Neither Plasma nor COSMIC can present the first graphical login until initial Home Manager activation succeeds. Because the complete activation closure was already built into `/mnt/nix` during installation, this first boot requires neither GitHub access nor another dependency download.

If activation fails, the pending file remains and the display manager is not released. Fix the error from a console and restart the unit.

## Development/recovery bundle

The direct root installers also accept an explicit bundle path through `HOME_MANAGER_BUNDLE`. Without that variable they use `/tmp/home-manager.bundle`.

A local Home Manager checkout can create such a bundle with:

```bash
git -C "$HOME/.config/home-manager" bundle create /tmp/home-manager.bundle main
```

This path is intended for development or recovery. Normal release installations use the combined version-matched installation package.
