#!/usr/bin/env bash

set -Eeuo pipefail

LENOVO_DRIVER_URL="https://download.lenovo.com/pccbbs/mobiles/n4ba127w.exe"
LENOVO_DRIVER_SHA256="70275ff0d2cdd079290a6848febaa415bb012cfe98dbca1502b58e088fbdb33b"
TUNING_XML_NAME="SOUNDWIRE_MAN_025D_FUNC_1318_SUBSYS_233917AA.xml"

CONVERTER_REPO="https://github.com/antoinecellerier/speaker-tuning-to-easyeffects.git"
CONVERTER_TAG="v2026.08"
CONVERTER_COMMIT="86e0cb9d9756fc5c95648dd305f385192e696ade"

EXPECTED_PRESETS=27
EXPECTED_IRS=27

if (( $# != 0 )); then
  echo "Usage: $0" >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="${REPO_DIR:-$(cd -- "$SCRIPT_DIR/.." && pwd -P)}"
LOCAL_DIR="$REPO_DIR/audio/easyeffects/local"
LOCAL_OUTPUT="$LOCAL_DIR/output"
LOCAL_IRS="$LOCAL_DIR/irs"

for command in curl sha256sum awk git find mktemp mkdir rm install sort nix-build; do
  command -v "$command" >/dev/null || {
    echo "Required program is missing: $command" >&2
    exit 1
  }
done

# Keep the generator reproducible and directly usable on an installed NixOS
# system. The pinned converter requires NumPy and SciPy; optional rich output is
# deliberately not required. innoextract and the Python environment come from
# the machine's configured nixpkgs instead of relying on ambient packages.
echo "Preparing EasyEffects generator dependencies from nixpkgs..."
INNOEXTRACT_STORE="$(nix-build '<nixpkgs>' -A innoextract --no-out-link)"
PYTHON_STORE="$(
  nix-build \
    --no-out-link \
    -E 'with import <nixpkgs> {}; python3.withPackages (ps: [ ps.numpy ps.scipy ])'
)"
INNOEXTRACT="$INNOEXTRACT_STORE/bin/innoextract"
PYTHON="$PYTHON_STORE/bin/python3"

[[ -x "$INNOEXTRACT" ]] || {
  echo "innoextract could not be provided by nixpkgs." >&2
  exit 1
}
[[ -x "$PYTHON" ]] || {
  echo "Python with NumPy/SciPy could not be provided by nixpkgs." >&2
  exit 1
}

WORKDIR="$(mktemp -d /tmp/thinkpad-easyeffects.XXXXXX)"
cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

DRIVER="$WORKDIR/n4ba127w.exe"
DRIVER_DIR="$WORKDIR/driver"
CONVERTER_DIR="$WORKDIR/converter"
GENERATED_OUTPUT="$WORKDIR/generated/output"
GENERATED_IRS="$WORKDIR/generated/irs"

mkdir -p "$DRIVER_DIR" "$CONVERTER_DIR" "$GENERATED_OUTPUT" "$GENERATED_IRS"

echo "Downloading Lenovo ThinkPad audio driver..."
curl \
  --fail \
  --location \
  --silent \
  --show-error \
  --retry 3 \
  --connect-timeout 10 \
  --max-time 300 \
  --output "$DRIVER" \
  "$LENOVO_DRIVER_URL"

actual_driver_sha256="$(sha256sum "$DRIVER" | awk '{print $1}')"
if [[ "$actual_driver_sha256" != "$LENOVO_DRIVER_SHA256" ]]; then
  echo "Lenovo driver SHA-256 mismatch." >&2
  echo "Expected: $LENOVO_DRIVER_SHA256" >&2
  echo "Found:    $actual_driver_sha256" >&2
  exit 1
fi

echo "Lenovo driver checksum verified."

echo "Extracting Dolby tuning XML from Lenovo package..."
"$INNOEXTRACT" \
  --silent \
  --include "$TUNING_XML_NAME" \
  --output-dir "$DRIVER_DIR" \
  "$DRIVER"

mapfile -d '' tuning_matches < <(
  find "$DRIVER_DIR" -type f -name "$TUNING_XML_NAME" -print0
)

if (( ${#tuning_matches[@]} != 1 )); then
  echo "Expected exactly one $TUNING_XML_NAME in the Lenovo package; found ${#tuning_matches[@]}." >&2
  exit 1
fi

TUNING_XML="${tuning_matches[0]}"
echo "Found tuning XML: $TUNING_XML_NAME"

echo "Fetching pinned speaker-tuning-to-easyeffects $CONVERTER_TAG..."
git -C "$CONVERTER_DIR" init --quiet
git -C "$CONVERTER_DIR" remote add origin "$CONVERTER_REPO"
git -C "$CONVERTER_DIR" fetch --quiet --depth 1 origin tag "$CONVERTER_TAG"
git -C "$CONVERTER_DIR" checkout --quiet --detach FETCH_HEAD

actual_converter_commit="$(git -C "$CONVERTER_DIR" rev-parse HEAD)"
if [[ "$actual_converter_commit" != "$CONVERTER_COMMIT" ]]; then
  echo "Converter commit mismatch." >&2
  echo "Expected: $CONVERTER_COMMIT" >&2
  echo "Found:    $actual_converter_commit" >&2
  exit 1
fi

actual_converter_version="$(git -C "$CONVERTER_DIR" describe --tags --always)"
if [[ "$actual_converter_version" != "$CONVERTER_TAG" ]]; then
  echo "Converter version mismatch." >&2
  echo "Expected: $CONVERTER_TAG" >&2
  echo "Found:    $actual_converter_version" >&2
  exit 1
fi

echo "Generating all ThinkPad Dolby profiles with $CONVERTER_TAG..."
# This wrapper may intentionally run as root because /etc/nixos and the local
# tuning cache are root-owned. The converter itself only writes to the explicit
# temporary output directories below, so allowing root here cannot create
# root-owned files in a desktop user's EasyEffects tree.
ALLOW_ROOT=1 "$PYTHON" "$CONVERTER_DIR/dolby_to_easyeffects.py" \
  "$TUNING_XML" \
  --all-profiles \
  --output-dir "$GENERATED_OUTPUT" \
  --irs-dir "$GENERATED_IRS" \
  --skip-ee-check

mapfile -d '' generated_presets < <(
  find "$GENERATED_OUTPUT" -maxdepth 1 -type f -name 'Dolby-*.json' -print0 | sort -z
)
mapfile -d '' generated_irs < <(
  find "$GENERATED_IRS" -maxdepth 1 -type f -name 'Dolby-*.irs' -print0 | sort -z
)

if (( ${#generated_presets[@]} != EXPECTED_PRESETS )); then
  echo "Unexpected generated preset count: ${#generated_presets[@]} (expected $EXPECTED_PRESETS)." >&2
  exit 1
fi

if (( ${#generated_irs[@]} != EXPECTED_IRS )); then
  echo "Unexpected generated IRS count: ${#generated_irs[@]} (expected $EXPECTED_IRS)." >&2
  exit 1
fi

if [[ ! -f "$GENERATED_OUTPUT/Dolby-Dynamic-Balanced.json" ]]; then
  echo "Missing generated Dolby-Dynamic-Balanced.json." >&2
  exit 1
fi

if [[ ! -f "$GENERATED_IRS/Dolby-Dynamic-Balanced.irs" ]]; then
  echo "Missing generated Dolby-Dynamic-Balanced.irs." >&2
  exit 1
fi

# Generation and validation succeeded. Replace only the local generated cache.
# Any user-adjusted default saved under local/override remains untouched.
mkdir -p "$LOCAL_OUTPUT" "$LOCAL_IRS"
rm -f "$LOCAL_OUTPUT"/Dolby-*.json "$LOCAL_IRS"/Dolby-*.irs

for generated in "${generated_presets[@]}"; do
  install -m 0644 "$generated" "$LOCAL_OUTPUT/${generated##*/}"
done
for generated in "${generated_irs[@]}"; do
  install -m 0644 "$generated" "$LOCAL_IRS/${generated##*/}"
done

echo "Local ThinkPad EasyEffects tuning refreshed successfully."
echo "  Generator: $CONVERTER_TAG ($CONVERTER_COMMIT)"
echo "  Presets:   $EXPECTED_PRESETS -> $LOCAL_OUTPUT"
echo "  IRS:       $EXPECTED_IRS -> $LOCAL_IRS"
