# NixOS post-install checklist

This checklist applies after a fresh installation from the version-matched NixOS / Home Manager package.

## All profiles

1. Reboot into the installed system and log in with the password created during installation.
2. Confirm that Home Manager completed before the first graphical login:

   ```bash
   systemctl status home-manager-initial-activation.service --no-pager
   ```

3. Check for failed system services:

   ```bash
   systemctl --failed
   ```

4. Confirm the local profile and identity files:

   ```bash
   cat /etc/nixos/profile.nix
   cat /etc/nixos/identity.json
   ```

5. Verify the expected filesystems and swap:

   ```bash
   findmnt /
   findmnt /home
   findmnt /nix
   findmnt /swap
   swapon --show
   ```

6. Run the normal update workflow after the system is known to be healthy:

   ```bash
   topgrade
   ```

Machine-local data such as `identity.json`, optional `deployment.json`, Apple fonts, wallpaper, optional Plymouth vendor logos, EasyEffects tuning and live dependency state is intentionally excluded from Git. Back up any local data that cannot simply be regenerated.

## ThinkPad X1 Carbon Gen 13 / HP Z2 Tower G9

Complete the Secure Boot and TPM2 workflow documented in [`docs/secure-boot-tpm2.md`](docs/secure-boot-tpm2.md).

The normal sequence is:

```bash
sudo /etc/nixos/post-install-security.sh prepare
sudo /etc/nixos/post-install-security.sh enroll-secureboot
reboot
sudo /etc/nixos/post-install-security.sh status
sudo /etc/nixos/post-install-security.sh enroll-tpm
```

Do not enroll TPM2 before Secure Boot is enabled and verified.

On the ThinkPad, the installer generates the local EasyEffects speaker tuning during preflight. After login, verify that EasyEffects is running and that the expected internal-speaker preset is active.

## Apple MacBook Air 8,1

The MacBook uses a separate T2 dual-boot architecture and does not use the Lanzaboote/Secure-Boot procedure above.

Follow:

- [`docs/apple-macbook-air-8-1-install.md`](docs/apple-macbook-air-8-1-install.md)
- [`docs/apple-macbook-air-8-1-postinstall.md`](docs/apple-macbook-air-8-1-postinstall.md)

The Apple EFI and macOS/APFS partitions remain outside the normal NixOS update workflow.

## Optional deployment data

Local infrastructure belongs in ignored `/etc/nixos/deployment.json`. A missing file is valid. Use it only when the machine needs deployment-specific values such as SSH authorized keys, a remote Nix builder, desktop integration data, Hermes endpoints or a non-default Topgrade dependency policy.

Do not commit passwords, tokens, private keys, personal addresses or machine-local deployment endpoints.
