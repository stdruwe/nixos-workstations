{
  lib,
  coreutils,
  writeShellApplication,
}:

writeShellApplication {
  name = "nixos-needsreboot";

  runtimeInputs = [ coreutils ];

  text = ''
    dryRun=0

    for arg in "$@"; do
      case "$arg" in
        --dry-run)
          dryRun=1
          ;;
        --version)
          echo "nixos-needsreboot: NixOS system-artifact checker"
          exit 0
          ;;
        *)
          echo "Unknown argument: $arg" >&2
          exit 1
          ;;
      esac
    done

    if [ "$dryRun" -ne 1 ] && [ "$(id -u)" -ne 0 ]; then
      echo "ERROR: please run this as root" >&2
      echo "HINT: use the '--dry-run' option" >&2
      exit 1
    fi

    booted=/run/booted-system
    current=/nix/var/nix/profiles/system

    if [ ! -e "$booted" ] || [ ! -e "$current" ]; then
      echo "Cannot determine the booted and current NixOS system generations." >&2
      exit 1
    fi

    path_exists() {
      [ -e "$1" ] || [ -L "$1" ]
    }

    describe_artifact() {
      path="$1"

      if ! path_exists "$path"; then
        printf '<missing>'
        return
      fi

      resolved="$(readlink -f "$path")"
      leaf="$(basename "$resolved")"

      case "$leaf" in
        bzImage|initrd)
          basename "$(dirname "$resolved")"
          ;;
        *)
          basename "$resolved"
          ;;
      esac
    }

    same_artifact() {
      old="$1"
      new="$2"

      if [ -L "$old" ] || [ -L "$new" ]; then
        [ "$(readlink -f "$old")" = "$(readlink -f "$new")" ]
      elif [ -f "$old" ] && [ -f "$new" ]; then
        cmp -s "$old" "$new"
      else
        [ "$(readlink -f "$old")" = "$(readlink -f "$new")" ]
      fi
    }

    rebootRequired=0
    reasons=""

    check_artifact() {
      name="$1"
      label="$2"
      old="$booted/$name"
      new="$current/$name"

      oldExists=0
      newExists=0
      path_exists "$old" && oldExists=1
      path_exists "$new" && newExists=1

      if [ "$oldExists" -eq 0 ] && [ "$newExists" -eq 0 ]; then
        return
      fi

      if [ "$oldExists" -eq 1 ] && [ "$newExists" -eq 1 ] && same_artifact "$old" "$new"; then
        return
      fi

      rebootRequired=1
      oldDescription="$(describe_artifact "$old")"
      newDescription="$(describe_artifact "$new")"
      reasons="''${reasons}''${label}: ''${oldDescription} -> ''${newDescription}"$'\n'
    }

    # Compare boot-critical artifacts by their actual Nix store identity rather
    # than assuming that kernel modules live inside the kernel output. This also
    # supports split-output kernels such as the Apple T2 kernel.
    check_artifact kernel "Kernel"
    check_artifact initrd "Initrd"
    check_artifact kernel-modules "Kernel modules"
    check_artifact systemd "Systemd"

    if [ "$rebootRequired" -eq 0 ]; then
      exit 0
    fi

    if [ "$dryRun" -eq 1 ]; then
      printf '%s' "$reasons"
    else
      printf '%s' "$reasons" > /var/run/reboot-required
    fi

    exit 2
  '';

  meta = {
    description = "Determine whether boot-critical NixOS system artifacts changed";
    license = lib.licenses.mit;
    mainProgram = "nixos-needsreboot";
    platforms = lib.platforms.linux;
  };
}
