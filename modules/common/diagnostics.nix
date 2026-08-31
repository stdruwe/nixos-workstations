{ config, pkgs, ... }:

{
  # Enable Wireshark through the NixOS module so dumpcap permissions are
  # configured correctly for the machine-local workstation user.
  programs.wireshark.enable = true;
  users.users.${config.workstation.userName}.extraGroups = [ "wireshark" ];

  environment.systemPackages =
    (with pkgs; [
      # Hardware and firmware diagnostics.
      dmidecode
      lshw
      lm_sensors
      acpica-tools
      usbtop
      lsof
      strace
      tpm2-tools
      efitools

      # Performance, load and I/O diagnostics.
      sysstat
      iotop
      stress-ng
      fio
      memtester

      # Storage, filesystem and recovery tools.
      parted
      gptfdisk
      cryptsetup
      btrfs-progs
      dosfstools
      exfatprogs
      ntfs3g
      testdisk
      ddrescue
      hdparm
      sg3_utils

      # Network diagnostics.
      iperf3
      mtr
      traceroute
      nmap
      tcpdump
      bind
      socat
      netcat-openbsd
      whois
      arp-scan

      # Graphics and display diagnostics.
      vulkan-tools
      mesa-demos
      wayland-utils
      edid-decode
      drm_info
      ddcutil
    ])
    ++ [ config.boot.kernelPackages.perf ];
}
