{ pkgs, ... }:

let
  pluginId = "net.stdruwe.usbpdstatus";

  usbPdStatus = pkgs.writeShellScriptBin "usb-pd-status" ''
        set -u

        read_one() {
          if [ -r "$1" ]; then
            ${pkgs.coreutils}/bin/tr -d '\n' < "$1"
          fi
        }

        is_uint() {
          case "$1" in
            ""|*[!0-9]*) return 1 ;;
            *) return 0 ;;
          esac
        }

        battery=""
        for b in /sys/class/power_supply/BAT*; do
          if [ -d "$b" ]; then
            battery="$b"
            break
          fi
        done

        bat_status="unknown"
        bat_capacity="-1"
        bat_mw="0"

        if [ -n "$battery" ]; then
          value="$(read_one "$battery/status")"
          [ -n "$value" ] && bat_status="$value"

          value="$(read_one "$battery/capacity")"
          if is_uint "$value"; then
            bat_capacity="$value"
          fi

          value="$(read_one "$battery/power_now")"
          if is_uint "$value"; then
            bat_mw=$(( value / 1000 ))
          fi
        fi

        active_name=""
        active_status="unknown"
        active_mv="0"
        active_ma="0"
        active_mw="0"

        port_lines=""

        for p in /sys/class/power_supply/ucsi-source-psy-*; do
          [ -d "$p" ] || continue

          name="$(${pkgs.coreutils}/bin/basename "$p")"
          online="$(read_one "$p/online")"
          [ -n "$online" ] || online="0"

          status="$(read_one "$p/status")"
          [ -n "$status" ] || status="unknown"

          uv="$(read_one "$p/voltage_now")"
          ua="$(read_one "$p/current_now")"
          uw="$(read_one "$p/power_now")"

          mv="0"
          ma="0"
          mw="0"

          if is_uint "$uv"; then
            mv=$(( uv / 1000 ))
          fi

          if is_uint "$ua"; then
            ma=$(( ua / 1000 ))
          fi

          if is_uint "$uv" && is_uint "$ua" && [ "$uv" -gt 0 ] && [ "$ua" -gt 0 ]; then
            mw=$(( uv * ua / 1000000000 ))
          elif is_uint "$uw"; then
            mw=$(( uw / 1000 ))
          fi

          port_lines="$port_lines
    PORT|$name|$online|$status|$mv|$ma|$mw"

          if [ "$online" = "1" ]; then
            if [ -z "$active_name" ] || [ "$mw" -gt "$active_mw" ]; then
              active_name="$name"
              active_status="$status"
              active_mv="$mv"
              active_ma="$ma"
              active_mw="$mw"
            fi
          fi
        done

        mode="NONE"
        display_mw="0"

        if [ "$bat_status" = "Discharging" ] && [ "$bat_mw" -gt 0 ]; then
          mode="BAT"
          display_mw="$bat_mw"
        elif [ -n "$active_name" ]; then
          mode="PD"
          display_mw="$active_mw"
        fi

        printf 'SUMMARY|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
          "$mode" "$display_mw" "$active_name" "$active_status" \
          "$active_mv" "$active_ma" "$bat_status" "$bat_capacity" "$bat_mw"

        if [ -n "$port_lines" ]; then
          printf '%s\n' "$port_lines" | ${pkgs.coreutils}/bin/tail -n +2
        fi
  '';

  plasmoid = pkgs.runCommand "usb-pd-status-plasmoid" { } ''
    root="$out/share/plasma/plasmoids/${pluginId}"
    mkdir -p "$root/contents/ui"

    cat > "$root/metadata.json" <<'JSON'
    {
      "KPackageStructure": "Plasma/Applet",
      "KPlugin": {
        "Category": "System Information",
        "Description": "Shows USB-C Power Delivery input power or battery discharge power",
        "Icon": "battery",
        "Id": "${pluginId}",
        "License": "MIT",
        "Name": "USB-C PD Status",
        "Version": "1.0"
      },
      "X-Plasma-API-Minimum-Version": "6.0"
    }
    JSON

    cat > "$root/contents/ui/main.qml" <<'QML'
    import QtQuick
    import QtQuick.Layouts
    import org.kde.kirigami as Kirigami
    import org.kde.plasma.components as PlasmaComponents
    import org.kde.plasma.plasmoid
    import org.kde.plasma.plasma5support as Plasma5Support

    PlasmoidItem {
        id: root

        property string command: "${usbPdStatus}/bin/usb-pd-status"
        property string mode: "NONE"
        property int displayMw: 0
        property string activePort: ""
        property string activeStatus: "unknown"
        property int activeMv: 0
        property int activeMa: 0
        property string batteryStatus: "unknown"
        property int batteryCapacity: -1
        property int batteryMw: 0
        property var ports: []

        preferredRepresentation: compactRepresentation

        toolTipMainText: mode === "PD" ? "USB-C Power Delivery"
                         : mode === "BAT" ? "Battery discharge"
                         : "USB-C PD / Battery"
        toolTipSubText: mode === "PD"
                        ? (formatPower(displayMw) + " · " + formatVoltage(activeMv) + " · " + formatCurrent(activeMa))
                        : mode === "BAT"
                          ? (formatPower(displayMw) + (batteryCapacity >= 0 ? " · " + batteryCapacity + "%" : ""))
                          : "No active PD power available"

        function numberOrZero(value) {
            var n = Number(value)
            return isFinite(n) ? Math.round(n) : 0
        }

        function formatPower(mw) {
            return mw > 0 ? (mw / 1000.0).toFixed(1) + " W" : "-- W"
        }

        function formatVoltage(mv) {
            return mv > 0 ? (mv / 1000.0).toFixed(2) + " V" : "-- V"
        }

        function formatCurrent(ma) {
            return ma > 0 ? (ma / 1000.0).toFixed(2) + " A" : "-- A"
        }

        function parseOutput(text) {
            var lines = text.trim().split("\n")
            var parsedPorts = []

            for (var i = 0; i < lines.length; ++i) {
                if (lines[i].length === 0)
                    continue

                var f = lines[i].split("|")

                if (f[0] === "SUMMARY" && f.length >= 10) {
                    mode = f[1]
                    displayMw = numberOrZero(f[2])
                    activePort = f[3]
                    activeStatus = f[4]
                    activeMv = numberOrZero(f[5])
                    activeMa = numberOrZero(f[6])
                    batteryStatus = f[7]
                    batteryCapacity = Number(f[8])
                    batteryMw = numberOrZero(f[9])
                } else if (f[0] === "PORT" && f.length >= 7) {
                    parsedPorts.push({
                        "name": f[1],
                        "online": f[2] === "1",
                        "status": f[3],
                        "mv": numberOrZero(f[4]),
                        "ma": numberOrZero(f[5]),
                        "mw": numberOrZero(f[6])
                    })
                }
            }

            ports = parsedPorts
        }

        Plasma5Support.DataSource {
            id: executableSource
            engine: "executable"
            connectedSources: [root.command]
            interval: 5000

            onNewData: function(sourceName, data) {
                if (data["stdout"] !== undefined)
                    root.parseOutput(String(data["stdout"]))
            }
        }

        compactRepresentation: Item {
            Layout.minimumWidth: compactLabel.implicitWidth + Kirigami.Units.largeSpacing
            Layout.preferredWidth: compactLabel.implicitWidth + Kirigami.Units.largeSpacing
            Layout.fillHeight: true

            PlasmaComponents.Label {
                id: compactLabel
                anchors.centerIn: parent
                text: root.formatPower(root.displayMw)
                font.bold: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.expanded = !root.expanded
            }
        }

        fullRepresentation: Item {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 20
            Layout.preferredHeight: details.implicitHeight + Kirigami.Units.largeSpacing * 2

            ColumnLayout {
                id: details
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                Kirigami.Heading {
                    level: 3
                    text: root.mode === "PD" ? "USB-C Power Delivery"
                          : root.mode === "BAT" ? "Battery discharge"
                          : "USB-C PD / Battery"
                }

                PlasmaComponents.Label {
                    text: root.mode === "PD"
                          ? "Power: " + root.formatPower(root.displayMw)
                          : root.mode === "BAT"
                            ? "Discharge: " + root.formatPower(root.displayMw)
                            : "No active PD power available"
                    font.bold: true
                }

                PlasmaComponents.Label {
                    visible: root.mode === "PD"
                    text: "Active port: " + (root.activePort.length > 0 ? root.activePort : "-")
                }

                PlasmaComponents.Label {
                    visible: root.mode === "PD"
                    text: "Status: " + root.activeStatus
                }

                PlasmaComponents.Label {
                    visible: root.mode === "PD"
                    text: "Voltage / Current: " + root.formatVoltage(root.activeMv) + " / " + root.formatCurrent(root.activeMa)
                }

                PlasmaComponents.Label {
                    text: "Battery: " + root.batteryStatus
                          + (root.batteryCapacity >= 0 ? " · " + root.batteryCapacity + "%" : "")
                          + (root.batteryMw > 0 ? " · " + root.formatPower(root.batteryMw) : "")
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                    visible: root.ports.length > 0
                }

                PlasmaComponents.Label {
                    visible: root.ports.length > 0
                    text: "USB-C ports"
                    font.bold: true
                }

                Repeater {
                    model: root.ports

                    delegate: PlasmaComponents.Label {
                        required property var modelData
                        text: modelData.name + ": "
                              + (modelData.online ? "online" : "offline")
                              + " · " + modelData.status
                              + (modelData.mw > 0 ? " · " + root.formatPower(modelData.mw) : "")
                              + (modelData.mv > 0 ? " · " + root.formatVoltage(modelData.mv) : "")
                              + (modelData.ma > 0 ? " · " + root.formatCurrent(modelData.ma) : "")
                    }
                }
            }
        }
    }
    QML
  '';

  panelScript = pkgs.writeText "usb-pd-add-to-panel.js" ''
    const pluginId = "${pluginId}";
    const allPanels = panels();
    let target = null;

    for (let i = 0; i < allPanels.length; ++i) {
        if (allPanels[i].formFactor === "horizontal" && allPanels[i].location === "bottom") {
            target = allPanels[i];
            break;
        }
    }

    if (target === null) {
        for (let i = 0; i < allPanels.length; ++i) {
            if (allPanels[i].formFactor === "horizontal") {
                target = allPanels[i];
                break;
            }
        }
    }

    if (target === null && allPanels.length > 0)
        target = allPanels[0];

    if (target !== null && target.widgets(pluginId).length === 0) {
        const widget = target.addWidget(pluginId);
        const trays = target.widgets("org.kde.plasma.systemtray");
        if (trays.length > 0)
            widget.index = trays[0].index;
    }
  '';

  panelInstaller = pkgs.writeShellScriptBin "usb-pd-add-to-panel" ''
    set -eu

    script="$(${pkgs.coreutils}/bin/cat ${panelScript})"

    for attempt in $(${pkgs.coreutils}/bin/seq 1 30); do
      if ${pkgs.systemd}/bin/busctl --user call \
        org.kde.plasmashell \
        /PlasmaShell \
        org.kde.PlasmaShell \
        evaluateScript \
        s "$script" >/dev/null 2>&1
      then
        exit 0
      fi

      ${pkgs.coreutils}/bin/sleep 1
    done

    echo "PlasmaShell did not become available in time for the USB-C PD plasmoid." >&2
    exit 1
  '';

in
{
  environment.systemPackages = [
    usbPdStatus
    plasmoid
    pkgs.kdePackages.plasma5support
  ];

  systemd.user.services.usb-pd-plasmoid-panel = {
    description = "Insert USB-C PD plasmoid into Plasma panel";
    wantedBy = [ "graphical-session.target" ];
    after = [ "plasma-plasmashell.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${panelInstaller}/bin/usb-pd-add-to-panel";
      RemainAfterExit = true;
    };
  };
}
