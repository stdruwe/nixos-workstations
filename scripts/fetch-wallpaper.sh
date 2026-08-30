#!/usr/bin/env bash

set -Eeuo pipefail

KDE_STORE_CONTENT_ID="1189184"
KDE_STORE_PAGE="https://store.kde.org/p/${KDE_STORE_CONTENT_ID}"
OCS_API_URL="https://api.kde-look.org/ocs/v1/content/data/${KDE_STORE_CONTENT_ID}"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
TARGET_DIR="${1:-$REPO_DIR/assets/local}"

for command in curl python3 mktemp mkdir mv rm; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

if [[ -s "$TARGET_DIR/wallpaper.png" || -s "$TARGET_DIR/wallpaper.jpg" ]]; then
  echo "Shared wallpaper is already present under $TARGET_DIR."
  exit 0
fi

WORKDIR="$(mktemp -d /tmp/nixos-wallpaper.XXXXXX)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

METADATA="$WORKDIR/metadata.xml"
PAYLOAD="$WORKDIR/wallpaper.download"

mkdir -p "$TARGET_DIR"

echo "Resolving shared wallpaper from KDE Store content $KDE_STORE_CONTENT_ID..."
curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --connect-timeout 10 \
  --max-time 60 \
  --proto '=https' \
  --proto-redir '=https' \
  --header 'OCS-APIRequest: true' \
  --output "$METADATA" \
  "$OCS_API_URL"

DOWNLOAD_URL="$(python3 - "$METADATA" <<'PY'
from html import unescape
from pathlib import Path
from xml.etree import ElementTree as ET
import sys

path = Path(sys.argv[1])
try:
    root = ET.parse(path).getroot()
except Exception as exc:
    raise SystemExit(f"Could not parse KDE Store OCS metadata: {exc}")

for element in root.iter():
    tag = element.tag.rsplit("}", 1)[-1]
    if tag == "downloadlink1" and element.text and element.text.strip():
        url = unescape(element.text.strip())
        if not url.startswith("https://"):
            raise SystemExit("KDE Store returned a non-HTTPS download URL")
        print(url)
        raise SystemExit(0)

raise SystemExit("KDE Store metadata does not contain downloadlink1")
PY
)"

echo "Downloading shared wallpaper..."
curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --connect-timeout 10 \
  --max-time 180 \
  --proto '=https' \
  --proto-redir '=https' \
  --output "$PAYLOAD" \
  "$DOWNLOAD_URL"

IMAGE_TYPE="$(python3 - "$PAYLOAD" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
data = path.read_bytes()
if len(data) < 100_000:
    raise SystemExit("Downloaded wallpaper is unexpectedly small")
if data.startswith(b"\x89PNG\r\n\x1a\n"):
    print("png")
elif data.startswith(b"\xff\xd8\xff"):
    print("jpg")
else:
    raise SystemExit("Downloaded wallpaper is neither PNG nor JPEG")
PY
)"

TARGET="$TARGET_DIR/wallpaper.$IMAGE_TYPE"
rm -f "$TARGET_DIR/wallpaper.png" "$TARGET_DIR/wallpaper.jpg"
mv "$PAYLOAD" "$TARGET"
chmod 0644 "$TARGET"

echo "Shared wallpaper downloaded successfully:"
echo "  Source: $KDE_STORE_PAGE"
echo "  File:   $TARGET"
