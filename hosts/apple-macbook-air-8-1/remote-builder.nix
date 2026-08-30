{ config, lib, ... }:

let
  remoteBuilder = config.workstation.deployment.remoteBuilder or null;
in
{
  assertions = lib.optionals (remoteBuilder != null) [
    {
      assertion = (remoteBuilder.hostName or "") != "";
      message = "deployment.json remoteBuilder.hostName must not be empty.";
    }
    {
      assertion = (remoteBuilder.publicHostKey or "") != "";
      message = "deployment.json remoteBuilder.publicHostKey must not be empty.";
    }
  ];

  # Expensive x86_64-linux builds can be delegated to a deployment-specific
  # ssh-ng builder. A clean/public checkout has no builder configured and
  # therefore continues to build locally.
  nix = lib.mkIf (remoteBuilder != null) {
    distributedBuilds = true;

    buildMachines = [
      {
        hostName = remoteBuilder.hostName or "";
        protocol = remoteBuilder.protocol or "ssh-ng";
        system = remoteBuilder.system or "x86_64-linux";
        sshUser = remoteBuilder.sshUser or "nix-ssh";
        sshKey = remoteBuilder.sshKey or "/root/.ssh/nixbuilder_ed25519";
        maxJobs = remoteBuilder.maxJobs or 4;
        speedFactor = remoteBuilder.speedFactor or 8;
        supportedFeatures = remoteBuilder.supportedFeatures or [
          "nixos-test"
          "benchmark"
          "big-parallel"
          "kvm"
        ];

        # Nix expects the base64 encoding of the complete SSH host public-key
        # file, including its trailing newline.
        publicHostKey = remoteBuilder.publicHostKey or "";
      }
    ];

    settings.builders-use-substitutes = true;
  };
}
