{ config, pkgs, ... }:

let
  # btop reads CPU power directly from the Intel RAPL energy counter.
  # energy_uj is 0400 root:root by default. Instead of granting btop the broad
  # CAP_DAC_READ_SEARCH DAC bypass capability, only the dedicated powercap
  # group receives read access to this specific counter.
  raplEnergyAccess = pkgs.writeShellScript "rapl-energy-access" ''
    devpath="$1"
    energy="/sys$devpath/energy_uj"

    [ -e "$energy" ] || exit 0

    ${pkgs.coreutils}/bin/chgrp powercap "$energy" 2>/dev/null || exit 0
    ${pkgs.coreutils}/bin/chmod 0440 "$energy"
  '';
in
{
  users.groups.powercap = { };
  users.users.${config.workstation.userName}.extraGroups = [ "powercap" ];

  # If the Intel RAPL zone node is recreated, for example after a module
  # reload, the narrow group permissions are applied again automatically.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="powercap", KERNEL=="intel-rapl:0", RUN+="${raplEnergyAccess} %p"
  '';

  # Covers normal boot and nixos-rebuild switch. On systems without the
  # matching Intel RAPL counter, ConditionPathExists keeps this service inert.
  systemd.services.rapl-energy-access = {
    description = "Grant powercap group read access to Intel RAPL energy counter";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udevd.service" ];

    unitConfig.ConditionPathExists = "/sys/class/powercap/intel-rapl:0/energy_uj";

    serviceConfig.Type = "oneshot";

    script = ''
      ${pkgs.coreutils}/bin/chgrp powercap /sys/class/powercap/intel-rapl:0/energy_uj
      ${pkgs.coreutils}/bin/chmod 0440 /sys/class/powercap/intel-rapl:0/energy_uj
    '';
  };
}
