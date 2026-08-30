{ config, pkgs, ... }:

let
  userName = config.workstation.userName;
  userAuthorizedKeys = config.workstation.deployment.userAuthorizedKeys or [ ];
in
{
  # The concrete username and display name are local installation data from
  # identity.json. Passwords, password hashes and personal SSH keys do not
  # belong in Git.
  users.users.${userName} = {
    isNormalUser = true;
    description = config.workstation.fullName;
    home = config.workstation.homeDirectory;

    extraGroups = [
      "dialout"
      "networkmanager"
      "wheel"
    ];

    openssh.authorizedKeys.keys = userAuthorizedKeys;
  };

  # /etc/nixos is administratively owned by root:wheel. The setgid bit and
  # default ACL ensure that new Git files inherit group wheel and remain
  # writable by all administrators in wheel. Individual files do not need to
  # remain owned by the same user.
  systemd.services.nixos-config-wheel-access = {
    description = "Maintain root:wheel access for /etc/nixos";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];

    unitConfig.ConditionPathIsDirectory = "/etc/nixos";

    path = [
      pkgs.acl
      pkgs.coreutils
      pkgs.findutils
    ];

    script = ''
      set -euo pipefail

      chown root:wheel /etc/nixos
      chgrp -R wheel /etc/nixos
      chmod 2775 /etc/nixos

      find /etc/nixos -type d -exec chmod g+rws {} +
      find /etc/nixos -type f ! -perm /111 -exec chmod g+rw {} +
      find /etc/nixos -type f -perm /111 -exec chmod g+rwx {} +

      find /etc/nixos -type d -exec \
        setfacl -m g:wheel:rwx,m::rwx,d:g:wheel:rwx,d:m::rwx {} +
      find /etc/nixos -type f ! -perm /111 -exec \
        setfacl -m g:wheel:rw,m::rw {} +
      find /etc/nixos -type f -perm /111 -exec \
        setfacl -m g:wheel:rwx,m::rwx {} +
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}
