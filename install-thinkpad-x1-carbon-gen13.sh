#!/usr/bin/env bash

set -Eeuo pipefail

# NixOS reinstallation for Lenovo ThinkPad X1 Carbon Gen 13.
# The target disk is selected interactively or passed as the optional first argument.

PROFILE="thinkpad-x1-carbon-gen13"
DEFAULT_HOST_NAME="$PROFILE"
INSTALL_CONFIG_REL="hosts/${PROFILE}/installation.nix"
NORMAL_CONFIG_REL="hosts/${PROFILE}/default.nix"
DISKO_CONFIG_REL="hosts/${PROFILE}/disko.nix"
LUKS_PASSWORD_FILE="/tmp/luks-password"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/install-common.sh
source "$SCRIPT_DIR/scripts/install-common.sh"
# shellcheck source=scripts/install-disk.sh
source "$SCRIPT_DIR/scripts/install-disk.sh"

WORKDIR=""
cleanup() {
  rm -f "$LUKS_PASSWORD_FILE"
}
trap cleanup EXIT

[[ "$#" -le 1 ]] || install_die "Usage: sudo ./install-thinkpad-x1-carbon-gen13.sh [target-disk]"
[[ "$EUID" -eq 0 ]] || install_die "Run as root: sudo ./install-thinkpad-x1-carbon-gen13.sh [target-disk]"
[[ -d /sys/firmware/efi/efivars ]] || install_die "The installation medium was not booted in UEFI mode."

for command in \
  nix nix-build nix-instantiate nixos-install nixos-enter lsblk mountpoint readlink \
  blkid grep od tr swapon swapoff umount sync cp mkdir mktemp
do
  install_need_command "$command"
done

EFI_GLOBAL_GUID="8be4df61-93ca-11d2-aa0d-00e098032b8c"
SETUP_MODE_VAR="/sys/firmware/efi/efivars/SetupMode-${EFI_GLOBAL_GUID}"
SECURE_BOOT_VAR="/sys/firmware/efi/efivars/SecureBoot-${EFI_GLOBAL_GUID}"

read_efi_boolean() {
  local variable_file="$1"
  [[ -r "$variable_file" ]] || install_die "UEFI variable cannot be read: $variable_file"
  od -An -t u1 -j 4 -N 1 "$variable_file" | tr -d '[:space:]'
}

SETUP_MODE="$(read_efi_boolean "$SETUP_MODE_VAR")"
SECURE_BOOT="$(read_efi_boolean "$SECURE_BOOT_VAR")"
[[ "$SETUP_MODE" == "1" ]] || install_die "UEFI Secure Boot is not in Setup Mode."
[[ "$SECURE_BOOT" == "0" ]] || install_die "Secure Boot must be disabled during installation."

echo "UEFI Secure Boot Setup Mode: active"
echo "UEFI Secure Boot: disabled"

for file in \
  configuration.nix scripts/install-common.sh scripts/install-disk.sh \
  scripts/fetch-wallpaper.sh scripts/generate-thinkpad-easyeffects-local.sh \
  "$INSTALL_CONFIG_REL" "$NORMAL_CONFIG_REL" "$DISKO_CONFIG_REL" \
  "hosts/${PROFILE}/base.nix" \
  "hosts/${PROFILE}/hardware-installation.nix" \
  "hosts/${PROFILE}/hardware.nix" \
  "hosts/${PROFILE}/networking.nix" \
  "hosts/${PROFILE}/desktop.nix" \
  "hosts/${PROFILE}/services.nix" \
  "hosts/${PROFILE}/audio.nix" \
  modules/common/default.nix modules/common/identity.nix modules/common/base.nix \
  modules/common/programs.nix modules/common/fastfetch.nix modules/common/users.nix \
  modules/common/packages.nix modules/common/fonts.nix modules/common/spotify.nix \
  modules/features/kate.nix modules/features/keyboard-backlight.nix modules/features/usb-pd-plasmoid.nix \
  topgrade.nix secureboot.nix lon.nix lon.lock pkgs/powertop-2.16.nix \
  post-install-security.sh
do
  [[ -f "$SCRIPT_DIR/$file" ]] || install_die "Required file is missing: $SCRIPT_DIR/$file"
done

[[ -x "$SCRIPT_DIR/post-install-security.sh" ]] || install_die "post-install-security.sh is not executable."

export NIXOS_INSTALL_LON_LOCK="$SCRIPT_DIR/lon.lock"
DISKO_REF="$(
  nix --extra-experimental-features "nix-command" eval --impure --raw --expr \
    'let
      lockPath = builtins.toPath (builtins.getEnv "NIXOS_INSTALL_LON_LOCK");
      lock = builtins.fromJSON (builtins.readFile lockPath);
    in
    lock.sources.disko.revision'
)"
unset NIXOS_INSTALL_LON_LOCK
[[ -n "$DISKO_REF" ]] || install_die "Disko revision could not be read from lon.lock."

AUTOLOAD_DIR="$SCRIPT_DIR/audio/easyeffects/autoload/output"
[[ -d "$AUTOLOAD_DIR" ]] || install_die "EasyEffects autoload directory is missing: $AUTOLOAD_DIR"
compgen -G "$AUTOLOAD_DIR/*.json" >/dev/null || install_die "No EasyEffects autoload rule was found."

install_select_target_disk "${1:-}"

echo
echo "Selected target disk:"
lsblk -d -o NAME,SIZE,MODEL,TRAN "$REAL_DISK"

# Local identity is set before any destructive action.
echo
echo "Local system identity:"
install_prompt_identity "$DEFAULT_HOST_NAME"
echo "  Hardware profile: $PROFILE"
echo "  Hostname:         $INSTALL_HOST_NAME"
echo "  User:             $INSTALL_USER"
echo "  Display name:     $INSTALL_FULL_NAME"

WORKDIR="$(mktemp -d /tmp/nixos-thinkpad-install.XXXXXX)"
echo "Configuration working copy: $WORKDIR"
cp -a "$SCRIPT_DIR"/. "$WORKDIR"/
rm -f "$WORKDIR/apple-sf-fonts.tar.zst" "$WORKDIR/apple-sf-fonts.tar.zst.sha256"

install_write_local_identity "$WORKDIR" "$INSTALL_CONFIG_REL"

echo
echo "Preparing machine-local ThinkPad EasyEffects tuning..."
REPO_DIR="$WORKDIR" \
  bash "$WORKDIR/scripts/generate-thinkpad-easyeffects-local.sh"

echo
echo "Checking NixOS target configuration with local identity..."
nix-instantiate '<nixpkgs/nixos>' -A system \
  -I "nixos-config=$WORKDIR/configuration.nix" >/dev/null

echo "Checking Disko ${DISKO_REF} against $REAL_DISK..."
nix --extra-experimental-features "nix-command flakes" \
  run "github:nix-community/disko/${DISKO_REF}" -- \
  --mode destroy,format,mount \
  --dry-run \
  --argstr device "$REAL_DISK" \
  "$WORKDIR/$DISKO_CONFIG_REL" >/dev/null

echo "Preflight succeeded. No disk has been modified yet."

echo
echo "WARNING: $REAL_DISK will be erased completely."
CONFIRM_TEXT="ERASE $REAL_DISK"
read -r -p "Enter exactly '${CONFIRM_TEXT}' to continue: " CONFIRM
[[ "$CONFIRM" == "$CONFIRM_TEXT" ]] || install_die "Aborted."

while true; do
  echo
  read -r -s -p "New LUKS recovery passphrase: " LUKS_PASSWORD_1
  echo
  read -r -s -p "Repeat passphrase: " LUKS_PASSWORD_2
  echo
  [[ -n "$LUKS_PASSWORD_1" ]] || { echo "The passphrase must not be empty."; continue; }
  [[ "$LUKS_PASSWORD_1" == "$LUKS_PASSWORD_2" ]] || { echo "The passphrases do not match."; continue; }
  break
done

umask 077
printf '%s' "$LUKS_PASSWORD_1" > "$LUKS_PASSWORD_FILE"
unset LUKS_PASSWORD_1 LUKS_PASSWORD_2
chmod 600 "$LUKS_PASSWORD_FILE"

if mountpoint -q /mnt; then
  umount -R /mnt
fi
swapoff -a || true

echo
echo "Partitioning and formatting the disk with Disko ${DISKO_REF}..."
nix --extra-experimental-features "nix-command flakes" \
  run "github:nix-community/disko/${DISKO_REF}" -- \
  --mode destroy,format,mount \
  --argstr device "$REAL_DISK" \
  --yes-wipe-all-disks \
  "$WORKDIR/$DISKO_CONFIG_REL"
rm -f "$LUKS_PASSWORD_FILE"

for mountpoint_path in /mnt /mnt/boot /mnt/home /mnt/nix /mnt/swap; do
  mountpoint -q "$mountpoint_path" || install_die "Expected mount point is missing: $mountpoint_path"
  echo "  OK: $mountpoint_path"
done

ROOT_PART="$(install_partition_by_label "$REAL_DISK" "root-x86-64")"
ROOT_PARTTYPE="$(lsblk -dnro PARTTYPE "$ROOT_PART" | tr '[:upper:]' '[:lower:]')"
EXPECTED_PARTTYPE="4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
[[ "$ROOT_PARTTYPE" == "$EXPECTED_PARTTYPE" ]] || install_die "Incorrect GPT type for the root partition: $ROOT_PARTTYPE"
ROOT_FSTYPE="$(blkid -s TYPE -o value "$ROOT_PART")"
[[ "$ROOT_FSTYPE" == "crypto_LUKS" ]] || install_die "Root partition is not LUKS-encrypted: $ROOT_FSTYPE"
[[ -f /mnt/swap/swapfile ]] || install_die "Btrfs swapfile was not created."

echo
echo "Disk layout:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTTYPE,PARTLABEL,MOUNTPOINTS "$REAL_DISK"

echo
echo "Copying NixOS configuration..."
mkdir -p /mnt/etc/nixos
cp -a "$WORKDIR"/. /mnt/etc/nixos/
rm -f /mnt/etc/nixos/host.nix /mnt/etc/nixos/hardware-configuration.nix

nixos-install \
  --root /mnt \
  --no-root-passwd \
  -I nixos-config=/mnt/etc/nixos/configuration.nix

# The user was created declaratively; set a fresh password known only locally.
install_set_fresh_password /mnt
install_prepare_repo_permissions /mnt

sync

echo
echo "============================================================"
echo " NixOS was installed successfully."
echo "============================================================"
echo "Hardware profile: $PROFILE"
echo "Hostname:         $INSTALL_HOST_NAME"
echo "User:             $INSTALL_USER"
echo
echo "No initial password change is required on the first boot."
echo "Then configure Secure Boot/TPM2:"
echo "  1. sudo /etc/nixos/post-install-security.sh prepare"
echo "  2. sudo /etc/nixos/post-install-security.sh enroll-secureboot"
echo "  3. reboot"
echo "  4. sudo /etc/nixos/post-install-security.sh status"
echo "  5. sudo /etc/nixos/post-install-security.sh enroll-tpm"
echo
echo "Remove the installation medium and reboot."
