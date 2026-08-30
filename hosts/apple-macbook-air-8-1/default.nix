{ config, ... }:

{
  imports = [
    ./base.nix
  ];

  # Bitwarden is the SSH agent on this host. Keep GCR available for the
  # desktop, but do not start its competing SSH agent under COSMIC.
  services.gnome.gcr-ssh-agent.enable = false;

  # The LUKS passphrase entered during boot serves as local authentication on
  # this T2 Mac. After successful decryption, log directly into COSMIC without
  # a second password prompt in the greeter.
  services.displayManager.autoLogin = {
    enable = true;
    user = config.workstation.userName;
  };
}
