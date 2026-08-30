#!/usr/bin/env bash

set -Eeuo pipefail

APPLE_EFI="${APPLE_EFI:-/dev/nvme0n1p1}"
EFI_SYSTEM_PARTITION_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
EFIRES_REL="assets/appleLogo.efires"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
EXTRACTOR="$SCRIPT_DIR/extract-apple-logo-efires.py"
DEST="$REPO_DIR/assets/local/apple-logo-2x.png"
MOUNT_DIR=""

cleanup() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    if mountpoint -q "$MOUNT_DIR"; then
      umount "$MOUNT_DIR" || true
    fi
    rmdir "$MOUNT_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

[[ "$EUID" -eq 0 ]] || {
  echo "Run as root: sudo $0" >&2
  exit 1
}

for command in lsblk mount mountpoint umount mktemp mkdir python3 tr; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

[[ -b "$APPLE_EFI" ]] || {
  echo "Apple EFI is missing: $APPLE_EFI" >&2
  exit 1
}

PARTTYPE="$(lsblk -dnro PARTTYPE "$APPLE_EFI" 2>/dev/null | tr '[:upper:]' '[:lower:]')"
[[ "$PARTTYPE" == "$EFI_SYSTEM_PARTITION_GUID" ]] || {
  echo "The specified Apple EFI is not an EFI System Partition: ${PARTTYPE:-<empty>}" >&2
  exit 1
}

[[ -f "$EXTRACTOR" ]] || {
  echo "EFIRES extractor is missing: $EXTRACTOR" >&2
  exit 1
}

MOUNT_DIR="$(mktemp -d /tmp/apple-efi.XXXXXX)"
mount -o ro,nosuid,nodev,noexec "$APPLE_EFI" "$MOUNT_DIR"

SOURCE="$MOUNT_DIR/$EFIRES_REL"
if [[ ! -f "$SOURCE" ]]; then
  echo "Optional Apple boot asset is missing from the EFI: /$EFIRES_REL"
  echo "Plymouth will be built without the Apple logo."
  exit 0
fi

mkdir -p "$(dirname -- "$DEST")"
python3 "$EXTRACTOR" "$SOURCE" "$DEST"
chmod 0644 "$DEST"

echo "Local Plymouth logo updated: $DEST"
