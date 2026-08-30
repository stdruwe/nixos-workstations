{ config, pkgs, ... }:

let
  userName = config.workstation.userName;
  homeDirectory = config.workstation.homeDirectory;
  pendingFile = "/var/lib/nixos/home-manager-initial-activation";
in
{
  # Fresh installers build the selected standalone Home Manager activation
  # package into the target Nix store and write its logical store path to the
  # pending file. The first real boot activates it before the display manager,
  # when nix-daemon and the normal user database are available. Existing
  # systems have no pending file, so this unit is skipped without side effects.
  systemd.services.home-manager-initial-activation = {
    description = "Initial Home Manager activation before first graphical login";

    requiredBy = [ "display-manager.service" ];
    before = [ "display-manager.service" ];
    after = [
      "local-fs.target"
      "nix-daemon.socket"
      "systemd-user-sessions.service"
    ];
    requires = [ "nix-daemon.socket" ];

    unitConfig.ConditionPathExists = pendingFile;

    path = [
      pkgs.coreutils
      pkgs.util-linux
    ];

    serviceConfig.Type = "oneshot";

    script = ''
      activation_path="$(${pkgs.coreutils}/bin/cat ${pendingFile})"

      case "$activation_path" in
        /nix/store/*) ;;
        *)
          echo "Invalid Home Manager activation path: $activation_path" >&2
          exit 1
          ;;
      esac

      if [[ ! -x "$activation_path/activate" ]]; then
        echo "Home Manager activation does not exist: $activation_path/activate" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/install \
        -d \
        -m 0755 \
        -o ${userName} \
        -g users \
        "${homeDirectory}/.config"

      if [[ ! -d "${homeDirectory}/.config/home-manager/.git" ]]; then
        echo "Home Manager repository is missing from ${homeDirectory}/.config/home-manager" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/chown \
        -R \
        ${userName}:users \
        "${homeDirectory}/.config/home-manager"

      ${pkgs.util-linux}/bin/runuser \
        -u ${userName} \
        -- \
        ${pkgs.coreutils}/bin/env \
          USER=${userName} \
          HOME=${homeDirectory} \
          "$activation_path/activate"

      ${pkgs.coreutils}/bin/rm -f ${pendingFile}
    '';
  };
}
