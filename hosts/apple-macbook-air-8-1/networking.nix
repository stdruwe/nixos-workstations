{ ... }:

{
  # T2 Macs expose an internal USB Ethernet/NCM interface with this fixed MAC.
  # It is not a usable external network adapter. Prevent NetworkManager from
  # creating an automatic wired profile for it. Matching by MAC is independent
  # of the kernel-assigned interface name and avoids relying on udev renaming.
  # See: https://wiki.t2linux.org/guides/postinstall/#network-manager-recurrent-notifications
  networking.networkmanager.settings.main.no-auto-default = "mac:ac:de:48:00:11:22";

  # The BCM4355 firmware on this Mac throttles IPv6 receive throughput while
  # brcmfmac's Neighbor Discovery offload (NDOE) is enabled. A PROMISC A/B test
  # disables the firmware ARP/ND offloads and restores normal IPv6 RX speed.
  # Patch only NDOE off for this T2 kernel; keep ARP offload unchanged.
  boot.kernelPatches = [
    {
      name = "apple-t2-brcmfmac-disable-nd-offload";
      patch = ./brcmfmac-disable-nd-offload.patch;
    }
  ];
}
