#!/usr/bin/env bash

set -Eeuo pipefail

PRESET_NAME="Dolby-Dynamic-Balanced.json"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
DEST_DIR="$REPO_DIR/audio/easyeffects/local/override"
DEST="$DEST_DIR/$PRESET_NAME"

for command in getent install cmp mkdir; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

if (( EUID != 0 )); then
  echo "Run this helper with sudo so it can update the machine-local NixOS data." >&2
  exit 1
fi

SOURCE_USER="${SOURCE_USER:-${SUDO_USER:-}}"
if [[ -z "$SOURCE_USER" || "$SOURCE_USER" == "root" ]]; then
  echo "Could not determine the desktop user. Re-run with SOURCE_USER=<user>." >&2
  exit 1
fi

SOURCE_HOME="$(getent passwd "$SOURCE_USER" | cut -d: -f6)"
if [[ -z "$SOURCE_HOME" ]]; then
  echo "Could not determine the home directory for $SOURCE_USER." >&2
  exit 1
fi

SOURCE="${SOURCE_PRESET:-$SOURCE_HOME/.local/share/easyeffects/output/$PRESET_NAME}"

if [[ ! -f "$SOURCE" ]]; then
  echo "EasyEffects preset not found: $SOURCE" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]] && cmp -s "$SOURCE" "$DEST"; then
  echo "Machine-local default preset is already identical to the EasyEffects copy."
  exit 0
fi

install -m 0644 "$SOURCE" "$DEST"

echo "Updated machine-local EasyEffects default preset:"
echo "  $DEST"
echo
echo "The override is under audio/easyeffects/local/ and is ignored by Git."
