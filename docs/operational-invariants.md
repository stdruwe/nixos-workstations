# Operational invariants and hardware workarounds

This document records non-obvious configuration that is intentionally present because it prevents a previously observed hardware, desktop or boot problem. It complements `CURRENT-STATE.md`: the current-state file describes the supported configuration, while this file preserves the rationale that must be understood before simplifying unusual values, ordering, patches or overrides.

## Change rule

Treat the following as design decisions, not cleanup candidates, until their rationale has been reviewed:

- fixed delays and retry windows;
- hardware PCI/USB identifiers and device paths;
- service ordering and overridden systemd commands;
- kernel parameters and kernel patches;
- `lib.mkForce` overrides;
- one-time marker files and migration fallbacks;
- cross-repository ordering between NixOS and Home Manager.

When changing one of these, update the adjacent code comment and this document in the same change. Cross-repository invariants must be reviewed and tested in both repositories together. A workaround should be removed only after the original failure mode has been retested on the affected hardware or after the documented upstream fix has reached the pinned dependency state.

## HP Z2 Tower G9: Plasma display and panel startup ordering

**Invariant:** NixOS applies the deployment-specific KScreen layout 30 seconds after login. The matching Home Manager profile waits 35 seconds before its one-time second-panel bootstrap.

**Reason:** Plasma must finish its initial output and panel discovery before the final two-monitor topology is applied. Applying the final layout and creating panels too early caused Plasma to create or migrate unnecessary additional application bars/panels while the output topology was still changing. The five-second margin ensures panel creation happens after the NixOS layout change.

**Do not:** change `plasmaDisplayLayout.delaySeconds` or the Home Manager 35-second bootstrap independently.

**Retest before removal/change:** fresh Plasma profile with both displays connected, first login, subsequent login, and a login after deleting only the panel-bootstrap marker. Verify that exactly the intended panels exist and no extra application bars are created.

## ThinkPad and HP: watchdog policy

**Invariant:** both profiles set the kernel parameter `nmi_watchdog=0` and explicitly disable systemd's runtime, reboot and kexec watchdog timers with `RuntimeWatchdogSec = "off"`, `RebootWatchdogSec = "off"` and `KExecWatchdogSec = "off"`.

**Reason:** watchdog operation was intentionally disabled during earlier boot/shutdown and power-management work because these workstations do not rely on an automatic watchdog-reset policy. The NMI watchdog setting was first used while diagnosing the ThinkPad's Lunar Lake/graphics hand-off path and was subsequently standardized on the HP profile as well. The systemd watchdog settings were made explicit while eliminating unwanted hardware-watchdog/shutdown involvement. This is a deliberate policy choice, not a claim that current kernels require watchdogs to be disabled.

The resulting HP configuration was verified with clean reboot/shutdown behavior both with and without a running virtual machine. Preserve the policy unless watchdog recovery is intentionally being introduced as a new operational requirement.

**Retest before re-enabling:** check cold boot, normal reboot, shutdown with and without active virtual machines, graphical hand-off, and journal output for watchdog-device or shutdown-timeout regressions. Re-enable the NMI watchdog and systemd/hardware watchdog policy independently during testing so the source of any regression remains identifiable.

## ThinkPad X1 Carbon Gen 13: Quectel RM520N-GL D3cold

**Invariant:** D3cold is disabled only for PCI device `1eac:1007` while normal runtime power management remains enabled.

**Reason:** The RM520N-GL loses its MHI state across s2idle when PCIe D3cold is allowed. Recovery through `mhi-pci-generic` delays WWAN reconnection by roughly one minute.

**Retest before removal:** suspend/resume repeatedly with WWAN registered and verify immediate modem recovery without the udev `d3cold_allowed=0` rule.

## ThinkPad X1 Carbon Gen 13: WWAN wake source

**Invariant:** `/sys/bus/pci/devices/0000:00:1c.3/power/wakeup` is forced to `disabled` before sleep.

**Reason:** The Quectel modem is attached behind that PCIe root port. The modem must remain usable during normal operation but must not wake the laptop from s2idle.

**Retest before change:** verify the PCI topology on the supported hardware revision and perform repeated s2idle wake-source tests. Do not generalize the hard-coded root-port path to other hardware profiles.

## ThinkPad X1 Carbon Gen 13: GNSS activation ordering

**Invariant:** the gpsd device hook waits up to five seconds for `/dev/wwan0at0` to become writable before sending `AT+QGPS=1`.

**Reason:** gpsd may request `/dev/gnss0` while the modem's AT endpoint is still becoming available. The bounded retry tolerates that device-creation ordering without leaving GNSS permanently disabled.

**Retest before shortening/removal:** start gpsd/GNSS immediately after modem initialization and after resume; verify that the first GNSS request succeeds consistently.

## ThinkPad X1 Carbon Gen 13: ModemManager stop timeout

**Invariant:** `systemd.services.ModemManager.serviceConfig.TimeoutStopSec = "5s"` remains configured.

**Historical rationale:** not yet documented in the public repository or recovered from the available prior discussion. The value predates this operational-invariant audit. Do not infer a reason from the number alone and do not remove or change it as cleanup until its original failure mode has been recovered from prior notes or reproduced on the ThinkPad.

**Required follow-up before change:** determine whether the timeout protects rebuild/restart behavior, suspend/resume, modem shutdown, or another observed failure. Once confirmed, replace this paragraph with the verified reason and a concrete retest criterion.

## ThinkPad X1 Carbon Gen 13: HDA codec power saving

**Invariant:** `snd_hda_intel` uses `power_save=10`; PowerTOP's more aggressive `power_save=1` suggestion is intentionally not followed.

**Reason:** the ten-second timeout enables HDA codec power saving without cycling the codec after only one idle second. The shorter PowerTOP recommendation was considered unnecessarily aggressive because frequent power-state toggling can increase the risk of audible transition artifacts. The ten-second setting was applied and retained after reboot without reported crackles, dropouts or other audio regressions.

**Retest before changing:** compare idle power with the current value and the proposed replacement while testing speaker/headphone playback, pause/resume transitions, notification sounds and repeated idle-to-active transitions. Do not shorten the timeout solely to make PowerTOP report the tunable as optimal.

## ThinkPad X1 Carbon Gen 13: thermald

**Invariant:** `services.thermald.enable = false`.

**Reason:** the imported nixos-hardware profile enables thermald, but on this X1 Carbon Gen 13 thermald exits as incompatible because of Lenovo DYTC.

**Retest before removal:** confirm that the current thermald and firmware combination starts cleanly and provides useful control on the actual model.

## ThinkPad and HP: retained Plymouth hand-off to Plasma

**Invariant:** the normal Plymouth quit units are overridden and a dedicated final quit runs after `plasmalogin.service`, with a five-second delay before `plymouth quit --retain-splash`.

**Reason:** the workstation themes intentionally retain the splash across the display-manager transition instead of allowing the normal Plymouth quit path to expose an intermediate console/transition frame. The MacBook uses the equivalent five-second bridge before the COSMIC greeter through its own profile-specific mechanism.

**Retest before change:** cold boot through LUKS to the graphical login on the real target display. Check for tty flashes, premature splash disappearance, login-manager overlap and regressions in the LUKS animation timing.

## Apple MacBook Air 8,1: asynchronous suspend/resume

**Invariant:** `pm_async=off` must remain effective for this profile.

**Reason:** a controlled test with `pm_async=1` caused the MacBook to fail to resume and required a hard power-off. With asynchronous suspend disabled, suspend/resume works reliably enough for the supported profile, although visible resume can take roughly 15 seconds and the keyboard/trackpad can take additional time to become responsive. A T2 USB timeout (`error -110`) was observed on the slower resume path, followed by successful device re-enumeration.

**Retest before removal:** only revisit asynchronous suspend after a new T2/model-specific kernel fix or other material suspend-path change. Test repeated deep suspend/resume cycles, internal display recovery, keyboard/trackpad recovery, WLAN and T2 USB re-enumeration before considering `pm_async=off` removable.

## Apple MacBook Air 8,1: EFI NVRAM writes

**Invariant:** `boot.loader.efi.canTouchEfiVariables = false`.

**Reason:** NixOS uses a separate Linux ESP and systemd-boot. Apple Startup Manager discovers the fallback loader at `EFI/BOOT/BOOTX64.EFI`; creating NVRAM boot entries is unnecessary and intentionally avoided.

**Retest before change:** preserve the Apple EFI and macOS/APFS partitions and verify startup selection through Apple Startup Manager.

## Apple MacBook Air 8,1: Broadcom Neighbor Discovery offload

**Invariant:** the profile-specific brcmfmac patch disables firmware Neighbor Discovery offload (NDOE) while leaving ARP offload unchanged.

**Reason:** on the BCM4355 firmware in this MacBook, IPv6 receive throughput is throttled while NDOE is enabled. A PROMISC A/B test restored normal IPv6 RX performance when firmware ARP/ND offloads were disabled; the tracked patch narrows the workaround to NDOE.

**Retest before removal:** repeat IPv4/IPv6 throughput tests on the internal WLAN after any relevant brcmfmac/firmware update.

## Apple MacBook Air 8,1: T2 Broadcom firmware extraction

**Invariant:** the upstream T2 module remains enabled for kernel/audio support, but its firmware package is disabled and replaced by the local userspace-7zz extraction package.

**Reason:** the pinned nixos-hardware revision still uses `vmTools.runInLinuxVM` for Apple recovery-image extraction and may fail without producing a usable exit result. The local package follows the userspace extraction approach associated with `NixOS/nixos-hardware#1933` while supplying the same Sonoma firmware.

**Removal criterion:** remove the local package only after the pinned nixos-hardware revision contains a verified working userspace extraction path for this model.

## Apple MacBook Air 8,1: keyboard backlight keys

**Invariant:** triggerhappy translates `KBDILLUMUP`/`KBDILLUMDOWN` press and hold events into 10-percent `brightnessctl` steps.

**Reason:** COSMIC 1.6 receives the kernel key events but does not handle them, while the Apple keyboard LED controller itself works.

**Removal criterion:** remove the workaround when the deployed COSMIC version handles the keyboard-backlight events directly and press/hold behavior has been verified on the MacBook.

## Maintenance

When a newly discovered workaround is introduced, add it here with:

1. the exact invariant;
2. the observed failure mode and affected hardware/profile;
3. any cross-file or cross-repository dependency;
4. a concrete retest or removal criterion.

Do not document guesses as historical causes. If the reason for existing non-obvious behavior is unknown, preserve it while investigating rather than rewriting it as an optimization.
