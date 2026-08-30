{ config, lib, pkgs, ... }:

let
  isApple = config.workstation.profile == "apple-macbook-air-8-1";
  isThinkPad = config.workstation.profile == "thinkpad-x1-carbon-gen13";
  hasBattery = isApple || isThinkPad;
  hasWwan = config.networking.modemmanager.enable;

  desktopLabel =
    if config.services.desktopManager.cosmic.enable then
      "COSMIC ${pkgs.cosmic-session.version}"
    else if config.services.desktopManager.plasma6.enable then
      "KDE Plasma ${pkgs.kdePackages.plasma-workspace.version}"
    else
      "unknown";

  toolPath = pkgs.lib.makeBinPath (
    [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnused
      pkgs.iproute2
      pkgs.networkmanager
    ]
    ++ lib.optionals hasWwan [ pkgs.modemmanager ]
  );

  fastfetchLan = pkgs.writeShellScriptBin "fastfetch-lan" ''
    export PATH=${toolPath}

    found=0

    while IFS=: read -r iface type; do
      [[ "$type" == "ethernet" ]] || continue
      [[ "$iface" == "lo" ]] && continue

      found=1

      state=$(nmcli -g GENERAL.STATE device show "$iface" 2>/dev/null \
        | sed 's/^[0-9]*(//' \
        | sed 's/)$//')

      ip=$(ip -4 -o addr show dev "$iface" scope global 2>/dev/null \
        | awk '{print $4}' \
        | head -n1)

      if [[ -r "/sys/class/net/$iface/speed" ]]; then
        speed=$(cat "/sys/class/net/$iface/speed" 2>/dev/null)
      else
        speed=""
      fi

      if [[ -n "$ip" ]]; then
        if [[ "$speed" =~ ^[0-9]+$ ]] && (( speed > 0 )); then
          printf '%s · %s · %s Mbit/s\n' "$iface" "$ip" "$speed"
        else
          printf '%s · %s\n' "$iface" "$ip"
        fi
      else
        printf '%s · %s\n' "$iface" "''${state:-disconnected}"
      fi
    done < <(nmcli -t -f DEVICE,TYPE device status 2>/dev/null)

    (( found )) || printf 'not present\n'
  '';

  # The ACPI Smart Battery implementation used by the T2 Mac exposes
  # /sys/.../capacity as AbsoluteStateOfCharge, i.e. relative to design
  # capacity. For a user-facing state of charge, use charge_now/charge_full
  # like UPower/COSMIC and report battery health separately.
  fastfetchAppleBattery = pkgs.writeShellScriptBin "fastfetch-apple-battery" ''
    export PATH=${toolPath}

    bat=/sys/class/power_supply/BAT0
    if [[ ! -d "$bat" ]]; then
      printf 'not present\n'
      exit 0
    fi

    charge_now=$(cat "$bat/charge_now" 2>/dev/null || true)
    charge_full=$(cat "$bat/charge_full" 2>/dev/null || true)
    charge_full_design=$(cat "$bat/charge_full_design" 2>/dev/null || true)
    capacity=$(cat "$bat/capacity" 2>/dev/null || true)
    status=$(cat "$bat/status" 2>/dev/null || true)
    cycles=$(cat "$bat/cycle_count" 2>/dev/null || true)

    if [[ "$charge_now" =~ ^[0-9]+$ && "$charge_full" =~ ^[0-9]+$ && "$charge_full" -gt 0 ]]; then
      percent=$(awk -v now="$charge_now" -v full="$charge_full" 'BEGIN { printf "%.0f", now * 100 / full }')
    elif [[ "$capacity" =~ ^[0-9]+$ ]]; then
      percent="$capacity"
    else
      percent="?"
    fi

    health=""
    if [[ "$charge_full" =~ ^[0-9]+$ && "$charge_full_design" =~ ^[0-9]+$ && "$charge_full_design" -gt 0 ]]; then
      health=$(awk -v full="$charge_full" -v design="$charge_full_design" 'BEGIN { printf "%.0f", full * 100 / design }')
    fi

    printf '%s%% [%s]' "$percent" "''${status:-Unknown}"
    [[ -n "$health" ]] && printf ' · %s%% health' "$health"
    [[ "$cycles" =~ ^[0-9]+$ ]] && printf ' · %s cycles' "$cycles"
    printf '\n'
  '';

  fastfetchWwan = pkgs.writeShellScriptBin "fastfetch-wwan" ''
    export PATH=${toolPath}

    soft=0
    hard=0
    rfkill_found=0

    for dev in /sys/class/rfkill/rfkill*; do
      [[ -r "$dev/type" ]] || continue
      [[ "$(cat "$dev/type")" == "wwan" ]] || continue

      rfkill_found=1

      [[ -r "$dev/soft" ]] && (( $(cat "$dev/soft") != 0 )) && soft=1
      [[ -r "$dev/hard" ]] && (( $(cat "$dev/hard") != 0 )) && hard=1
    done

    if (( hard && soft )); then
      printf 'blocked · hardware + software\n'
      exit 0
    elif (( hard )); then
      printf 'blocked · hardware\n'
      exit 0
    elif (( soft )); then
      printf 'blocked · software\n'
      exit 0
    fi

    nm_wwan=$(nmcli -t radio wwan 2>/dev/null)

    if [[ "$nm_wwan" == "disabled" ]]; then
      printf 'disabled · NetworkManager\n'
      exit 0
    fi

    modem=$(
      mmcli -L 2>/dev/null |
        sed -n 's#.*Modem/\([0-9][0-9]*\).*#\1#p' |
        head -n1
    )

    if [[ -z "$modem" ]]; then
      if (( rfkill_found )); then
        printf 'unblocked · modem not detected\n'
      else
        printf 'modem not detected\n'
      fi
      exit 0
    fi

    info=$(mmcli -m "$modem" 2>/dev/null)

    state=$(printf '%s\n' "$info" | sed -n 's/.*|[[:space:]]*state:[[:space:]]*//p' | head -n1)
    tech=$(printf '%s\n' "$info" | sed -n 's/.*|[[:space:]]*access tech:[[:space:]]*//p' | head -n1)
    signal=$(printf '%s\n' "$info" | sed -n 's/.*|[[:space:]]*signal quality:[[:space:]]*//p' | head -n1 | sed -E 's/[[:space:]]*\((recent|cached)\)//')
    operator=$(printf '%s\n' "$info" | sed -n 's/.*|[[:space:]]*operator name:[[:space:]]*//p' | head -n1)

    out=""
    append_part() {
      [[ -n "$1" ]] || return
      if [[ -n "$out" ]]; then out="$out · $1"; else out="$1"; fi
    }

    [[ -n "$operator" && "$operator" != "--" ]] && append_part "$operator"
    [[ -n "$tech" && "$tech" != "unknown" ]] && append_part "$tech"
    [[ -n "$signal" && "$signal" != "--" ]] && append_part "$signal"
    [[ -n "$state" ]] && append_part "$state"

    if [[ -n "$out" ]]; then printf '%s\n' "$out"; else printf 'unblocked · detected\n'; fi
  '';

  batteryModule =
    if isApple then
      ''
        ,
        { "type": "command", "key": "Battery", "text": "${fastfetchAppleBattery}/bin/fastfetch-apple-battery" }
      ''
    else if isThinkPad then
      ''
        ,
        { "type": "battery", "key": "Battery", "format": "{capacity} [{status}] · {cycle-count} cycles" }
      ''
    else
      "";
in
{
  environment.systemPackages =
    [ fastfetchLan ]
    ++ lib.optionals isApple [ fastfetchAppleBattery ]
    ++ lib.optionals hasWwan [ fastfetchWwan ];

  # The regular "de" module is intentionally not used: querying
  # plasmashell --version has already triggered Qt aborts on the ThinkPad over SSH.
  environment.etc."fastfetch/config.jsonc".text = ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
      "logo": { "type": "small", "padding": { "right": 3 } },
      "display": {
        "separator": "  ",
        "color": { "keys": "blue", "title": "cyan" }
      },
      "modules": [
        "title",
        "separator",
        { "type": "os", "key": "OS" },
        { "type": "host", "key": "Host" },
        { "type": "bios", "key": "BIOS", "format": "{version} · {date}" },
        { "type": "kernel", "key": "Kernel" },
        { "type": "uptime", "key": "Uptime" },
        { "type": "packages", "key": "Packages" },
        "break",
        { "type": "custom", "key": "Desktop", "format": "${desktopLabel}" },
        { "type": "shell", "key": "Shell" },
        "break",
        { "type": "cpu", "key": "CPU" },
        { "type": "gpu", "key": "GPU" },
        { "type": "memory", "key": "Memory" },
        { "type": "swap", "key": "Swap" },
        { "type": "disk", "key": "Disk", "folders": "/" }${batteryModule},
        "break",
        { "type": "localip", "key": "Local IP" },
        { "type": "wifi", "key": "Wi-Fi", "format": "{ssid} · {band} GHz · Ch {channel} · {signal-quality}" },
        { "type": "command", "key": "LAN", "text": "${fastfetchLan}/bin/fastfetch-lan" }${lib.optionalString hasWwan ''
        ,
        { "type": "command", "key": "WWAN", "text": "${fastfetchWwan}/bin/fastfetch-wwan" }
        ''}
      ]
    }
  '';
}
