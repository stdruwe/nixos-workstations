{ pkgs, ... }:

{
  services.pulseaudio.enable = false;

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa = {
      enable = true;
      support32Bit = true;
    };

    pulse.enable = true;
  };

  environment.systemPackages = with pkgs; [
    easyeffects
    audacity
  ];
}
