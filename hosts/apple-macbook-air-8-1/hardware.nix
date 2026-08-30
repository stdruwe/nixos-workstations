{ pkgs, ... }:

let
  # Temporary workaround for NixOS/nixos-hardware#1933. The pinned
  # nixos-hardware revision still extracts the Apple recovery image through
  # vmTools.runInLinuxVM, which can fail without producing an exit code.
  # Keep the upstream T2 module for kernel/audio/etc., but provide the same
  # Sonoma Broadcom firmware through the userspace-7zz implementation locally.
  appleT2BrcmFirmware = pkgs.callPackage ../../pkgs/apple-t2-brcm-firmware {
    version = "sonoma";
  };

  keyboardBacklightUp =
    "${pkgs.brightnessctl}/bin/brightnessctl -q -d 'apple::kbd_backlight' set 10%+";
  keyboardBacklightDown =
    "${pkgs.brightnessctl}/bin/brightnessctl -q -d 'apple::kbd_backlight' set 10%-";
in
{
  # Verified hardware: MacBookAir8,1 (2018), Intel Core i5-8210Y,
  # Intel UHD Graphics 617, Apple T2 and 16 GiB RAM.
  hardware.apple-t2 = {
    kernelChannel = "stable";

    firmware = {
      # Disabled only to avoid the VM-based firmware package from the pinned
      # nixos-hardware revision. hardware.firmware below installs the same
      # Sonoma firmware using the upstream PR #1933 userspace extraction.
      enable = false;
      version = "sonoma";
    };
  };

  # Keep the Sonoma T2 Broadcom firmware first, then add the standard Linux
  # firmware set required by i915. In particular, the MacBookAir8,1 needs
  # i915/kbl_dmc_ver1_04.bin; without it i915 disables runtime power management.
  hardware.firmware = [
    appleT2BrcmFirmware
    pkgs.linux-firmware
  ];

  # Map the Apple keyboard to a PC-like modifier layout: swap Fn with left Ctrl
  # and left Option with Command. Right Option remains AltGr.
  boot.extraModprobeConfig = ''
    options hid_apple swap_fn_leftctrl=1 swap_opt_cmd=2
  '';

  # COSMIC 1.6 currently sees KEY_KBDILLUMUP/DOWN but does not handle these
  # keys itself. The LED controller works, so translate the kernel events into
  # 10-percent brightnessctl steps for both press and hold events. Remove this
  # workaround once COSMIC handles the keyboard-backlight events directly.
  services.triggerhappy = {
    enable = true;
    user = "root";
    bindings = [
      {
        keys = [ "KBDILLUMUP" ];
        event = "press";
        cmd = keyboardBacklightUp;
      }
      {
        keys = [ "KBDILLUMUP" ];
        event = "hold";
        cmd = keyboardBacklightUp;
      }
      {
        keys = [ "KBDILLUMDOWN" ];
        event = "press";
        cmd = keyboardBacklightDown;
      }
      {
        keys = [ "KBDILLUMDOWN" ];
        event = "hold";
        cmd = keyboardBacklightDown;
      }
    ];
  };

  # MacBookAir8,1 has no AMD dGPU, so hardware.apple-t2.enableIGPU remains at
  # its intentional default value of false.
  hardware.graphics.enable = true;
  hardware.bluetooth.enable = true;

  environment.systemPackages = [
    pkgs.nvtopPackages.intel
  ];
}
