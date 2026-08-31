{ pkgs, ... }:

let
  image = "ghcr.io/esphome/esphome:stable";
in
{
  # The HP Z2 Tower G9 is only the remote build worker. The authoritative
  # ESPHome Device Builder remains the Home Assistant app. Using the official
  # ESPHome container keeps ESP-IDF/PlatformIO and their generic Linux
  # toolchains out of the NixOS host environment.
  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";

    containers.esphome = {
      inherit image;
      autoStart = true;

      # Updates are intentionally manual through Topgrade. A reboot must not
      # silently move the build worker to a newer ESPHome release.
      pull = "missing";

      volumes = [
        "/var/lib/esphome-device-builder:/config"
        "/var/cache/esphome-device-builder:/cache"
        "/etc/localtime:/etc/localtime:ro"
      ];

      # Host networking is required for mDNS and lets the Device Builder bind
      # its dashboard and remote-build listener independently.
      extraOptions = [ "--network=host" ];

      # The image entrypoint maps the `dashboard` command to
      # esphome-device-builder. Keep the UI local to this workstation while
      # exposing only the Noise-protected remote-build peer link on the wired
      # LAN.
      cmd = [
        "dashboard"
        "--host"
        "127.0.0.1"
        "--remote-build-host"
        "enp6s0"
        "--remote-build-port"
        "6055"
        "/config"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/esphome-device-builder 0755 root root -"
    "d /var/cache/esphome-device-builder 0755 root root -"
  ];

  # Topgrade starts this unit explicitly. Pulling and restarting are kept in a
  # root service so Topgrade itself does not need to know Podman's root store
  # layout or reproduce the container definition.
  systemd.services.esphome-container-update = {
    description = "Update ESPHome remote-build container";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    path = [
      pkgs.podman
      pkgs.systemd
    ];

    serviceConfig = {
      Type = "oneshot";
    };

    script = ''
      podman pull ${image}
      systemctl restart podman-esphome.service
    '';
  };
}
