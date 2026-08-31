#!/usr/bin/env bash

set -Eeuo pipefail

umask 077

NIXOS_DIR="/etc/nixos"
SOURCE_DIR="${NIXOS_DIR}/local"
REQUIRED_FILES=(
  profile.nix
  identity.json
  deployment.json
)

die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF_USAGE
Usage:
  sudo $0 /path/to/external-backup-directory

Example:
  sudo $0 /run/media/\$SUDO_USER/NIXOS-BACKUP

Creates:
  nixos-local-<hostname>-<timestamp>.tar.zst
  nixos-local-<hostname>-<timestamp>.tar.zst.sha256
  nixos-local-<hostname>-<timestamp>.manifest.txt

Only /etc/nixos/local is backed up. The public Git checkout, generated assets,
release locks and machine-local update caches are intentionally excluded.
EOF_USAGE
}

[[ "$EUID" -eq 0 ]] || die "This script must be run as root."

[[ $# -eq 1 ]] || {
  usage
  exit 2
}

DEST_DIR="$1"

for command in tar zstd sha256sum findmnt realpath hostname date stat mkdir basename sync tr; do
  command -v "$command" >/dev/null || die "Required program is missing: $command"
done

[[ -d "$SOURCE_DIR" ]] || die "Local recovery state is missing: $SOURCE_DIR"

for file in "${REQUIRED_FILES[@]}"; do
  [[ -f "$SOURCE_DIR/$file" ]] || die "Required recovery file is missing: $SOURCE_DIR/$file"
done

mkdir -p "$DEST_DIR"
[[ -w "$DEST_DIR" ]] || die "Backup destination is not writable: $DEST_DIR"

SOURCE_REAL="$(realpath -m "$SOURCE_DIR")"
DEST_REAL="$(realpath -m "$DEST_DIR")"

case "$DEST_REAL/" in
  "$SOURCE_REAL/"*)
    die "The backup destination must not be inside $SOURCE_DIR."
    ;;
esac

SOURCE_FS="$(findmnt -n -o SOURCE -T "$SOURCE_DIR")"
DEST_FS="$(findmnt -n -o SOURCE -T "$DEST_DIR")"

if [[ "$SOURCE_FS" == "$DEST_FS" ]]; then
  die "Source and backup destination are on the same filesystem. Use external media for reinstallation backups."
fi

HOST="$(hostname -s | tr -c 'A-Za-z0-9._-' '_')"
STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
BASE="nixos-local-${HOST}-${STAMP}"
ARCHIVE="${DEST_DIR}/${BASE}.tar.zst"
CHECKSUM="${ARCHIVE}.sha256"
MANIFEST="${DEST_DIR}/${BASE}.manifest.txt"

echo "============================================================"
echo " Back up NixOS local recovery state"
echo "============================================================"
echo
echo "Source:      $SOURCE_REAL"
echo "Destination: $DEST_REAL"
echo

{
  echo "NixOS local recovery-state backup"
  echo "Time: $(date --iso-8601=seconds)"
  echo "Hostname: $(hostname)"
  echo "Source: $SOURCE_REAL"
  echo "Source filesystem: $SOURCE_FS"
  echo "Destination filesystem: $DEST_FS"
  echo
  echo "Files:"
  for file in "${REQUIRED_FILES[@]}"; do
    stat -c '%a %U:%G %n' "$SOURCE_DIR/$file"
  done
  echo
  echo "SHA-256 of recovery files:"
  sha256sum "${REQUIRED_FILES[@]/#/$SOURCE_DIR/}"
} > "$MANIFEST"

echo "Creating archive..."
tar \
  --zstd \
  --acls \
  --xattrs \
  --numeric-owner \
  -C "$NIXOS_DIR" \
  -cpf "$ARCHIVE" \
  local

echo "Creating SHA-256 checksum..."
(
  cd "$DEST_DIR"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

echo "Verifying checksum..."
(
  cd "$DEST_DIR"
  sha256sum -c "$(basename "$CHECKSUM")"
)

echo "Verifying archive structure..."
tar --zstd -tf "$ARCHIVE" >/dev/null

sync

echo
echo "============================================================"
echo " Backup successful"
echo "============================================================"
echo "Archive:  $ARCHIVE"
echo "SHA-256:  $CHECKSUM"
echo "Manifest: $MANIFEST"
