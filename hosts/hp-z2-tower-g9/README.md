# HP Z2 Tower G9 profile

Technical hardware profile: `hp-z2-tower-g9`

- CPU: Intel Core i7-12700K
- GPUs: Intel UHD Graphics 770 (Quick Sync / VA-API) + AMD Radeon RX 7600 XT
- desktop: KDE Plasma 6 / Wayland
- shared NixOS modules come from `modules/common/`
- generated `hardware-configuration.nix` is integrated into the profile
- there is no model-specific HP Z2 Tower G9 profile in `nixos-hardware`; the generic Intel and AMD GPU profiles are used instead
- the installer receives the Disko target at runtime; no SSD serial number or fixed disk ID is stored in this profile
- Hermes is not part of this hardware profile

Hostname and local username are deliberately not part of this profile. They are selected through the local untracked files `/etc/nixos/profile.nix` and `/etc/nixos/identity.json`.

Installation details are in `README-INSTALL.md`; verified hardware notes are in `NOTES.md`.
