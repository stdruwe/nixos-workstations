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

    # Extended modern iOS/iPadOS diagnostics and developer interfaces.
    python3Packages.pymobiledevice3
  ];
}
