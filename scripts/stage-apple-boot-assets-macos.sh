#!/bin/zsh

set -e

PREBOOT_ROOT="/System/Volumes/Preboot"
EFI_DEVICE="disk0s1"
EFI_ASSET_REL="assets/appleLogo.efires"

fail() {
  print -u2 -- "ERROR: $*"
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "This script must run on macOS."
[[ -d "$PREBOOT_ROOT" ]] || fail "macOS Preboot volume is missing: $PREBOOT_ROOT"

print -- "Searching for the Apple EFI login resource in the APFS Preboot volume..."
APPLE_LOGO_EFIRES="$(
  sudo find "$PREBOOT_ROOT" \
    -type f \
    -path '*/usr/standalone/i386/EfiLoginUI/appleLogo.efires' \
    -print 2>/dev/null \
    | head -n 1
)"

[[ -n "$APPLE_LOGO_EFIRES" ]] || fail "appleLogo.efires was not found in the Preboot volume."
[[ -f "$APPLE_LOGO_EFIRES" ]] || fail "The discovered source file is not readable: $APPLE_LOGO_EFIRES"

print -- "Source: $APPLE_LOGO_EFIRES"

EFI_INFO="$(diskutil info "$EFI_DEVICE" 2>/dev/null)" \
  || fail "Apple EFI partition $EFI_DEVICE was not found."

if ! print -r -- "$EFI_INFO" | grep -Eq 'Partition Type:[[:space:]]+EFI|Content.*:[[:space:]]+EFI'; then
  fail "$EFI_DEVICE was not recognized as an EFI System Partition."
fi

print -- "Mounting Apple EFI $EFI_DEVICE..."
sudo diskutil mount "$EFI_DEVICE" >/dev/null

EFI_MOUNT="$(
  diskutil info "$EFI_DEVICE" \
    | awk -F': *' '/Mount Point/ { print $2; exit }'
)"

[[ -n "$EFI_MOUNT" && -d "$EFI_MOUNT" ]] || fail "Could not determine the Apple EFI mount point."

cleanup() {
  sudo diskutil unmount "$EFI_DEVICE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

DEST="$EFI_MOUNT/$EFI_ASSET_REL"
print -- "Copying to: $DEST"
sudo mkdir -p "${DEST:h}"
sudo cp -p "$APPLE_LOGO_EFIRES" "$DEST"

sudo cmp -s "$APPLE_LOGO_EFIRES" "$DEST" \
  || fail "Copied EFIRES file does not match the source."

SIZE="$(sudo stat -f '%z' "$DEST")"
print -- "Verified: $SIZE bytes"
print -- "Apple boot asset is stored persistently on the Apple EFI at /$EFI_ASSET_REL."
