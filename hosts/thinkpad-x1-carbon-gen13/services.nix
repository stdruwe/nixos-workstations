{ pkgs, ... }:

{
  # GNSS/GPS through the Quectel RM520N-GL.
  services.gpsd = {
    enable = true;
    devices = [ "/dev/gnss0" ];
    readonly = true;
    nowait = false;
  };

  services.udev.extraRules = ''
    SUBSYSTEM=="gnss", KERNEL=="gnss[0-9]*", GROUP="dialout", MODE="0660"
    SUBSYSTEM=="wwan", KERNEL=="wwan*at*", GROUP="dialout", MODE="0660"
  '';

  environment.etc."gpsd/device-hook".source = pkgs.writeShellScript "gpsd-device-hook" ''
    DEVICE="$1"
    ACTION="$2"

    if [ "$DEVICE" != "/dev/gnss0" ]; then
      exit 0
    fi

    case "$ACTION" in
      ACTIVATE)
        ${pkgs.util-linux}/bin/logger \
          -t quectel-gnss \
          "GNSS requested - enabling RM520N-GL"

        # gpsd can request GNSS before ModemManager/kernel device discovery has
        # made the modem AT endpoint writable. Keep this bounded five-second
        # retry window; shortening it can make the first GNSS request fail even
        # though /dev/gnss0 already exists. See docs/operational-invariants.md.
        for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
          if [ -w /dev/wwan0at0 ]; then
            printf 'AT+QGPS=1\r' > /dev/wwan0at0
            exit 0
          fi

          ${pkgs.coreutils}/bin/sleep 0.1
        done

        ${pkgs.util-linux}/bin/logger \
          -t quectel-gnss \
          "Could not enable GNSS: /dev/wwan0at0 unavailable"

        exit 1
        ;;

      DEACTIVATE)
        ${pkgs.util-linux}/bin/logger \
          -t quectel-gnss \
          "GNSS no longer requested - disabling RM520N-GL"

        if [ -w /dev/wwan0at0 ]; then
          printf 'AT+QGPSEND\r' > /dev/wwan0at0
        fi
        ;;
    esac
  '';

  # The Quectel RM5xx card sits behind this verified PCIe root port. Keep it
  # usable during normal operation, but prevent it from waking the laptop from
  # s2idle. The hard-coded path is model-specific and must not be generalized
  # without rechecking the PCI topology. See docs/operational-invariants.md.
  systemd.services.disable-wwan-wakeup = {
    description = "Disable wakeup from the Quectel WWAN PCIe root port";

    wantedBy = [ "sleep.target" ];
    before = [ "sleep.target" ];

    script = ''
      set -eu

      wakeup=/sys/bus/pci/devices/0000:00:1c.3/power/wakeup
      if [ ! -e "$wakeup" ]; then
        printf '%s\n' "WWAN PCIe root-port wakeup control missing: $wakeup" >&2
        exit 1
      fi

      printf disabled > "$wakeup"
      read -r state < "$wakeup"
      [ "$state" = disabled ]
    '';

    serviceConfig.Type = "oneshot";
  };
}
