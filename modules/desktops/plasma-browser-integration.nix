{ ... }:

let
  extensionSettings = {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi";
    installation_mode = "force_installed";
  };
in
{
  # The Plasma module already exposes plasma-browser-integration as a Firefox
  # native messaging host. Install the matching KDE extension for Firefox and
  # for Zen, which consumes the shared nixpkgs Firefox policy set.
  programs.firefox.policies.ExtensionSettings."plasma-browser-integration@kde.org" =
    extensionSettings;
  nixpkgs.config.firefox.policies.ExtensionSettings."plasma-browser-integration@kde.org" =
    extensionSettings;
}
