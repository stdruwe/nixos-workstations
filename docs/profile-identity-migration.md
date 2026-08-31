# Machine-local recovery state

Last updated: 2026-08-31

The public repository and machine-specific recovery data are intentionally separate.
The canonical local state is:

```text
/etc/nixos/local/
├── profile.nix
├── identity.json
└── deployment.json
```

The complete `local/` directory is ignored by Git and is the only NixOS configuration state that needs a dedicated reinstallation backup.

## Files

### `local/profile.nix`

Selects exactly one technical hardware profile. Because the file lives one directory below the repository root, imports use `../hosts/...`:

```nix
{ ... }:

{
  imports = [
    ../hosts/thinkpad-x1-carbon-gen13/default.nix
  ];
}
```

Supported profiles are:

```text
thinkpad-x1-carbon-gen13
hp-z2-tower-g9
apple-macbook-air-8-1
```

### `local/identity.json`

Contains machine-local identity data:

```json
{
  "hostName": "example-host",
  "userName": "example-user",
  "fullName": "Example User"
}
```

Hostname, username and display name are not part of the technical hardware profile.

### `local/deployment.json`

Contains optional private or deployment-specific declarative data. The supported schema is documented in [`deployment-json.md`](deployment-json.md).

An empty deployment is represented as:

```json
{}
```

## Installer bootstrap migration

The hardware installers must evaluate NixOS before the target system has been activated. For this bootstrap phase they may still create these temporary root-level files:

```text
/etc/nixos/profile.nix
/etc/nixos/identity.json
/etc/nixos/deployment.json
```

They are bootstrap inputs only, not the canonical runtime layout.

During NixOS activation, `modules/common/local-state.nix`:

1. creates `/etc/nixos/local/` with restricted `root:wheel` permissions;
2. converts the root-level `profile.nix` import from `./hosts/...` to `../hosts/...`;
3. moves identity and deployment data into `local/`;
4. creates an empty `local/deployment.json` when no deployment file exists;
5. removes the migrated root-level bootstrap files.

Normal evaluation always prefers the canonical `local/` files. The root-level paths remain accepted only so an existing installation or a fresh installer can perform the migration without a broken intermediate rebuild.

## Existing installations

No manual file move is required. Update the repository and activate the configuration normally:

```bash
cd /etc/nixos
git switch main
git pull --ff-only
sudo nixos-rebuild switch
```

After a successful activation, verify:

```bash
sudo ls -la /etc/nixos/local
sudo cat /etc/nixos/local/profile.nix
sudo cat /etc/nixos/local/identity.json
sudo cat /etc/nixos/local/deployment.json
```

The three canonical files must exist. A normal profile selector must contain `../hosts/<profile>/default.nix`.

## Backup

Use:

```bash
sudo /etc/nixos/scripts/backup-config.sh /path/to/external-backup-directory
```

Despite its historical filename, the helper now backs up only `/etc/nixos/local/` and creates:

```text
nixos-local-<hostname>-<timestamp>.tar.zst
nixos-local-<hostname>-<timestamp>.tar.zst.sha256
nixos-local-<hostname>-<timestamp>.manifest.txt
```

The public Git checkout, Git history, release locks, Home Manager lock state, downloaded fonts, wallpaper, EasyEffects generated state and other reproducible data are deliberately excluded.

## Restore

For a reinstall or disaster recovery:

1. obtain a clean checkout of the public NixOS repository at `/etc/nixos`;
2. restore the archived `local/` directory into `/etc/nixos/local/`;
3. verify `profile.nix`, `identity.json` and `deployment.json`;
4. continue with the documented build/security installation process.

Secure Boot keys, TPM enrollment, Tailscale state, SSH host keys, KDE Connect pairings and desktop/browser state are not part of this NixOS local-state backup.
