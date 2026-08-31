#!/usr/bin/env bash

set -Eeuo pipefail

if [[ "$#" -ne 1 ]]; then
  echo "Usage: $0 /path/to/filebot-source.nix" >&2
  exit 2
fi

source_file="$1"
tmp_file="${source_file}.tmp.$$"

cleanup() {
  rm -f -- "$tmp_file"
}
trap cleanup EXIT

for command in curl grep sort tail sed tr mkdir dirname mv; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

mkdir -p "$(dirname -- "$source_file")"

echo "Checking current FileBot release..."

version="$(
  curl \
    -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    --retry 2 \
    --retry-delay 2 \
    --retry-all-errors \
    https://www.filebot.net/download.html \
    | grep -oE 'FileBot_[0-9]+\.[0-9]+\.[0-9]+_amd64\.deb' \
    | sort -Vu \
    | tail -n 1 \
    | sed -E 's/^FileBot_([0-9.]+)_amd64\.deb$/\1/'
)"

if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Could not determine the current stable FileBot version." >&2
  exit 1
fi

checksum_url="https://raw.githubusercontent.com/filebot/website/master/get.filebot.net/filebot/FileBot_${version}/FileBot_${version}_amd64.deb.sha256"
sha256="$(
  curl \
    -fsSL \
    --connect-timeout 10 \
    --max-time 60 \
    --retry 2 \
    --retry-delay 2 \
    --retry-all-errors \
    "$checksum_url" \
    | tr -d '[:space:]'
)"

if ! printf '%s\n' "$sha256" | grep -Eq '^[0-9a-fA-F]{64}$'; then
  echo "Invalid SHA-256 checksum returned for FileBot $version." >&2
  exit 1
fi

current_version=""
current_sha256=""
if [[ -f "$source_file" ]]; then
  current_version="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$source_file")"
  current_sha256="$(sed -n 's/^[[:space:]]*sha256 = "\([^"]*\)";/\1/p' "$source_file")"
fi

if [[ "$current_version" == "$version" && "$current_sha256" == "$sha256" ]]; then
  echo "FileBot $version is already current."
  exit 0
fi

printf '{\n  version = "%s";\n  sha256 = "%s";\n}\n' \
  "$version" "$sha256" > "$tmp_file"
mv -- "$tmp_file" "$source_file"

echo "Prepared FileBot update: ${current_version:-<none>} -> $version"
