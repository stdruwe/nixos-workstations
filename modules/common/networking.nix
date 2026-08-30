{ pkgs, ... }:

{
  networking.networkmanager = {
    enable = true;

    # Ethernet and Wi-Fi receive reproducible route metrics on all hosts.
    settings = {
      "connection-ethernet-priority" = {
        "match-device" = "type:ethernet";
        "ipv4.route-metric" = 100;
        "ipv6.route-metric" = 100;
      };

      "connection-wifi-priority" = {
        "match-device" = "type:wifi";
        "ipv4.route-metric" = 200;
        "ipv6.route-metric" = 200;
      };
    };

    # Ethernet/Wi-Fi profiles created dynamically through Plasma are normalized
    # to the desired autoconnect priority afterward.
    dispatcherScripts = [
      {
        type = "basic";

        source = pkgs.writeShellScript "networkmanager-autoconnect-priority" ''
          [ "$2" = "up" ] || exit 0
          [ -n "''${CONNECTION_UUID:-}" ] || exit 0

          con_type="$(
            ${pkgs.networkmanager}/bin/nmcli \
              -g connection.type \
              connection show uuid "$CONNECTION_UUID" \
              2>/dev/null || true
          )"

          case "$con_type" in
            802-3-ethernet|ethernet)
              priority=20
              ;;
            802-11-wireless|wifi)
              priority=10
              ;;
            *)
              exit 0
              ;;
          esac

          current="$(
            ${pkgs.networkmanager}/bin/nmcli \
              -g connection.autoconnect-priority \
              connection show uuid "$CONNECTION_UUID" \
              2>/dev/null || true
          )"

          if [ "$current" != "$priority" ]; then
            ${pkgs.networkmanager}/bin/nmcli \
              connection modify uuid "$CONNECTION_UUID" \
              connection.autoconnect-priority "$priority"
          fi
        '';
      }
    ];
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
