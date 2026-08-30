{ pkgs, ... }:

let
  keyboardBacklightPower = pkgs.writeShellScriptBin "keyboard-backlight-power" ''
    set -eu
  if [ "$EUID" -ne 0 ]; then
    echo "This program requires root privileges."
    echo "Usage: sudo keyboard-backlight-power"
    exit 1
  fi
    # ------------------------------------------------------------
    # Detect active external power dynamically
    # ------------------------------------------------------------

    on_ac=0

    for supply in /sys/class/power_supply/*; do
      [ -d "$supply" ] || continue
      [ -r "$supply/type" ] || continue
      [ -r "$supply/online" ] || continue

      type="$(${pkgs.coreutils}/bin/cat "$supply/type" 2>/dev/null || true)"

      # Batteries are not external power sources.
      [ "$type" = "Battery" ] && continue

      online="$(${pkgs.coreutils}/bin/cat "$supply/online" 2>/dev/null || true)"

      if [ "$online" = "1" ]; then
        on_ac=1
        break
      fi
    done

    # ------------------------------------------------------------
    # Find the keyboard backlight dynamically
    # ------------------------------------------------------------

    for led in /sys/class/leds/*kbd_backlight*; do
      [ -e "$led/brightness" ] || continue
      [ -r "$led/max_brightness" ] || continue

      if [ "$on_ac" = "1" ]; then
        # AC power: 100%
        value="$(${pkgs.coreutils}/bin/cat "$led/max_brightness")"
      else
        # Battery power: off
        value=0
      fi

      printf '%s\n' "$value" > "$led/brightness"
    done
  '';

in
{
  environment.systemPackages = [
    keyboardBacklightPower
  ];

  # Apply the correct state during normal system startup.
  systemd.services.keyboard-backlight-power = {
    description = "Set keyboard backlight according to AC/battery state";

    wantedBy = [
      "multi-user.target"
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${keyboardBacklightPower}/bin/keyboard-backlight-power";
    };
  };

  # React immediately when an external power source is connected or removed.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ACTION=="change", RUN+="${keyboardBacklightPower}/bin/keyboard-backlight-power"
  '';

  # Reapply the state after suspend/hibernate.
  powerManagement.resumeCommands = ''
    ${keyboardBacklightPower}/bin/keyboard-backlight-power
  '';
}
