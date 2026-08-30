{ ... }:

{
  # Homelander soll den PipeWire-Audiographen dauerhaft mit 96 kHz betreiben.
  # Andere Quellraten werden von PipeWire auf 96 kHz resampelt.
  services.pipewire.extraConfig.pipewire."99-homelander-96khz" = {
    "context.properties" = {
      "default.clock.rate" = 96000;
      "default.clock.allowed-rates" = [ 96000 ];
      "settings.check-rate" = true;
    };
  };
}
