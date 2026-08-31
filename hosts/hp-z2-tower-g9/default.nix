{ config, pkgs, ... }:

{
  imports = [
    ./base.nix
    ../../secureboot.nix
  ];

  # The LUKS TPM2 PIN already serves as local authentication during boot. On
  # this stationary workstation, the second password prompt is therefore
  # omitted.
  services.displayManager.autoLogin = {
    enable = true;
    user = config.workstation.userName;
  };

  # Radeon-specific diagnostics complement the combined Intel/AMD nvtop build
  # from hardware.nix without adding AMD-only tooling to other profiles.
  environment.systemPackages = [ pkgs.amdgpu_top ];
}
