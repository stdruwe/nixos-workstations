# MacBookAir8,1 (2018/T2) – post-install and runtime findings

Last updated: 2026-08-31

This document records verified runtime findings for the technical profile `apple-macbook-air-8-1`. Experimental changes should only be recorded here after they have been reproduced and confirmed.

## Boot / Apple Startup Manager

- NixOS resides on the separate Linux ESP `NIXOS-ESP` (`/dev/nvme0n1p3`).
- The Apple EFI partition `/dev/nvme0n1p1` remains untouched.
- macOS/APFS remains present on p2 in the verified layout.
- The NixOS snowflake icon is installed declaratively as `.VolumeIcon.icns` on the NixOS ESP.
- `boot.loader.efi.canTouchEfiVariables = false` remains intentional. Do not create EFI NVRAM entries from NixOS.

Use `sudo nixos-rebuild switch` for persistent configuration activation. Calling `switch-to-configuration` directly can activate a store path without advancing the persistent system generation in the expected way.

## Plymouth and shared wallpaper

The MacBook profile uses a dedicated Apple-to-LUKS Plymouth theme:

- the shared machine-local wallpaper is cropped to 2560×1600 (16:10);
- the same source is also used for the COSMIC desktop/lock screen and COSMIC greeter;
- the Apple boot logo is machine-local and is not stored in Git;
- `scripts/stage-apple-boot-assets-macos.sh` stages the machine's own macOS `appleLogo.efires` resource on the Apple EFI partition;
- `scripts/import-apple-boot-logo-linux.sh` extracts the 168×206 2x logo locally to ignored `assets/local/apple-logo-2x.png`;
- if the local Apple logo is absent, the profile remains buildable and skips the optional logo intro;
- i915 is present in the initrd for early native KMS;
- LUKS animation and exit timing are aligned with the other profiles;
- `plymouth-quit.service` waits five seconds to bridge the transition to the COSMIC greeter without a visible tty stage.

The logo extraction/fallback workflow and the boot transition were both verified. See `third-party-material.md` and the installation guide for provenance and staging details.

## T2 NCM / NetworkManager

T2 Macs expose an internal USB Ethernet/NCM interface that is not a usable external Ethernet port. The t2linux post-install documentation identifies the well-known interface address used by this hardware path:

```text
ac:de:48:00:11:22
```

This is a T2 platform constant used by the upstream workaround, not a deployment-specific workstation identifier. The profile uses it for NetworkManager `no-auto-default`, which is independent of the kernel interface name and avoids recurrent wired-network notifications.

## BCM4355 WLAN / IPv6 receive performance

The initially severe IPv6 receive bottleneck on the Broadcom BCM4355 was isolated systematically:

- local WLAN/IPv4 throughput was fast;
- IPv6 receive throughput stayed around 50 Mbit/s, including with multiple TCP streams;
- GRO and interface MTU were not the cause;
- a PROMISC A/B test disabled firmware ARP/ND offloads and significantly improved IPv6 receive throughput;
- `ndoe` was isolated as the problematic firmware offload.

The profile therefore applies `brcmfmac-disable-nd-offload.patch`, which disables only Neighbor Discovery Offload while leaving ARP offload unchanged.

After rebuilding the kernel and rebooting without PROMISC, roughly 400 Mbit/s was observed for both IPv4 and IPv6. The workaround is therefore verified.

WLAN power saving remains **enabled**. The post-fix ping test with power saving enabled showed 0% loss and about 2.9 ms average latency to the gateway, so there is no reason to disable it.

## Keyboard / trackpad / backlight

Verified `hid_apple` mapping:

```text
swap_fn_leftctrl=1
swap_opt_cmd=2
```

Result:

- Fn and left Ctrl are swapped;
- left Option and left Command are swapped;
- right Option remains AltGr.

COSMIC currently does not handle this machine's keyboard-backlight kernel events itself. `services.triggerhappy` therefore controls `apple::kbd_backlight` through `brightnessctl` in 10% steps for press and hold events.

## Suspend / resume

`/sys/power/mem_sleep` uses `deep`. The kernel runs with:

```text
pm_async=off
```

This is **required** for this profile. A controlled test with `pm_async=1` caused the MacBook to fail to resume and require a hard power-off. Do not repeat that test unless a new model-specific fix becomes available.

With `pm_async=off`, suspend/resume works but is comparatively slow. Roughly 15 seconds to visible output was observed, with occasional additional delay before the internal keyboard and trackpad became fully responsive.

A T2 USB timeout (`error -110`) was also observed during the slower resume path; the devices subsequently re-enumerated. Suspend tuning must not remove `pm_async=off`.

## Intel graphics / DMC / RC6

Before the fix, the following firmware was missing:

```text
i915/kbl_dmc_ver1_04.bin
```

The MacBook profile therefore installs `pkgs.linux-firmware` in addition to the T2 firmware. After reboot the firmware loaded successfully:

```text
Finished loading DMC firmware i915/kbl_dmc_ver1_04.bin (v1.4)
```

A 10-second test showed roughly 92.7% RC6 residency on an idle desktop. A PCI device reported as permanently `active` is therefore not automatically a problem while the internal display is enabled.

## Verified idle power use

After the DMC fix, on an idle COSMIC desktop at roughly 40% display brightness, measured values were approximately:

- Intel RAPL package: 2.14 W;
- total battery discharge: 6.27 W average.

Battery discharge is the more meaningful whole-system measurement because RAPL does not fully include the display, T2, RAM, WLAN, SSD and other peripherals.

CPU/WLAN state during this measurement:

- governor `powersave`;
- `energy_performance_preference=balance_power`;
- WLAN power saving `on`.

## Apple NVMe AP1536M

The Apple NVMe controller exposes no additional standardized NVMe power states and no APST. Verified values are `npss: 0` and `apsta: 0`.

PCIe ASPM L1/L1.1 is active. L1.2 and runtime PM were not forced. Do not enable them experimentally without a measurable benefit and full resume validation.

## Thunderbolt / Titan Ridge

The Titan Ridge xHCI branch can use runtime PM. The Thunderbolt NHI remained active in tests. A reversible NHI unbind test produced no reliable power-saving benefit and was fully reverted.

Do not disable Thunderbolt globally or force ASPM based on the current measurements. The additional functionality/resume risk is not justified by the observed power behavior.

## Nix remote builder

The MacBook hardware profile does not embed a remote-builder address, SSH host key or deployment-specific hostname. Optional `ssh-ng` offloading is supplied through `/etc/nixos/local/deployment.json`; without it, local builds remain enabled and the profile still evaluates/builds normally.

A local deployment may configure:

- a remote builder endpoint;
- the dedicated builder account (default `nix-ssh`);
- the local client key path (default `/root/.ssh/nixbuilder_ed25519`);
- the builder's base64-encoded SSH public host-key file;
- capacity/scheduling values such as `maxJobs` and `speedFactor`.

The private client key remains outside Git and the Nix store. The optional remote-builder path has been validated with a real T2 kernel build and can be used for expensive x86_64 builds while preserving local-build fallback.

## Local recovery state

The canonical NixOS recovery state is `/etc/nixos/local/` and consists of exactly `profile.nix`, `identity.json` and `deployment.json`. The MacBook uses the same recovery model as the other profiles. Reproducible wallpaper/font/logo assets and `.local-sources/` are not part of that backup set.

## Update / Home Manager state

Current integration state:

- the MacBook profile is integrated into `main`;
- Home Manager contains `apple-macbook-air-8-1` on `main`;
- Bitwarden is the selected SSH agent for the MacBook profile, while shared GitHub SSH routing uses `ssh.github.com:443`;
- Topgrade validates managed dependency candidates only against the current machine's NixOS and Home Manager profiles;
- there is no publisher profile, automatic dependency commit/push workflow, cross-machine update transaction or cross-profile dependency validation in normal Topgrade operation;
- Home Manager uses tracked `flake.lock.bootstrap` only as bootstrap state and keeps the live `flake.lock` machine-local and ignored;
- manual Home Manager builds/switches use explicit `path:.#<profile>` references;
- the NixOS system update is guarded by a full current-profile candidate build before the installed `nixos-unstable` channel is changed;
- on a failed candidate, the installed channel remains unchanged while Home Manager, Flatpak and the remaining Topgrade steps continue;
- repository-wide sudo authentication timeout is 15 minutes.

The T2 profile has exercised that failed-candidate path with an upstream `4001-asahi-trackpad.patch` / `drivers/hid/hid-magicmouse.c` hunk failure. That is a validated update-guard path, not a general defect in the repository update design.

Further power optimization should be driven by new measurements. Preserve the known stable constraints (`pm_async=off`, the NDOE workaround and WLAN power saving enabled).
