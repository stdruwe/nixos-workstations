{ config, pkgs, ... }:

let
  lockedPreference = value: {
    Value = value;
    Status = "locked";
  };

  # Firefox, Zen Browser and Thunderbird use the same Gecko preference for
  # middle-click autoscroll. "locked" ensures that it remains enabled and
  # cannot be disabled again by profile-specific state.
  autoScrollPreference = lockedPreference true;

  # Consistent Gecko defaults across all hardware profiles. Websites and HTML
  # mail may still request their own fonts; these preferences define the
  # generic sans-serif/serif/monospace families and defaults for Latin and
  # other Unicode text. New York Medium is a Fontconfig alias that resolves to
  # Apple's New York variable family at Medium weight for normal serif text.
  geckoFontPreferences = {
    "font.default.x-western" = lockedPreference "sans-serif";
    "font.name.sans-serif.x-western" = lockedPreference "SF Pro";
    "font.name.serif.x-western" = lockedPreference "New York Medium";
    "font.name.monospace.x-western" = lockedPreference "SF Mono";

    "font.default.x-unicode" = lockedPreference "sans-serif";
    "font.name.sans-serif.x-unicode" = lockedPreference "SF Pro";
    "font.name.serif.x-unicode" = lockedPreference "New York Medium";
    "font.name.monospace.x-unicode" = lockedPreference "SF Mono";
  };
in
{
  # Zen Browser carries these nixpkgs Firefox policies into its own
  # distribution/policies.json. Firefox itself receives the same preferences
  # explicitly below through the NixOS module.
  nixpkgs.config.firefox.policies.Preferences =
    geckoFontPreferences
    // {
      "general.autoScroll" = autoScrollPreference;
    };

  programs.firefox = {
    enable = true;
    languagePacks = [ "de" ];

    policies = {
      RequestedLocales = [ "de" ];
      Preferences =
        geckoFontPreferences
        // {
          "general.autoScroll" = autoScrollPreference;
        };
      Homepage.StartPage = "previous-session";

      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          installation_mode = "force_installed";
        };
        "gesturefy@robbendebiene.de" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/gesturefy/latest.xpi";
          installation_mode = "normal_installed";
        };
        "sponsorBlocker@ajay.app" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/sponsorblock/latest.xpi";
          installation_mode = "normal_installed";
        };
      };
    };
  };

  programs.thunderbird = {
    enable = true;
    policies = {
      RequestedLocales = "de";
      Preferences =
        geckoFontPreferences
        // {
          "general.autoScroll" = autoScrollPreference;
        };
      ExtensionSettings."langpack-de@thunderbird.mozilla.org" = {
        installation_mode = "force_installed";
        install_url = "https://releases.mozilla.org/pub/thunderbird/releases/${pkgs.thunderbird.version}/linux-x86_64/xpi/de.xpi";
      };
    };
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
    package = pkgs.appimage-run.override {
      extraPkgs = pkgs: [
        pkgs.libepoxy
        pkgs.mpv
      ];
    };
  };

  environment.etc."mpv/mpv.conf".text = ''
    hwdec=vaapi
    vo=gpu-next
    gpu-api=vulkan
    gpu-context=waylandvk
    target-colorspace-hint=auto
  '';

  services.flatpak.enable = true;

  environment.sessionVariables = {
    # Use Bitwarden Desktop as the primary SSH agent for the local desktop user.
    SSH_AUTH_SOCK = "${config.workstation.homeDirectory}/.bitwarden-ssh-agent.sock";
  };

  programs.bash.interactiveShellInit = ''
    if [[ -t 1 && -z "''${FASTFETCH_SHOWN:-}" ]]; then
      export FASTFETCH_SHOWN=1
      fastfetch --config /etc/fastfetch/config.jsonc
    fi
  '';
}
