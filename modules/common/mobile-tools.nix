{ pkgs, ... }:

{
  # usbmuxd provides the host-side transport and udev integration required by
  # libimobiledevice tools for normal-mode iPhone and iPad communication.
  services.usbmuxd.enable = true;

  environment.systemPackages = with pkgs; [
    # Serial and generic USB DFU tooling.
    picocom
    dfu-util

    # Android debugging and device control. android-tools provides adb and
    # fastboot; current systemd uaccess rules provide device access.
    android-tools
    scrcpy

    # Apple mobile-device diagnostics, pairing, file access and recovery.
    libimobiledevice
    ifuse
    idevicerestore
    libirecovery
    ideviceinstaller
    libplist
  ];

  # pymobiledevice3 is intentionally not installed system-wide while its
  # current nixpkgs dependency pyimg4 is marked broken. Re-enable it once the
  # upstream asn1 compatibility issue has been resolved in nixpkgs.
}
