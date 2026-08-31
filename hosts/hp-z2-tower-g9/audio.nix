{ ... }:

{
  # Keep the HP Z2 Tower G9 PipeWire graph fixed at 96 kHz.
  # PipeWire resamples other source rates to 96 kHz.
  services.pipewire.extraConfig.pipewire."99-hp-z2-tower-g9-96khz" = {
    "context.properties" = {
      "default.clock.rate" = 96000;
      "default.clock.allowed-rates" = [ 96000 ];
      "settings.check-rate" = true;
    };
  };
}
