{ ... }:

let
  profileConfig =
    if builtins.pathExists ./profile.nix then
      ./profile.nix
    else
      throw ''
        Local profile selector is missing: /etc/nixos/profile.nix

        Create profile.nix and import exactly one hardware profile:
          ./hosts/thinkpad-x1-carbon-gen13/default.nix
        or:
          ./hosts/hp-z2-tower-g9/default.nix
        or:
          ./hosts/apple-macbook-air-8-1/default.nix

        The local /etc/nixos/identity.json is also required.
      '';
in
{
  imports = [
    profileConfig
  ];
}
