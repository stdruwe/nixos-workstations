{ config, pkgs, ... }:

let
  nixLspSettings = pkgs.writeText "kate-nix-lsp-settings.json" (
    builtins.toJSON {
      servers.nix = {
        command = [ "nixd" ];
        url = "https://github.com/nix-community/nixd";
        highlightingModeRegex = "^Nix$";

        settings.nixd = {
          nixpkgs.expr = "import <nixpkgs> { }";
          formatting.command = [ "nixfmt" ];
          options.nixos.expr = "(import <nixpkgs/nixos> { configuration = /etc/nixos/configuration.nix; }).options";
        };
      };
    }
  );
  homeDirectory = config.workstation.homeDirectory;
  userName = config.workstation.userName;
in
{
  systemd.tmpfiles.rules = [
    "d ${homeDirectory}/.config/kate 0755 ${userName} users -"
    "d ${homeDirectory}/.config/kate/lspclient 0755 ${userName} users -"
    "L+ ${homeDirectory}/.config/kate/lspclient/settings.json - - - - ${nixLspSettings}"
  ];
}
