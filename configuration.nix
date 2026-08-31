{ ... }:

let
  localProfile = ./local/profile.nix;
  bootstrapProfile = ./profile.nix;
  profileConfig =
    if builtins.pathExists localProfile then
      localProfile
    else if builtins.pathExists bootstrapProfile then
      bootstrapProfile
    else
      throw ''
        Local profile selector is missing: /etc/nixos/local/profile.nix

        Create local/profile.nix and import exactly one hardware profile:
          ../hosts/thinkpad-x1-carbon-gen13/default.nix
        or:
          ../hosts/hp-z2-tower-g9/default.nix
        or:
          ../hosts/apple-macbook-air-8-1/default.nix

        During installation only, /etc/nixos/profile.nix is accepted as a
        bootstrap selector and is migrated into local/ during activation.
        The canonical /etc/nixos/local/identity.json is also required after
        activation.
      '';
in
{
  imports = [
    profileConfig
  ];
}
