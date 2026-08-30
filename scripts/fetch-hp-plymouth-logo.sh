#!/usr/bin/env bash

set -Eeuo pipefail

SOURCE_URL="https://static.cdnlogo.com/logos/h/4/hewlett-packard.svg"
EXPECTED_SHA256="7c6db26bddfee7258ee2afe33cf60ef32639f9d276c57110e20dd87e57f9b0a9"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
DEST="$REPO_DIR/assets/local/hp-logo.svg"
TMP=""

cleanup() {
  [[ -n "$TMP" ]] && rm -f "$TMP"
}
trap cleanup EXIT

for command in curl sha256sum awk grep mkdir install mktemp; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

if [[ -f "$DEST" ]]; then
  actual="$(sha256sum "$DEST" | awk '{print $1}')"
  if [[ "$actual" == "$EXPECTED_SHA256" ]]; then
    echo "Local HP Plymouth logo is already current: $DEST"
    exit 0
  fi
fi

TMP="$(mktemp /tmp/hp-plymouth-logo.XXXXXX.svg)"

if ! curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --connect-timeout 10 \
  --max-time 60 \
  --output "$TMP" \
  "$SOURCE_URL"
then
  echo "HP Plymouth logo could not be downloaded." >&2
  echo "Plymouth remains functional without the HP logo." >&2
  exit 0
fi

actual="$(sha256sum "$TMP" | awk '{print $1}')"
if [[ "$actual" != "$EXPECTED_SHA256" ]]; then
  echo "Downloaded HP logo has an unexpected SHA-256 checksum." >&2
  echo "Expected: $EXPECTED_SHA256" >&2
  echo "Found:    $actual" >&2
  echo "The file will not be installed for safety reasons." >&2
  exit 1
fi

grep -q '<svg' "$TMP" || {
  echo "Downloaded file is not the expected SVG." >&2
  exit 1
}

mkdir -p "$(dirname -- "$DEST")"
install -m 0644 "$TMP" "$DEST"

echo "Local HP Plymouth logo updated: $DEST"
