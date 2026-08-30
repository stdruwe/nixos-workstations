{ config, ... }:

{
  imports = [
    ./base.nix
    ../../secureboot.nix
  ];

  # The LUKS TPM2 PIN already serves as local authentication during boot. The
  # notebook therefore also omits the second password prompt in the login
  # manager.
  services.displayManager.autoLogin = {
    enable = true;
    user = config.workstation.userName;
  };
}
