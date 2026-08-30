{ config, lib, ... }:

let
  builder = config.workstation.deployment.nixBuilder or { };
  authorizedKeys = builder.authorizedKeys or [ ];
in
{
  # Expose this profile as a restricted Nix remote builder only when local
  # deployment data provides authorized client keys. NixOS creates the
  # dedicated `nix-ssh` system user and restricts it to Nix daemon traffic.
  nix.sshServe = lib.mkIf (authorizedKeys != [ ]) {
    enable = true;
    protocol = "ssh-ng";
    trusted = true;
    keys = authorizedKeys;
  };
}
