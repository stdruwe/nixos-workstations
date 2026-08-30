#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_URL="https://upload.wikimedia.org/wikipedia/commons/0/09/ThinkPad_Logo.svg"
EXPECTED_SHA256="c4325e91bb8c48f7d20e7782f431acce49aa0fc380eaf31f1a20ecd3dbccb542"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
DEST="$REPO_DIR/assets/local/thinkpad-logo.svg"
TMP=""

cleanup() {
  [[ -n "$TMP" ]] && rm -f "$TMP"
}
trap cleanup EXIT

for command in curl sha256sum awk grep mkdir install mktemp wc; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

if [[ -f "$DEST" ]]; then
  actual="$(sha256sum "$DEST" | awk '{print $1}')"
  if [[ "$actual" == "$EXPECTED_SHA256" ]]; then
    echo "Local ThinkPad Plymouth logo is already current: $DEST"
    exit 0
  fi
fi

TMP="$(mktemp /tmp/thinkpad-plymouth-logo.XXXXXX.svg)"

if ! content_type="$(curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --connect-timeout 10 \
  --max-time 60 \
  --user-agent 'nixos-stefan-mobil ThinkPad Plymouth asset fetcher' \
  --output "$TMP" \
  --write-out '%{content_type}' \
  "$SOURCE_URL")"
then
  echo "ThinkPad Plymouth logo could not be downloaded." >&2
  echo "Plymouth remains functional without the ThinkPad logo." >&2
  exit 0
fi

case "$content_type" in
  image/svg+xml*) ;;
  *)
    echo "Unexpected MIME type for the ThinkPad logo: $content_type" >&2
    echo "The file will not be installed for safety reasons." >&2
    exit 1
    ;;
esac

size="$(wc -c < "$TMP")"
if (( size < 1000 || size > 10000 )); then
  echo "Downloaded ThinkPad logo has an unexpected file size: $size bytes." >&2
  echo "The file will not be installed for safety reasons." >&2
  exit 1
fi

grep -q '<svg' "$TMP" || {
  echo "Downloaded file is not the expected SVG." >&2
  exit 1
}

actual="$(sha256sum "$TMP" | awk '{print $1}')"
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
  echo "Downloaded ThinkPad logo has an unexpected SHA-256 checksum." >&2
  echo "Expected: $EXPECTED_SHA256" >&2
  echo "Found:    $actual" >&2
  echo "The file will not be installed for safety reasons." >&2
  exit 1
fi

mkdir -p "$(dirname -- "$DEST")"
install -m 0644 "$TMP" "$DEST"

echo "Local ThinkPad Plymouth logo updated: $DEST"
