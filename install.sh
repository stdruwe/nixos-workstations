#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat <<'USAGE'
Usage:
  sudo ./install.sh thinkpad-x1-carbon-gen13 [target-disk]
  sudo ./install.sh hp-z2-tower-g9 [target-disk]
  sudo ./install.sh apple-macbook-air-8-1 [--layout-check]

Profiles:
  thinkpad-x1-carbon-gen13   Lenovo ThinkPad X1 Carbon Gen 13
  hp-z2-tower-g9             HP Z2 Tower G9
  apple-macbook-air-8-1      Apple MacBookAir8,1 (2018, T2)

ThinkPad and HP select the target disk interactively if none is supplied.
On the Mac, --layout-check performs only the read-only layout validation.
USAGE
}

[[ "$EUID" -eq 0 ]] || {
  echo "Run as root: sudo ./install.sh <hardware-profile> [profile-option]" >&2
  exit 1
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    usage >&2
    exit 2
    ;;
esac

PROFILE="$1"
shift

# In the combined release package, the NixOS checkout lives under ./nixos and
# the matching Home Manager bundle sits next to it. In the normal repository,
# the dispatcher lives directly beside the three hardware-specific
# implementations; there the existing HOME_MANAGER_BUNDLE-/tmp workflow
# remains available.
if [[ -d "$SCRIPT_DIR/nixos" ]]; then
  NIXOS_DIR="$SCRIPT_DIR/nixos"
  PACKAGE_HOME_MANAGER_BUNDLE="$SCRIPT_DIR/home-manager.bundle"

  [[ -f "$PACKAGE_HOME_MANAGER_BUNDLE" ]] || {
    echo "Home Manager bundle is missing from the installation package: $PACKAGE_HOME_MANAGER_BUNDLE" >&2
    exit 1
  }

  if [[ -z "${HOME_MANAGER_BUNDLE:-}" ]]; then
    HOME_MANAGER_BUNDLE="$PACKAGE_HOME_MANAGER_BUNDLE"
    export HOME_MANAGER_BUNDLE
  fi
else
  NIXOS_DIR="$SCRIPT_DIR"
fi

case "$PROFILE" in
  thinkpad-x1-carbon-gen13)
    INSTALLER="$NIXOS_DIR/install-thinkpad-x1-carbon-gen13.sh"
    ;;
  hp-z2-tower-g9)
    INSTALLER="$NIXOS_DIR/install-hp-z2-tower-g9.sh"
    ;;
  apple-macbook-air-8-1)
    INSTALLER="$NIXOS_DIR/install-apple-macbook-air-8-1.sh"
    ;;
  *)
    echo "Unknown hardware profile: $PROFILE" >&2
    usage >&2
    exit 2
    ;;
esac

[[ -x "$INSTALLER" ]] || {
  echo "NixOS installer is missing or not executable: $INSTALLER" >&2
  exit 1
}

exec "$INSTALLER" "$@"
