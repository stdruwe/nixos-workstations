{ config, lib, pkgs, ... }:

let
  plasmaBrowserIntegration = pkgs.kdePackages.plasma-browser-integration;
  nativeMessagingManifest =
    "${plasmaBrowserIntegration}/lib/mozilla/native-messaging-hosts/org.kde.plasma.browser_integration.json";

  extensionSettings = {
    install_url = "https://addons.mozilla.org/firefox/downloads/latest/plasma-integration/latest.xpi";
    installation_mode = "force_installed";
  };
in
{
  config = lib.mkIf config.services.desktopManager.plasma6.enable {
    # Zen Browser consumes the Firefox policies from nixpkgs.config, while
    # Firefox receives the same extension through its NixOS module.
    nixpkgs.config.firefox.policies.ExtensionSettings."plasma-browser-integration@kde.org" =
      extensionSettings;
    programs.firefox.policies.ExtensionSettings."plasma-browser-integration@kde.org" =
      extensionSettings;

    # Zen currently looks for per-user native messaging manifests in the
    # Mozilla directory. Expose Plasma's native host there declaratively.
    systemd.user.tmpfiles.rules = [
      "d %h/.mozilla 0755 - - -"
      "d %h/.mozilla/native-messaging-hosts 0755 - - -"
      "L+ %h/.mozilla/native-messaging-hosts/org.kde.plasma.browser_integration.json - - - - ${nativeMessagingManifest}"
    ];
  };
}
