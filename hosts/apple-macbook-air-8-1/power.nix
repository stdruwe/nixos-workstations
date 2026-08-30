{ ... }:

{
  # COSMIC already enables power-profiles-daemon by default. The MacBook
  # profile keeps that choice explicit; TLP is not used in parallel.
  services.power-profiles-daemon.enable = true;
}
