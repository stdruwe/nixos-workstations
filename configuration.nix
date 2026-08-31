{ ... }:

let
  profileConfig =
    if builtins.pathExists ./local/profile.nix then
      ./local/profile.nix
    else
      throw ''
        Local profile selector is missing: /etc/nixos/local/profile.nix

        Create local/profile.nix and import exactly one hardware profile:
          ../hosts/thinkpad-x1-carbon-gen13/default.nix
        or:
          ../hosts/hp-z2-tower-g9/default.nix
        or:
          ../hosts/apple-macbook-air-8-1/default.nix

        The local /etc/nixos/local/identity.json is also required.
      '';
in
{
  imports = [
    profileConfig
  ];
}
