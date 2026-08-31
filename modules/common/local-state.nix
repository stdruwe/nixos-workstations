{ pkgs, ... }:

{
  # Keep the machine-specific recovery state in one ignored directory. The
  # installers still create the historical root-level bootstrap files because
  # NixOS must evaluate them before the target system is activated. Activation
  # converts that bootstrap state into the canonical local/ layout atomically.
  system.activationScripts.localRecoveryState.text = ''
    local_dir=/etc/nixos/local

    ${pkgs.coreutils}/bin/install -d -m 2770 -o root -g wheel "$local_dir"

    if [ ! -e "$local_dir/profile.nix" ] && [ -f /etc/nixos/profile.nix ]; then
      ${pkgs.gnused}/bin/sed 's#\./hosts/#../hosts/#g' \
        /etc/nixos/profile.nix > "$local_dir/profile.nix.tmp"
      ${pkgs.coreutils}/bin/install -m 0660 -o root -g wheel \
        "$local_dir/profile.nix.tmp" "$local_dir/profile.nix"
      ${pkgs.coreutils}/bin/rm -f "$local_dir/profile.nix.tmp" /etc/nixos/profile.nix
    fi

    if [ ! -e "$local_dir/identity.json" ] && [ -f /etc/nixos/identity.json ]; then
      ${pkgs.coreutils}/bin/install -m 0660 -o root -g wheel \
        /etc/nixos/identity.json "$local_dir/identity.json"
      ${pkgs.coreutils}/bin/rm -f /etc/nixos/identity.json
    fi

    if [ ! -e "$local_dir/deployment.json" ]; then
      if [ -f /etc/nixos/deployment.json ]; then
        ${pkgs.coreutils}/bin/install -m 0660 -o root -g wheel \
          /etc/nixos/deployment.json "$local_dir/deployment.json"
        ${pkgs.coreutils}/bin/rm -f /etc/nixos/deployment.json
      else
        printf '{}\n' > "$local_dir/deployment.json.tmp"
        ${pkgs.coreutils}/bin/install -m 0660 -o root -g wheel \
          "$local_dir/deployment.json.tmp" "$local_dir/deployment.json"
        ${pkgs.coreutils}/bin/rm -f "$local_dir/deployment.json.tmp"
      fi
    fi

    for file in profile.nix identity.json deployment.json; do
      if [ -f "$local_dir/$file" ]; then
        ${pkgs.coreutils}/bin/chown root:wheel "$local_dir/$file"
        ${pkgs.coreutils}/bin/chmod 0660 "$local_dir/$file"
      fi
    done
  '';
}
