# Hardware status – `hp-z2-tower-g9`

Last updated: 2026-08-31

## Verified hardware

- HP Z2 Tower G9 Workstation Desktop PC
- SKU: `5F0C6EA#ABD`
- BIOS: `U50 Ver. 03.06.02`
- CPU: Intel Core i7-12700K
- RAM: 64 GiB
- Intel iGPU: UHD Graphics 770 / Alder Lake-S GT1 (`8086:4680`), driver `i915`
- dGPU: Radeon RX 7600 XT / Navi 33 (`1002:7480`), driver `amdgpu`
- Ethernet: Realtek RTL8125 2.5GbE (`10ec:8125`)
- WLAN: Intel Wireless-AC 9260 (`8086:2526`), driver `iwlwifi`

## Declarative state

- `nixos-generate-config --show-hardware-config` was incorporated as `hardware-configuration.nix`
- Intel microcode and `kvm-intel` were confirmed by the hardware scan
- AHCI, NVMe and standard USB/SCSI initrd modules were confirmed
- no model-specific HP Z2 Tower G9 profile exists in `nixos-hardware`
- generic `nixos-hardware` Intel and AMD GPU profiles are imported
- Intel UHD 770 remains enabled for Quick Sync / VA-API
- `nvtop` is built specifically with Intel+AMD support and without NVIDIA/CUDA
- installation target is selected at runtime or supplied explicitly; no SSD serial number or fixed disk ID is stored in Git
- Disko layout: 2 GiB ESP, LUKS2, Btrfs `@root`, `@home`, `@nix`, `@swap`, 40 GiB swapfile
- KDE Plasma 6 / Wayland
- Intel UHD 770 and Radeon RX 7600 XT are supported concurrently
- the system can act as the Nix remote builder for the `apple-macbook-air-8-1` profile

## Other storage devices

Other disks and optical drives may be present in the machine. They are not identified by serial number in this repository and are not Disko targets unless the installer operator explicitly selects one as the installation target.

Hostname and username do not belong in this hardware document. Canonical local identity is defined only through `/etc/nixos/local/identity.json`.
