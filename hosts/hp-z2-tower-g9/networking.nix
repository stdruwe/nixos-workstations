{ lib, ... }:

{
  # The HP Z2 G9 has no WWAN modem.
  networking.modemmanager.enable = false;

  # Avahi should use only the wired LAN port on this profile. The shared
  # services.avahi.openFirewall setting would otherwise open UDP 5353 globally
  # on every interface, so this profile deliberately restricts the allowance
  # to enp6s0.
  services.avahi = {
    allowInterfaces = [ "enp6s0" ];
    openFirewall = lib.mkForce false;
  };

  # ESPHome Device Builder: only the noise-protected remote-build peer link and
  # mDNS discovery are reachable on the wired LAN. The dashboard web interface
  # remains restricted to 127.0.0.1:6052.
  networking.firewall.interfaces."enp6s0" = {
    allowedTCPPorts = [ 6055 ];
    allowedUDPPorts = [ 5353 ];
  };
}
