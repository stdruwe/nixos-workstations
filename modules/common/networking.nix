{ config, lib, pkgs, ... }:

let
  localSubnetsRaw =
    lib.attrByPath [ "networking" "localSubnets" ] [ ] config.workstation.deployment;
  localSubnets =
    if builtins.isList localSubnetsRaw && lib.all builtins.isString localSubnetsRaw then
      lib.unique localSubnetsRaw
    else
      throw "deployment.json networking.localSubnets must be a list of CIDR strings";
  rulePriority = 2500;

  addLocalSubnetRules = pkgs.writeShellScript "add-local-subnet-routing-rules" (
    lib.concatMapStringsSep "\n" (
      subnet:
      let
        family = if lib.hasInfix ":" subnet then "-6" else "-4";
        escapedSubnet = lib.escapeShellArg subnet;
      in
      ''
        ${pkgs.iproute2}/bin/ip ${family} rule del \
          priority ${toString rulePriority} \
          to ${escapedSubnet} \
          lookup main \
          suppress_prefixlength 0 \
          2>/dev/null || true

        ${pkgs.iproute2}/bin/ip ${family} rule add \
          priority ${toString rulePriority} \
          to ${escapedSubnet} \
          lookup main \
          suppress_prefixlength 0
      ''
    ) localSubnets
  );

  removeLocalSubnetRules = pkgs.writeShellScript "remove-local-subnet-routing-rules" (
    lib.concatMapStringsSep "\n" (
      subnet:
      let
        family = if lib.hasInfix ":" subnet then "-6" else "-4";
        escapedSubnet = lib.escapeShellArg subnet;
      in
      ''
        ${pkgs.iproute2}/bin/ip ${family} rule del \
          priority ${toString rulePriority} \
          to ${escapedSubnet} \
          lookup main \
          suppress_prefixlength 0 \
          2>/dev/null || true
      ''
    ) localSubnets
  );
in
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

  # Tailscale subnet routes use policy-routing rules with higher numeric
  # priorities. When one of those routes overlaps the workstation's physical
  # LAN, prefer a real connected route from the main table. Suppressing the
  # main-table default route is essential: away from that LAN the lookup then
  # falls through to Tailscale instead of sending the private subnet toward the
  # ordinary Internet default gateway.
  systemd.services.local-subnet-routing = lib.mkIf (localSubnets != [ ]) {
    description = "Prefer directly connected local subnets over overlay routes";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    before = [ "tailscaled.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = addLocalSubnetRules;
      ExecStop = removeLocalSubnetRules;
    };
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };
}
