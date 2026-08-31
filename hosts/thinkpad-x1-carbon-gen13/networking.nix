{ config, lib, pkgs, ... }:

let
  wwanRaw =
    lib.attrByPath [ "networking" "wwan" ] null config.workstation.deployment;
  wwan =
    if wwanRaw == null then
      null
    else if builtins.isAttrs wwanRaw then
      wwanRaw
    else
      throw "deployment.json networking.wwan must be an attribute set";

  wwanConnectionId =
    if wwan == null then
      null
    else
      let
        value = wwan.connectionId or null;
      in
      if builtins.isString value && value != "" then
        value
      else
        throw "deployment.json networking.wwan.connectionId must be a non-empty string";

  wwanApn =
    if wwan == null then
      null
    else
      let
        value = wwan.apn or null;
      in
      if builtins.isString value && value != "" then
        value
      else
        throw "deployment.json networking.wwan.apn must be a non-empty string";

  wwanProfiles =
    if wwan == null then
      { }
    else
      {
        ${wwanConnectionId} = {
          connection = {
            id = wwanConnectionId;
            type = "gsm";
            autoconnect = "true";
            autoconnect-priority = 0;
          };

          gsm = {
            apn = wwanApn;
            auto-config = "false";
          };

          # Keep mobile broadband behind Ethernet/Wi-Fi in the normal route
          # preference order while still allowing it to provide connectivity
          # when the faster local links are unavailable.
          ipv4 = {
            method = "auto";
            route-metric = 700;
          };

          ipv6 = {
            method = "auto";
            route-metric = 700;
          };
        };
      };
in
{
  networking.networkmanager = {
    wifi.powersave = true;

    # Carrier/profile names and APNs are deployment-specific rather than a
    # property of the RM520N-GL hardware. Keep them in ignored
    # local/deployment.json; the hardware profile remains usable without a
    # predefined carrier connection.
    ensureProfiles.profiles = wwanProfiles;
  };

  networking.modemmanager = {
    enable = true;

    fccUnlockScripts = [
      {
        id = "1eac:1007";
        path = "${pkgs.modemmanager}/share/ModemManager/fcc-unlock.available.d/1eac:1007";
      }
    ];
  };

  # The Quectel RM520N-GL loses its MHI state across s2idle when PCIe D3cold
  # is allowed. That forces a full mhi-pci-generic recovery and delays WWAN
  # reconnection by roughly one minute. Keep runtime PM enabled, but prevent
  # D3cold for this modem only.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x1eac", ATTR{device}=="0x1007", ATTR{d3cold_allowed}="0"
  '';

  # An active WWAN modem can otherwise make shutdown wait a very long time for
  # ModemManager to stop. Bound the stop phase to five seconds so an active
  # modem cannot hold up system shutdown indefinitely. See
  # docs/operational-invariants.md before changing this timeout.
  systemd.services.ModemManager.serviceConfig.TimeoutStopSec = "5s";
}
