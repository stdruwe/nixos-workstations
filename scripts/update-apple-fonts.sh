#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
# shellcheck source=scripts/install-common.sh
source "$SCRIPT_DIR/install-common.sh"

if [[ "$EUID" -ne 0 ]]; then
  echo "Run as root: sudo /etc/nixos/scripts/update-apple-fonts.sh" >&2
  exit 1
fi

rm -f "$REPO_ROOT/apple-sf-fonts.tar.zst"
install_prepare_apple_fonts "$REPO_ROOT"

echo
echo "Apple fonts updated: SF Pro, SF Mono and New York."
echo "The new Fontconfig/Gecko selection becomes active with the next nixos-rebuild switch."
