{ pkgs, ... }:

{
  networking.networkmanager = {
    wifi.powersave = true;

    ensureProfiles.profiles."Vodafone" = {
      connection = {
        id = "Vodafone";
        type = "gsm";
        autoconnect = "true";
        autoconnect-priority = 0;
      };

      gsm = {
        apn = "web.vodafone.de";
        auto-config = "false";
      };

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

  systemd.services.ModemManager.serviceConfig.TimeoutStopSec = "5s";
}
