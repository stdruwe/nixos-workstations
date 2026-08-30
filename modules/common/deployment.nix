{ lib, ... }:

let
  deploymentFile = ../../deployment.json;
  deployment =
    if builtins.pathExists deploymentFile then
      builtins.fromJSON (builtins.readFile deploymentFile)
    else
      { };
in
{
  options.workstation.deployment = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    internal = true;
    default = deployment;
    description = "Optional local deployment data from deployment.json.";
  };
}
