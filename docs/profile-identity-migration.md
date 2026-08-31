# Migrating to technical hardware profiles and local identity

Last updated: 2026-08-29

This guide applies only to already installed legacy states that still use `host.nix` or hostname-based profile selection. Fresh installations already create `profile.nix` and `identity.json` automatically and do not need this migration.

Target model:

- `profile.nix` selects only the technical hardware profile;
- `identity.json` contains hostname, local username and display name;
- both files remain local and are not committed;
- hostname and username are not part of the technical profile name.

## 1. Use the current `main` branch

```bash
cd /etc/nixos
git switch main
git pull --ff-only
```

An old ignored `host.nix` may remain during migration. The current `configuration.nix` does not use it.

## 2. Define local identity

First determine the intended normal desktop user:

```bash
USER_NAME="$USER"
FULL_NAME="$(getent passwd "$USER_NAME" | cut -d: -f5 | cut -d, -f1)"
printf 'User: %s\nDisplay name: %s\n' "$USER_NAME" "$FULL_NAME"
```

If the display name is empty or incorrect, set `FULL_NAME` appropriately before continuing.

Choose the hostname and technical profile. Examples:

```bash
HOST_NAME='<hostname>'
PROFILE='thinkpad-x1-carbon-gen13'
```

or:

```bash
HOST_NAME='<hostname>'
PROFILE='hp-z2-tower-g9'
```

or:

```bash
HOST_NAME='<hostname>'
PROFILE='apple-macbook-air-8-1'
```

Then create the local files:

```bash
export HOST_NAME USER_NAME FULL_NAME PROFILE

nix \
  --extra-experimental-features 'nix-command' \
  eval \
  --impure \
  --json \
  --expr '{
    hostName = builtins.getEnv "HOST_NAME";
    userName = builtins.getEnv "USER_NAME";
    fullName = builtins.getEnv "FULL_NAME";
  }' \
  > /tmp/nixos-identity.json

cat > /tmp/nixos-profile.nix <<EOF
{ ... }:

{
  imports = [
    ./hosts/${PROFILE}/default.nix
  ];
}
EOF

sudo install -o root -g wheel -m 0664 \
  /tmp/nixos-identity.json \
  /etc/nixos/identity.json

sudo install -o root -g wheel -m 0664 \
  /tmp/nixos-profile.nix \
  /etc/nixos/profile.nix

rm -f /tmp/nixos-identity.json /tmp/nixos-profile.nix
```

Verify:

```bash
cat /etc/nixos/identity.json
cat /etc/nixos/profile.nix
git status --short
```

Because of `.gitignore`, neither `identity.json` nor `profile.nix` should appear as untracked files.

## 3. Validate NixOS without activation

```bash
cd /etc/nixos
sudo nixos-rebuild build
```

Expected result:

- evaluation and build succeed;
- hostname/user changes are not yet activated;
- the running system remains unchanged.

On systems with sensitive network hardware, `build` is preferable to `switch` for this migration check.

## 4. Validate Home Manager

```bash
cd "$HOME/.config/home-manager"
git switch main
git pull --ff-only
```

Build the Home Manager profile matching the technical hardware profile:

```bash
home-manager build --impure --flake 'path:.#thinkpad-x1-carbon-gen13'
```

or:

```bash
home-manager build --impure --flake 'path:.#hp-z2-tower-g9'
```

or:

```bash
home-manager build --impure --flake 'path:.#apple-macbook-air-8-1'
```

This step also does not activate anything.

## 5. Activate

Only after both NixOS and Home Manager builds succeed, activate deliberately:

```bash
cd /etc/nixos
sudo nixos-rebuild switch
```

Then activate the corresponding Home Manager profile, for example:

```bash
home-manager switch --impure --flake 'path:.#thinkpad-x1-carbon-gen13'
```

## 6. Remove the legacy local selector

After the new model has been activated and verified, remove the obsolete local selector:

```bash
sudo rm -f /etc/nixos/host.nix
```

The technical hardware selection now exists only in `profile.nix`; variable local identity exists only in `identity.json`.
