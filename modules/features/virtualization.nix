{ config, pkgs, ... }:

let
  virtManagerGerman = pkgs.virt-manager.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (old.postFixup or "") + ''
      wrapProgram $out/bin/virt-manager \
        --set LANG de_DE.UTF-8 \
        --set LANGUAGE de \
        --set LC_MESSAGES de_DE.UTF-8
    '';
  });
in
{
  # KVM/QEMU virtualization managed through libvirt and virt-manager.
  virtualisation.libvirtd = {
    enable = true;

    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
      vhostUserPackages = with pkgs; [
        virtiofsd
      ];
    };
  };

  programs.virt-manager = {
    enable = true;
    package = virtManagerGerman;
  };

  virtualisation.spiceUSBRedirection.enable = true;

  # Allow the regular desktop user to manage system libvirt VMs.
  users.users.${config.workstation.userName}.extraGroups = [
    "libvirtd"
  ];

  # libvirt's default NAT network uses virbr0. This does not bridge a
  # physical WLAN, WWAN or Ethernet interface.
  networking.firewall.trustedInterfaces = [
    "virbr0"
  ];

  # Required for DHCP/DNS on libvirt's default NAT network.
  environment.systemPackages = with pkgs; [
    dnsmasq
  ];

  # libvirt-guests logs status messages directly to the console upstream.
  # Keep them in the journal so they cannot overwrite the Plymouth shutdown
  # splash while guests are suspended or when no guests are running.
  systemd.services.libvirt-guests.serviceConfig = {
    StandardOutput = "journal";
    StandardError = "journal";
  };

  # Ensure libvirt's default NAT network is present, enabled for autostart,
  # and active. NixOS currently has no native option for declarative libvirt
  # network definitions, so this idempotent unit keeps the desired state.
  systemd.services.libvirt-default-network = {
    description = "Ensure libvirt default NAT network";
    wantedBy = [ "multi-user.target" ];
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];

    path = [ pkgs.libvirt ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      if ! virsh --connect qemu:///system net-info default >/dev/null 2>&1; then
        virsh --connect qemu:///system net-define \
          ${pkgs.libvirt}/var/lib/libvirt/qemu/networks/default.xml
      fi

      virsh --connect qemu:///system net-autostart default

      if ! virsh --connect qemu:///system net-info default \
        | grep -q '^Active:[[:space:]]*yes$'; then
        virsh --connect qemu:///system net-start default
      fi
    '';
  };

  # Keep the current nixpkgs-provided Windows VirtIO driver ISO available
  # under a stable path for virt-manager. Updating nixpkgs updates the target.
  system.activationScripts.virtio-win-iso.text = ''
    mkdir -p /var/lib/libvirt/iso
    ln -sfn ${pkgs.virtio-win.src} /var/lib/libvirt/iso/virtio-win.iso
  '';
}
