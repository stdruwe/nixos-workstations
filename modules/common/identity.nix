{ config, lib, ... }:

let
  identityFile = ../../identity.json;
  identity =
    if builtins.pathExists identityFile then
      builtins.fromJSON (builtins.readFile identityFile)
    else
      throw ''
        Local identity is missing: /etc/nixos/identity.json

        This file is intentionally not versioned and must contain at least
        hostName, userName and fullName.
      '';
in
{
  options.workstation = {
    profile = lib.mkOption {
      type = lib.types.enum [
        "thinkpad-x1-carbon-gen13"
        "hp-z2-tower-g9"
        "apple-macbook-air-8-1"
      ];
      description = "Stable technical hardware profile for this system.";
    };

    hostName = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Local hostname from identity.json.";
    };

    userName = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Local administrative user from identity.json.";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Display name of the local user from identity.json.";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "Home directory of the local user.";
    };
  };

  config = {
    workstation = {
      hostName = identity.hostName or "";
      userName = identity.userName or "";
      fullName = identity.fullName or "";
      homeDirectory = "/home/${config.workstation.userName}";
    };

    assertions = [
      {
        assertion = builtins.match "^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$" config.workstation.hostName != null;
        message = "identity.json does not contain a valid hostname.";
      }
      {
        assertion = builtins.match "^[a-z_][a-z0-9_-]{0,30}$" config.workstation.userName != null;
        message = "identity.json does not contain a valid local username.";
      }
      {
        assertion = config.workstation.fullName != "";
        message = "identity.json does not contain a full display name.";
      }
    ];

    networking.hostName = config.workstation.hostName;
  };
}
