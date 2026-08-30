#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_DIR="/etc/nixos"
TMP_BUNDLE_DIR=""

die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "${TMP_BUNDLE_DIR:-}" && -d "$TMP_BUNDLE_DIR" ]]; then
    rm -rf -- "$TMP_BUNDLE_DIR"
  fi
}

trap cleanup EXIT

usage() {
  cat <<EOF_USAGE
Usage:
  sudo $0 /path/to/external-backup-directory

Example:
  sudo $0 /run/media/\$SUDO_USER/NIXOS-BACKUP

Creates:
  nixos-<hostname>-<timestamp>.tar.zst
  nixos-<hostname>-<timestamp>.tar.zst.sha256
  nixos-<hostname>-<timestamp>.bundle
  nixos-<hostname>-<timestamp>.manifest.txt
EOF_USAGE
}

[[ "$EUID" -eq 0 ]] ||
  die "This script must be run as root."

[[ $# -eq 1 ]] || {
  usage
  exit 2
}

DEST_DIR="$1"

for command in \
  tar \
  zstd \
  sha256sum \
  git \
  runuser \
  stat \
  id \
  findmnt \
  realpath \
  hostname \
  date \
  du \
  find \
  chown \
  sort \
  tr \
  mkdir \
  mktemp \
  mv \
  rmdir \
  rm \
  basename \
  dirname \
  sync
do
  command -v "$command" >/dev/null ||
    die "Required program is missing: $command"
done

[[ -d "$SOURCE_DIR" ]] ||
  die "Source directory is missing: $SOURCE_DIR"

# ---------------------------------------------------------------------------
# Always run Git as the normal user
# ---------------------------------------------------------------------------
#
# The backup itself requires root privileges.
#
# Git, however, must not write to /etc/nixos/.git as root, because that would
# create root-owned objects, index files or other Git metadata and could break
# later Git operations by the normal user.

if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
  GIT_USER="$SUDO_USER"
elif [[ -d "$SOURCE_DIR/.git" ]]; then
  GIT_USER="$(stat -c '%U' "$SOURCE_DIR/.git")"
else
  die "Git user cannot be determined. Run this script with sudo as a normal user."
fi

id "$GIT_USER" >/dev/null 2>&1 ||
  die "Git user does not exist: $GIT_USER"

[[ "$GIT_USER" != "root" ]] ||
  die "Git must not run as root for this backup."

GIT_GROUP="$(id -gn "$GIT_USER")"

git_repo() {
  runuser -u "$GIT_USER" -- \
    git \
      -c "safe.directory=$SOURCE_DIR" \
      -C "$SOURCE_DIR" \
      "$@"
}

# ---------------------------------------------------------------------------
# Validate backup destination
# ---------------------------------------------------------------------------

mkdir -p "$DEST_DIR"

SOURCE_REAL="$(realpath -m "$SOURCE_DIR")"
DEST_REAL="$(realpath -m "$DEST_DIR")"

case "$DEST_REAL/" in
  "$SOURCE_REAL/"*)
    die "The backup destination must not be inside $SOURCE_DIR."
    ;;
esac

SOURCE_FS="$(findmnt -n -o SOURCE -T "$SOURCE_DIR")"
DEST_FS="$(findmnt -n -o SOURCE -T "$DEST_DIR")"

echo "Source:"
echo "  $SOURCE_DIR"
echo "  Filesystem: $SOURCE_FS"
echo
echo "Destination:"
echo "  $DEST_REAL"
echo "  Filesystem: $DEST_FS"
echo

if [[ "$SOURCE_FS" == "$DEST_FS" ]]; then
  die "Source and backup destination are on the same filesystem. Use external media for reinstallation backups."
fi

[[ -w "$DEST_DIR" ]] ||
  die "Backup destination is not writable: $DEST_DIR"

HOST="$(printf '%s' "$(hostname -s)" | tr -c 'A-Za-z0-9._-' '_')"
STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
BASE="nixos-${HOST}-${STAMP}"

ARCHIVE="${DEST_DIR}/${BASE}.tar.zst"
CHECKSUM="${ARCHIVE}.sha256"
BUNDLE="${DEST_DIR}/${BASE}.bundle"
MANIFEST="${DEST_DIR}/${BASE}.manifest.txt"

echo "============================================================"
echo " Back up NixOS configuration"
echo "============================================================"
echo

# ---------------------------------------------------------------------------
# Git snapshot
# ---------------------------------------------------------------------------

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  echo "Initializing local Git repository..."

  # /etc/nixos itself belongs to root. Therefore .git is initially created by
  # root and then transferred completely to the normal Git user.
  git -C "$SOURCE_DIR" init
  chown -R "$GIT_USER:$GIT_GROUP" "$SOURCE_DIR/.git"
fi

# Safety check: no file or directory below .git may belong to another user.
FOREIGN_GIT_ENTRY="$(
  find "$SOURCE_DIR/.git" \
    ! -user "$GIT_USER" \
    -print \
    -quit
)"

if [[ -n "$FOREIGN_GIT_ENTRY" ]]; then
  die "Entry with incorrect ownership found under .git: $FOREIGN_GIT_ENTRY"
fi

# Repository-local fallback identity when no Git identity is configured.
if ! git_repo config --get user.name >/dev/null; then
  git_repo config user.name "NixOS Config Backup"
fi

if ! git_repo config --get user.email >/dev/null; then
  git_repo config user.email "nixos-backup@localhost"
fi

echo "Git user:"
echo "  $GIT_USER"
echo

echo "Capturing current state in Git..."
git_repo add -A

if ! git_repo diff --cached --quiet; then
  git_repo commit -m "Backup ${STAMP}"
else
  echo "No changes since the last Git commit."
fi

# A bundle requires at least one commit.
git_repo rev-parse --verify HEAD >/dev/null ||
  die "Git repository contains no commit."

# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

echo
echo "Creating manifest..."

{
  echo "NixOS configuration backup"
  echo "Time: $(date --iso-8601=seconds)"
  echo "Hostname: $(hostname)"
  echo "Source: $SOURCE_REAL"
  echo "Destination filesystem: $DEST_FS"
  echo
  echo "Git HEAD:"
  git_repo rev-parse HEAD
  echo
  echo "Git status:"
  git_repo status --short
  echo
  echo "Size:"
  du -sh "$SOURCE_DIR"
  echo
  echo "File list:"
  find "$SOURCE_DIR" -xdev -printf '%P\n' | sort
} > "$MANIFEST"

# ---------------------------------------------------------------------------
# Complete archive
# ---------------------------------------------------------------------------

echo
echo "Creating complete tar.zst archive..."

tar \
  --zstd \
  --acls \
  --xattrs \
  --numeric-owner \
  -C "$(dirname "$SOURCE_DIR")" \
  -cpf "$ARCHIVE" \
  "$(basename "$SOURCE_DIR")"

# ---------------------------------------------------------------------------
# Checksum and archive test
# ---------------------------------------------------------------------------

echo "Creating SHA-256 checksum..."

(
  cd "$DEST_DIR"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

echo "Verifying SHA-256..."

(
  cd "$DEST_DIR"
  sha256sum -c "$(basename "$CHECKSUM")"
)

echo "Verifying archive structure..."

tar --zstd -tf "$ARCHIVE" >/dev/null

# ---------------------------------------------------------------------------
# Git bundle
# ---------------------------------------------------------------------------
#
# Git must run as the normal user here as well.
#
# The external destination directory may belong to root. Therefore the bundle
# is first created in a temporary directory writable by GIT_USER under /tmp and
# then moved into the backup destination by root.

echo "Creating Git bundle..."

TMP_BUNDLE_DIR="$(
  runuser -u "$GIT_USER" -- \
    mktemp -d "/tmp/nixos-git-bundle.XXXXXX"
)"

TMP_BUNDLE="${TMP_BUNDLE_DIR}/${BASE}.bundle"

git_repo bundle create "$TMP_BUNDLE" --all

echo "Verifying Git bundle..."

git_repo bundle verify "$TMP_BUNDLE"

mv -- "$TMP_BUNDLE" "$BUNDLE"
rmdir -- "$TMP_BUNDLE_DIR"
TMP_BUNDLE_DIR=""

sync

echo
echo "============================================================"
echo " Backup successful"
echo "============================================================"
echo
echo "Archive:"
echo "  $ARCHIVE"
echo
echo "SHA-256:"
echo "  $CHECKSUM"
echo
echo "Git bundle:"
echo "  $BUNDLE"
echo
echo "Manifest:"
echo "  $MANIFEST"
echo
echo "All checks completed successfully."
