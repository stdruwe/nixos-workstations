#!/usr/bin/env bash

set -Eeuo pipefail

# NixOS installation for Apple MacBookAir8,1 (2018, T2) in dual boot with macOS.
#
# Safety model:
# - Apple EFI (p1) and macOS/APFS (p2) are structurally verified and captured
#   as an immutable runtime baseline.
# - p1/p2 are never formatted, deleted or mounted.
# - Only p3 (NIXOS-ESP) and p4 (NIXOS-LUKS) may be recreated or formatted.
# - Before, during and after partitioning, p1/p2 are checked against the
#   baseline captured at startup.
# - Unknown existing p3/p4 partitions are never deleted automatically.
# - No EFI NVRAM entries are written; the NixOS profile enforces
#   boot.loader.efi.canTouchEfiVariables = false.
# - The full NixOS build is performed only by nixos-install with --root /mnt,
#   using the large target store under /mnt/nix rather than the copy-to-RAM
#   store of the T2 installation medium.

TARGET_DISK="/dev/nvme0n1"
APPLE_EFI="${TARGET_DISK}p1"
APPLE_APFS="${TARGET_DISK}p2"
NIXOS_ESP="${TARGET_DISK}p3"
NIXOS_LUKS="${TARGET_DISK}p4"

EXPECTED_MODEL="MacBookAir8,1"
EFI_SYSTEM_PARTITION_GUID="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
APPLE_APFS_PARTITION_GUID="7c3457ef-0000-11aa-aa11-00306543ecac"
NIXOS_ESP_SIZE_BYTES=$((2 * 1024 * 1024 * 1024))
SWAP_SIZE="16G"
KERNEL_SECTOR_SIZE=512

PROFILE="apple-macbook-air-8-1"
DEFAULT_HOST_NAME="apple-macbook-air-8-1"
PROFILE_REL="hosts/${PROFILE}/default.nix"
LUKS_PASSWORD_FILE="/tmp/nixos-mac-luks-password"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/install-common.sh
source "$SCRIPT_DIR/scripts/install-common.sh"

WORKDIR=""
LAYOUT_CHECK_ONLY=0

cleanup() {
  rm -f "$LUKS_PASSWORD_FILE"
  if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

case "$#" in
  0)
    ;;
  1)
    [[ "$1" == "--layout-check" ]] || \
      install_die "Usage: sudo ./install-apple-macbook-air-8-1.sh [--layout-check]"
    LAYOUT_CHECK_ONLY=1
    ;;
  *)
    install_die "Usage: sudo ./install-apple-macbook-air-8-1.sh [--layout-check]"
    ;;
esac

[[ "$EUID" -eq 0 ]] || install_die "Run as root: sudo ./install-apple-macbook-air-8-1.sh [--layout-check]"
[[ -d /sys/firmware/efi/efivars ]] || install_die "The installation medium was not booted in UEFI mode."

if [[ "$LAYOUT_CHECK_ONLY" -eq 0 && -n "${SSH_CONNECTION:-}${SSH_CLIENT:-}${SSH_TTY:-}" && -z "${TMUX:-}" ]]; then
  cat >&2 <<'EOF'
ERROR: Installation over SSH detected, but no tmux session is active.
The installer will not run inside an unprotected SSH session.

If tmux is missing from the live system:
  nix shell nixpkgs#tmux

Then:
  tmux new -s nixos-install
  ./install-apple-macbook-air-8-1.sh

Detach from tmux: Ctrl+B, then D
Reconnect: tmux attach -t nixos-install
EOF
  exit 1
fi

for command in \
  lsblk blkid blockdev tr findmnt
do
  install_need_command "$command"
done

if [[ "$LAYOUT_CHECK_ONLY" -eq 0 ]]; then
  for command in \
    nix nix-build nix-channel nix-instantiate nixos-install nixos-enter \
    readlink grep sed awk cut parted partprobe udevadm cryptsetup mkfs.fat mkfs.btrfs btrfs \
    mount mountpoint umount swapon swapoff \
    curl cp mv mkdir mktemp sync find stat
  do
    install_need_command "$command"
  done
fi

ACTUAL_MODEL="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
[[ "$ACTUAL_MODEL" == "$EXPECTED_MODEL" ]] || \
  install_die "Wrong device: expected ${EXPECTED_MODEL}, found ${ACTUAL_MODEL:-<unknown>}"

[[ -b "$TARGET_DISK" ]] || install_die "Internal SSD is missing: $TARGET_DISK"
[[ -b "$APPLE_EFI" ]] || install_die "Apple EFI is missing: $APPLE_EFI"
[[ -b "$APPLE_APFS" ]] || install_die "macOS/APFS partition is missing: $APPLE_APFS"

if findmnt -rn -S "$APPLE_EFI" >/dev/null 2>&1; then
  install_die "Apple EFI is mounted. The installer does not touch mounted protected partitions."
fi
if findmnt -rn -S "$APPLE_APFS" >/dev/null 2>&1; then
  install_die "macOS/APFS is mounted. The installer does not touch mounted protected partitions."
fi

LOGICAL_SECTOR_SIZE="$(blockdev --getss "$TARGET_DISK")"
[[ "$LOGICAL_SECTOR_SIZE" -eq 4096 ]] || \
  install_die "Unexpected logical sector size: ${LOGICAL_SECTOR_SIZE} bytes (expected 4096)."
(( LOGICAL_SECTOR_SIZE % KERNEL_SECTOR_SIZE == 0 )) || \
  install_die "Logical sector size is not a multiple of ${KERNEL_SECTOR_SIZE} bytes."
SECTOR_FACTOR=$((LOGICAL_SECTOR_SIZE / KERNEL_SECTOR_SIZE))

partition_sysfs_dir() {
  local number="$1"
  printf '/sys/class/block/%sp%s\n' "${TARGET_DISK##*/}" "$number"
}

partition_start() {
  local number="$1"
  local sysfs_dir
  local raw_start

  sysfs_dir="$(partition_sysfs_dir "$number")"
  [[ -r "$sysfs_dir/start" ]] || return 1
  read -r raw_start < "$sysfs_dir/start"
  [[ "$raw_start" =~ ^[0-9]+$ ]] || return 1
  (( raw_start % SECTOR_FACTOR == 0 )) || \
    install_die "p${number} does not start on a logical sector boundary."
  printf '%s\n' "$((raw_start / SECTOR_FACTOR))"
}

partition_size() {
  local number="$1"
  local sysfs_dir
  local raw_size

  sysfs_dir="$(partition_sysfs_dir "$number")"
  [[ -r "$sysfs_dir/size" ]] || return 1
  read -r raw_size < "$sysfs_dir/size"
  [[ "$raw_size" =~ ^[0-9]+$ ]] || return 1
  (( raw_size % SECTOR_FACTOR == 0 )) || \
    install_die "p${number} does not have an integral size in logical sectors."
  printf '%s\n' "$((raw_size / SECTOR_FACTOR))"
}

partition_end() {
  local start
  local size

  start="$(partition_start "$1")" || return 1
  size="$(partition_size "$1")" || return 1
  (( size > 0 )) || return 1
  printf '%s\n' "$((start + size - 1))"
}

partition_bounds() {
  local start
  local end

  start="$(partition_start "$1")" || return 1
  end="$(partition_end "$1")" || return 1
  printf '%s:%s\n' "$start" "$end"
}

partition_name() {
  lsblk -dnro PARTLABEL "${TARGET_DISK}p$1" 2>/dev/null || true
}

partition_partuuid() {
  blkid -s PARTUUID -o value "${TARGET_DISK}p$1" 2>/dev/null || true
}

partition_type_guid() {
  lsblk -dnro PARTTYPE "${TARGET_DISK}p$1" 2>/dev/null \
    | tr '[:upper:]' '[:lower:]'
}

partition_snapshot() {
  local number="$1"
  printf '%s|%s|%s|%s\n' \
    "$(partition_partuuid "$number")" \
    "$(partition_type_guid "$number")" \
    "$(partition_bounds "$number")" \
    "$(partition_name "$number")"
}

assert_apple_partitions_unchanged() {
  local phase="$1"
  local current_efi
  local current_apfs

  [[ -b "$APPLE_EFI" ]] || install_die "Apple EFI is missing ${phase}: $APPLE_EFI"
  [[ -b "$APPLE_APFS" ]] || install_die "macOS/APFS is missing ${phase}: $APPLE_APFS"

  current_efi="$(partition_snapshot 1)"
  current_apfs="$(partition_snapshot 2)"

  [[ "$current_efi" == "$APPLE_EFI_BASELINE" ]] || \
    install_die "Apple EFI changed ${phase}. Aborting."
  [[ "$current_apfs" == "$APPLE_APFS_BASELINE" ]] || \
    install_die "macOS/APFS changed ${phase}. Aborting."
}

APPLE_EFI_TYPE="$(partition_type_guid 1)"
APPLE_APFS_TYPE="$(partition_type_guid 2)"
[[ "$APPLE_EFI_TYPE" == "$EFI_SYSTEM_PARTITION_GUID" ]] || \
  install_die "p1 is not an EFI System Partition: ${APPLE_EFI_TYPE:-<empty>}"
[[ "$APPLE_APFS_TYPE" == "$APPLE_APFS_PARTITION_GUID" ]] || \
  install_die "p2 is not an Apple APFS partition: ${APPLE_APFS_TYPE:-<empty>}"

APPLE_EFI_BOUNDS="$(partition_bounds 1)"
APPLE_APFS_BOUNDS="$(partition_bounds 2)"
[[ -n "$APPLE_EFI_BOUNDS" ]] || install_die "Sector bounds for p1 could not be read."
[[ -n "$APPLE_APFS_BOUNDS" ]] || install_die "Sector bounds for p2 could not be read."

APPLE_EFI_START="$(partition_start 1)"
APPLE_EFI_END="$(partition_end 1)"
APPLE_APFS_START="$(partition_start 2)"
APPLE_APFS_END="$(partition_end 2)"

[[ "$APPLE_EFI_START" =~ ^[0-9]+$ && "$APPLE_EFI_END" =~ ^[0-9]+$ ]] || \
  install_die "Invalid sector bounds for p1: $APPLE_EFI_BOUNDS"
[[ "$APPLE_APFS_START" =~ ^[0-9]+$ && "$APPLE_APFS_END" =~ ^[0-9]+$ ]] || \
  install_die "Invalid sector bounds for p2: $APPLE_APFS_BOUNDS"
(( APPLE_EFI_START <= APPLE_EFI_END )) || install_die "Invalid sector order for p1."
(( APPLE_APFS_START <= APPLE_APFS_END )) || install_die "Invalid sector order for p2."
(( APPLE_EFI_END < APPLE_APFS_START )) || \
  install_die "p1 and p2 overlap or are not in the expected order."

[[ -n "$(partition_partuuid 1)" ]] || install_die "PARTUUID for p1 could not be read."
[[ -n "$(partition_partuuid 2)" ]] || install_die "PARTUUID for p2 could not be read."
APPLE_EFI_BASELINE="$(partition_snapshot 1)"
APPLE_APFS_BASELINE="$(partition_snapshot 2)"

EXTRA_PARTITIONS=""
for sys_partition in "/sys/class/block/${TARGET_DISK##*/}"p*; do
  [[ -e "$sys_partition" ]] || continue
  number="${sys_partition##*p}"
  if [[ "$number" =~ ^[0-9]+$ ]] && (( number > 4 )); then
    EXTRA_PARTITIONS+="${number} "
  fi
done
[[ -z "$EXTRA_PARTITIONS" ]] || \
  install_die "Unexpected additional GPT partition(s) found: ${EXTRA_PARTITIONS% }"

ALIGNMENT_SECTORS=$((1024 * 1024 / LOGICAL_SECTOR_SIZE))
NIXOS_ESP_SIZE_SECTORS=$((NIXOS_ESP_SIZE_BYTES / LOGICAL_SECTOR_SIZE))
NIXOS_ESP_START=$(( ((APPLE_APFS_END + 1 + ALIGNMENT_SECTORS - 1) / ALIGNMENT_SECTORS) * ALIGNMENT_SECTORS ))
NIXOS_ESP_END=$((NIXOS_ESP_START + NIXOS_ESP_SIZE_SECTORS - 1))
NIXOS_LUKS_START=$((NIXOS_ESP_END + 1))

RAW_DISK_SIZE_SECTORS="$(blockdev --getsz "$TARGET_DISK")"
[[ "$RAW_DISK_SIZE_SECTORS" =~ ^[0-9]+$ ]] || install_die "Disk size could not be read."
(( RAW_DISK_SIZE_SECTORS % SECTOR_FACTOR == 0 )) || \
  install_die "Disk size does not end on a logical sector boundary."
DISK_SIZE_SECTORS=$((RAW_DISK_SIZE_SECTORS / SECTOR_FACTOR))
(( NIXOS_LUKS_START < DISK_SIZE_SECTORS )) || \
  install_die "There is not enough space behind macOS/APFS for NIXOS-ESP and NIXOS-LUKS."

linux_partition_exists() {
  [[ -b "${TARGET_DISK}p$1" ]]
}

validate_existing_linux_partition() {
  local number="$1"
  local expected_name="$2"
  local start
  local actual_name

  linux_partition_exists "$number" || return 0

  start="$(partition_start "$number")"
  actual_name="$(partition_name "$number")"

  [[ "$start" =~ ^[0-9]+$ ]] || install_die "Start sector for p${number} could not be read."
  (( start > APPLE_APFS_END )) || \
    install_die "p${number} is not located completely behind the protected macOS/APFS partition."
  [[ "$actual_name" == "$expected_name" ]] || \
    install_die "p${number} is not a known NixOS partition (${actual_name:-<unnamed>}). It will not be deleted automatically."
}

validate_existing_linux_partition 3 "NIXOS-ESP"
validate_existing_linux_partition 4 "NIXOS-LUKS"

LINUX_LAYOUT_OK=1
if ! linux_partition_exists 3 || ! linux_partition_exists 4; then
  LINUX_LAYOUT_OK=0
else
  [[ "$(partition_bounds 3)" == "${NIXOS_ESP_START}:${NIXOS_ESP_END}" ]] || LINUX_LAYOUT_OK=0
  [[ "$(partition_start 4)" == "$NIXOS_LUKS_START" ]] || LINUX_LAYOUT_OK=0
fi

printf '\nVerified dual-boot base layout:\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTUUID,PARTTYPE,PARTLABEL,MOUNTPOINTS "$TARGET_DISK"
printf '\nProtected runtime baseline:\n'
printf '  p1: EFI System Partition, sectors %s-%s\n' "$APPLE_EFI_START" "$APPLE_EFI_END"
printf '  p2: Apple APFS,          sectors %s-%s\n' "$APPLE_APFS_START" "$APPLE_APFS_END"
printf 'Derived Linux area:\n'
printf '  p3: NIXOS-ESP, 2 GiB,   sectors %s-%s\n' "$NIXOS_ESP_START" "$NIXOS_ESP_END"
printf '  p4: NIXOS-LUKS,         from sector %s to the end of the disk\n' "$NIXOS_LUKS_START"

if [[ "$LINUX_LAYOUT_OK" -eq 1 ]]; then
  printf 'Existing p3/p4 layout is compatible and can be formatted without repartitioning.\n'
else
  printf 'p3/p4 are missing or differ; only known NIXOS partitions would be recreated.\n'
fi

assert_apple_partitions_unchanged "during the layout check"

if [[ "$LAYOUT_CHECK_ONLY" -eq 1 ]]; then
  printf '\nLayout check succeeded. No partitions were modified.\n'
  exit 0
fi

printf '\nUpdating nixos-unstable for the installation...\n'
nix-channel --add https://channels.nixos.org/nixos-unstable nixos
nix-channel --update nixos

NIXPKGS_PATH="$(readlink -f /nix/var/nix/profiles/per-user/root/channels/nixos)"
[[ -d "$NIXPKGS_PATH" ]] || install_die "Updated nixos channel was not found."

NIXPKGS_VERSION="$(
  nix-instantiate \
    -I "nixpkgs=$NIXPKGS_PATH" \
    --eval -E '(import <nixpkgs> {}).lib.version'
)"
printf 'Using nixpkgs: %s\n' "$NIXPKGS_VERSION"

for file in \
  configuration.nix scripts/install-common.sh \
  "$PROFILE_REL" \
  "hosts/${PROFILE}/base.nix" \
  "hosts/${PROFILE}/hardware.nix" \
  "hosts/${PROFILE}/power.nix" \
  "hosts/${PROFILE}/storage.nix" \
  modules/common/default.nix modules/common/identity.nix modules/common/base.nix \
  modules/common/programs.nix modules/common/fastfetch.nix modules/common/users.nix \
  modules/common/packages.nix modules/common/fonts.nix modules/common/spotify.nix \
  modules/desktops/cosmic.nix modules/features/kate.nix \
  topgrade.nix lon.nix lon.lock pkgs/powertop-2.16.nix
do
  [[ -f "$SCRIPT_DIR/$file" ]] || install_die "Required file is missing: $SCRIPT_DIR/$file"
done

printf '\nLocal system identity:\n'
install_prompt_identity "$DEFAULT_HOST_NAME"
printf '  Hardware profile: %s\n' "$PROFILE"
printf '  Hostname:         %s\n' "$INSTALL_HOST_NAME"
printf '  User:             %s\n' "$INSTALL_USER"
printf '  Display name:     %s\n' "$INSTALL_FULL_NAME"

WORKDIR="$(mktemp -d /tmp/nixos-macbook-air-install.XXXXXX)"
printf 'Configuration working copy: %s\n' "$WORKDIR"
cp -a "$SCRIPT_DIR"/. "$WORKDIR"/
rm -f "$WORKDIR"/result "$WORKDIR"/result-*
rm -f "$WORKDIR/apple-sf-fonts.tar.zst" "$WORKDIR/apple-sf-fonts.tar.zst.sha256"

install_write_local_identity "$WORKDIR" "$PROFILE_REL"

printf '\nChecking NixOS target configuration against current nixos-unstable...\n'
nix-instantiate '<nixpkgs/nixos>' -A system \
  -I "nixpkgs=$NIXPKGS_PATH" \
  -I "nixos-config=$WORKDIR/configuration.nix" \
  >/dev/null
printf 'Preflight succeeded. No partition has been modified yet.\n'

assert_apple_partitions_unchanged "after the preflight"

printf '\nWARNING: Only the Linux area will now be erased/formatted.\n'
printf '  p3: %s (NIXOS-ESP)\n' "$NIXOS_ESP"
printf '  p4: %s (NIXOS-LUKS)\n' "$NIXOS_LUKS"
printf '  p1: %s (Apple EFI)  remains untouched\n' "$APPLE_EFI"
printf '  p2: %s (macOS/APFS) remains untouched\n' "$APPLE_APFS"

if [[ "$LINUX_LAYOUT_OK" -eq 0 ]]; then
  printf 'The existing Linux partition layout is missing or differs; only known p3/p4 will be recreated.\n'
else
  printf 'The existing p3/p4 layout is compatible; only the filesystems will be recreated.\n'
fi

CONFIRM_TEXT="FORMAT ONLY P3 P4"
read -r -p "Enter exactly '${CONFIRM_TEXT}' to continue: " CONFIRM
[[ "$CONFIRM" == "$CONFIRM_TEXT" ]] || install_die "Aborted."

while true; do
  printf '\n'
  read -r -s -p "New LUKS passphrase: " LUKS_PASSWORD_1
  printf '\n'
  read -r -s -p "Repeat passphrase: " LUKS_PASSWORD_2
  printf '\n'
  [[ -n "$LUKS_PASSWORD_1" ]] || { echo "The passphrase must not be empty."; continue; }
  [[ "$LUKS_PASSWORD_1" == "$LUKS_PASSWORD_2" ]] || { echo "The passphrases do not match."; continue; }
  break
done

(
  umask 077
  printf '%s' "$LUKS_PASSWORD_1" > "$LUKS_PASSWORD_FILE"
  chmod 600 "$LUKS_PASSWORD_FILE"
)
unset LUKS_PASSWORD_1 LUKS_PASSWORD_2
umask 022

swapoff /mnt/swap/swapfile 2>/dev/null || true
if mountpoint -q /mnt; then
  umount -R /mnt
fi
if cryptsetup status root >/dev/null 2>&1; then
  cryptsetup close root
fi

assert_apple_partitions_unchanged "immediately before partitioning"

if [[ "$LINUX_LAYOUT_OK" -eq 0 ]]; then
  printf '\nRecreating only p3/p4...\n'

  if linux_partition_exists 4; then
    [[ "$(partition_name 4)" == "NIXOS-LUKS" ]] || \
      install_die "p4 is not recognized as NIXOS-LUKS and will not be deleted."
    parted --script "$TARGET_DISK" rm 4
  fi
  if linux_partition_exists 3; then
    [[ "$(partition_name 3)" == "NIXOS-ESP" ]] || \
      install_die "p3 is not recognized as NIXOS-ESP and will not be deleted."
    parted --script "$TARGET_DISK" rm 3
  fi

  partprobe "$TARGET_DISK"
  udevadm settle
  assert_apple_partitions_unchanged "after removing the Linux partitions"

  parted --script "$TARGET_DISK" \
    mkpart NIXOS-ESP fat32 "${NIXOS_ESP_START}s" "${NIXOS_ESP_END}s" \
    set 3 esp on \
    mkpart NIXOS-LUKS "${NIXOS_LUKS_START}s" 100%
  partprobe "$TARGET_DISK"
  udevadm settle

  [[ -b "$NIXOS_ESP" && -b "$NIXOS_LUKS" ]] || \
    install_die "p3/p4 were not detected after recreation."

  assert_apple_partitions_unchanged "after recreating the Linux partitions"
fi

[[ "$(partition_bounds 3)" == "${NIXOS_ESP_START}:${NIXOS_ESP_END}" ]] || \
  install_die "NIXOS-ESP does not have the derived 2 GiB sector bounds."
[[ "$(partition_start 4)" == "$NIXOS_LUKS_START" ]] || \
  install_die "NIXOS-LUKS does not start at the expected sector."
[[ "$(partition_name 3)" == "NIXOS-ESP" ]] || \
  install_die "p3 does not have GPT name NIXOS-ESP."
[[ "$(partition_name 4)" == "NIXOS-LUKS" ]] || \
  install_die "p4 does not have GPT name NIXOS-LUKS."

assert_apple_partitions_unchanged "immediately before formatting"

printf '\nFormatting only p3/p4...\n'
mkfs.fat -F 32 -n NIXOS-ESP "$NIXOS_ESP"
cryptsetup luksFormat --type luks2 --batch-mode "$NIXOS_LUKS" "$LUKS_PASSWORD_FILE"
cryptsetup open "$NIXOS_LUKS" root --key-file "$LUKS_PASSWORD_FILE"
rm -f "$LUKS_PASSWORD_FILE"

mkfs.btrfs -f -L NIXOS /dev/mapper/root
mount /dev/mapper/root /mnt
for subvol in @root @home @nix @swap; do
  btrfs subvolume create "/mnt/$subvol"
done
umount /mnt

mount -o subvol=@root,compress=zstd:3,noatime /dev/mapper/root /mnt
chmod 0755 /mnt
mkdir -p /mnt/home /mnt/nix /mnt/swap /mnt/boot
mount -o subvol=@home,compress=zstd:3,noatime /dev/mapper/root /mnt/home
mount -o subvol=@nix,compress=zstd:3,noatime /dev/mapper/root /mnt/nix
mount -o subvol=@swap /dev/mapper/root /mnt/swap
chmod 0755 /mnt/home /mnt/nix
chmod 0700 /mnt/swap
mount -o umask=0077 "$NIXOS_ESP" /mnt/boot

btrfs filesystem mkswapfile --size "$SWAP_SIZE" --uuid clear /mnt/swap/swapfile
swapon /mnt/swap/swapfile

for mountpoint_path in /mnt /mnt/boot /mnt/home /mnt/nix /mnt/swap; do
  mountpoint -q "$mountpoint_path" || install_die "Expected mount point is missing: $mountpoint_path"
done

assert_apple_partitions_unchanged "after Linux formatting"

printf '\nDisk layout before nixos-install:\n'
lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTUUID,PARTTYPE,PARTLABEL,MOUNTPOINTS "$TARGET_DISK"

printf '\nCopying NixOS configuration into the target system...\n'
rm -rf /mnt/etc/nixos
mkdir -p /mnt/etc/nixos
cp -a "$WORKDIR"/. /mnt/etc/nixos/
rm -f /mnt/etc/nixos/host.nix /mnt/etc/nixos/hardware-configuration.nix

printf '\nInstalling NixOS into target store /mnt/nix...\n'
nixos-install \
  --root /mnt \
  --no-root-passwd \
  --channel "$NIXPKGS_PATH" \
  -I "nixpkgs=$NIXPKGS_PATH" \
  -I nixos-config=/mnt/etc/nixos/configuration.nix

install_set_fresh_password /mnt
install_prepare_repo_permissions /mnt
sync

printf '\n============================================================\n'
printf ' NixOS was installed on the MacBookAir8,1.\n'
printf '============================================================\n'
printf 'Hostname: %s\n' "$INSTALL_HOST_NAME"
printf 'User:     %s\n' "$INSTALL_USER"
printf 'Profile:  %s\n' "$PROFILE"
printf '\nApple EFI and macOS/APFS were neither formatted nor mounted.\n'
printf 'Use Apple Startup Manager (Option/Alt) on reboot.\n'
