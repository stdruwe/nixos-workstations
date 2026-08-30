{ ... }:

{
  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

  # COSMIC runs natively on Wayland. XWayland remains available through the
  # COSMIC module without enabling an X11 desktop server.
  services.xserver.enable = false;
}
