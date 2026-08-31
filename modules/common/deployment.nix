{ lib, ... }:

let
  localDeploymentFile = ../../local/deployment.json;
  bootstrapDeploymentFile = ../../deployment.json;
  deploymentFile =
    if builtins.pathExists localDeploymentFile then
      localDeploymentFile
    else
      bootstrapDeploymentFile;
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
    description = "Optional machine-local deployment data from local/deployment.json.";
  };
}
