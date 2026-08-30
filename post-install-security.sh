#!/usr/bin/env bash

set -Eeuo pipefail

CONFIG_DIR="/etc/nixos"
CONFIG_FILE="${CONFIG_DIR}/configuration.nix"
PROFILE_SELECTOR="${CONFIG_DIR}/profile.nix"
IDENTITY_FILE="${CONFIG_DIR}/identity.json"
SECUREBOOT_MODULE="${CONFIG_DIR}/secureboot.nix"

ROOT_PART_LINK="/dev/disk/by-partlabel/root-x86-64"
PCRLOCK_POLICY="/var/lib/systemd/pcrlock.json"
SBCTL_DIR="/var/lib/sbctl"

EFI_GLOBAL_GUID="8be4df61-93ca-11d2-aa0d-00e098032b8c"
SETUP_MODE_VAR="/sys/firmware/efi/efivars/SetupMode-${EFI_GLOBAL_GUID}"
SECURE_BOOT_VAR="/sys/firmware/efi/efivars/SecureBoot-${EFI_GLOBAL_GUID}"

die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

need_root() {
  [[ "$EUID" -eq 0 ]] || die "Run as root, for example: sudo $0 $1"
}

need_command() {
  command -v "$1" >/dev/null || die "Required program is missing: $1"
}

read_efi_boolean() {
  local variable_file="$1"
  [[ -r "$variable_file" ]] || die "UEFI variable cannot be read: $variable_file"
  od -An -t u1 -j 4 -N 1 "$variable_file" | tr -d '[:space:]'
}

secure_boot_state() {
  local setup_mode secure_boot
  setup_mode="$(read_efi_boolean "$SETUP_MODE_VAR")"
  secure_boot="$(read_efi_boolean "$SECURE_BOOT_VAR")"
  echo "SetupMode=${setup_mode} SecureBoot=${secure_boot}"
}

check_uefi() {
  [[ -d /sys/firmware/efi/efivars ]] || die "System was not booted in UEFI mode."
}

check_root_luks() {
  [[ -e "$ROOT_PART_LINK" ]] || die "Root partition not found: $ROOT_PART_LINK"
  ROOT_PART="$(readlink -f -- "$ROOT_PART_LINK")"
  [[ -b "$ROOT_PART" ]] || die "Root partition is not a block device: $ROOT_PART"

  local fstype
  fstype="$(blkid -s TYPE -o value "$ROOT_PART")"
  [[ "$fstype" == "crypto_LUKS" ]] || die "Root partition is not LUKS: $ROOT_PART ($fstype)"
}

show_status() {
  check_uefi

  echo "============================================================"
  echo " Secure Boot / TPM status"
  echo "============================================================"
  echo
  echo "UEFI:"
  secure_boot_state
  echo

  echo "Local profile selector:"
  if [[ -f "$PROFILE_SELECTOR" ]]; then
    grep -E '^[[:space:]]*\./hosts/[^/]+/(installation|default)\.nix' "$PROFILE_SELECTOR" || true
  else
    echo "missing: $PROFILE_SELECTOR"
  fi

  echo
  echo "Local identity:"
  if [[ -f "$IDENTITY_FILE" ]]; then
    cat "$IDENTITY_FILE"
  else
    echo "missing: $IDENTITY_FILE"
  fi
  echo

  if command -v bootctl >/dev/null; then
    bootctl status || true
    echo
  fi

  if command -v sbctl >/dev/null; then
    sbctl status || true
    echo
  fi

  if [[ -e "$ROOT_PART_LINK" ]] && command -v systemd-cryptenroll >/dev/null; then
    check_root_luks
    echo "LUKS2 enrollments for $ROOT_PART:"
    systemd-cryptenroll "$ROOT_PART" || true
    echo
  fi

  if [[ -s "$PCRLOCK_POLICY" ]]; then
    echo "PCRLock policy: present ($PCRLOCK_POLICY)"
  else
    echo "PCRLock policy: not present yet"
  fi
}

prepare_secureboot() {
  need_root prepare
  check_uefi

  for cmd in od tr grep cp mktemp rm sbctl nixos-rebuild; do
    need_command "$cmd"
  done

  local setup_mode secure_boot
  setup_mode="$(read_efi_boolean "$SETUP_MODE_VAR")"
  secure_boot="$(read_efi_boolean "$SECURE_BOOT_VAR")"

  [[ "$setup_mode" == "1" ]] || die "Firmware is no longer in Secure Boot Setup Mode."
  [[ "$secure_boot" == "0" ]] || die "Secure Boot is already active; 'prepare' is intended for the first boot in Setup Mode."
  [[ -f "$CONFIG_FILE" ]] || die "NixOS configuration is missing: $CONFIG_FILE"
  [[ -f "$PROFILE_SELECTOR" ]] || die "Local profile selector is missing: $PROFILE_SELECTOR"
  [[ -f "$IDENTITY_FILE" ]] || die "Local identity is missing: $IDENTITY_FILE"
  [[ -f "$SECUREBOOT_MODULE" ]] || die "Secure Boot module is missing: $SECUREBOOT_MODULE"

  local target_profile=""
  local selector_backup=""

  if grep -Fq './hosts/thinkpad-x1-carbon-gen13/installation.nix' "$PROFILE_SELECTOR"; then
    target_profile="./hosts/thinkpad-x1-carbon-gen13/default.nix"
  elif grep -Fq './hosts/hp-z2-tower-g9/installation.nix' "$PROFILE_SELECTOR"; then
    target_profile="./hosts/hp-z2-tower-g9/default.nix"
  elif grep -Fq './hosts/thinkpad-x1-carbon-gen13/default.nix' "$PROFILE_SELECTOR"; then
    echo "Profile selector already points to ./hosts/thinkpad-x1-carbon-gen13/default.nix"
  elif grep -Fq './hosts/hp-z2-tower-g9/default.nix' "$PROFILE_SELECTOR"; then
    echo "Profile selector already points to ./hosts/hp-z2-tower-g9/default.nix"
  else
    die "Unknown profile selector in $PROFILE_SELECTOR."
  fi

  if [[ -n "$target_profile" && ! -f "${CONFIG_DIR}/${target_profile#./}" ]]; then
    die "Normal hardware profile is missing: ${CONFIG_DIR}/${target_profile#./}"
  fi

  echo "Secure Boot Setup Mode: OK"
  echo "Local profile selector: OK"
  echo

  if [[ ! -f "${SBCTL_DIR}/keys/db/db.key" ||
        ! -f "${SBCTL_DIR}/keys/db/db.pem" ||
        ! -f "${SBCTL_DIR}/keys/KEK/KEK.key" ||
        ! -f "${SBCTL_DIR}/keys/PK/PK.key" ]]; then
    echo "Creating Secure Boot keys with sbctl..."
    sbctl create-keys
  else
    echo "Secure Boot keys are already present."
  fi

  if [[ -n "$target_profile" ]]; then
    selector_backup="$(mktemp /tmp/nixos-profile-selector.XXXXXX)"
    cp -a "$PROFILE_SELECTOR" "$selector_backup"

    cat > "$PROFILE_SELECTOR" <<EOF
{ ... }:

{
  imports = [
    ${target_profile}
  ];
}
EOF

    echo
    echo "Profile selector switched to normal profile:"
    echo "  ${target_profile}"
  fi

  echo
  echo "Building and activating Lanzaboote configuration..."

  if ! nixos-rebuild switch; then
    if [[ -n "$selector_backup" && -f "$selector_backup" ]]; then
      cp -a "$selector_backup" "$PROFILE_SELECTOR"
      rm -f "$selector_backup"
      echo "Profile selector was restored after the failed rebuild." >&2
    fi
    die "nixos-rebuild switch failed."
  fi

  if [[ -n "$selector_backup" ]]; then
    rm -f "$selector_backup"
  fi

  echo
  echo "Checking signed EFI files:"
  echo "Note: older/additional kernel files may be reported as unsigned by sbctl;"
  echo "the current Lanzaboote/NixOS EFI artifacts are what matter."
  echo
  sbctl verify || true

  echo
  echo "Preparation complete."
  echo "Next step: sudo $0 enroll-secureboot"
}

enroll_secureboot() {
  need_root enroll-secureboot
  check_uefi

  for cmd in od tr sbctl; do
    need_command "$cmd"
  done

  local setup_mode secure_boot
  setup_mode="$(read_efi_boolean "$SETUP_MODE_VAR")"
  secure_boot="$(read_efi_boolean "$SECURE_BOOT_VAR")"

  [[ "$setup_mode" == "1" ]] || die "Firmware is not in Setup Mode; Secure Boot keys will not be enrolled."
  [[ "$secure_boot" == "0" ]] || die "Secure Boot is already active."
  [[ -f "${SBCTL_DIR}/keys/db/db.key" ]] || die "sbctl keys are missing. Run '$0 prepare' first."

  echo "Current signature verification:"
  sbctl verify || true
  echo
  echo "The custom sbctl keys will now be enrolled in the UEFI firmware together"
  echo "with the Microsoft OEM keys."
  echo
  read -r -p "Enter exactly 'ENROLL SECURE BOOT' to continue: " confirm
  [[ "$confirm" == "ENROLL SECURE BOOT" ]] || die "Aborted."

  sbctl enroll-keys --microsoft --ignore-immutable

  echo
  echo "Keys were enrolled."
  echo "Reboot now, then verify with 'sudo $0 status'."
  echo "Expected: SetupMode=0 and SecureBoot=1."
}

enroll_tpm() {
  need_root enroll-tpm
  check_uefi

  for cmd in od tr readlink blkid cryptsetup systemd-cryptenroll; do
    need_command "$cmd"
  done

  local setup_mode secure_boot
  setup_mode="$(read_efi_boolean "$SETUP_MODE_VAR")"
  secure_boot="$(read_efi_boolean "$SECURE_BOOT_VAR")"

  [[ "$setup_mode" == "0" ]] || die "Firmware is still in Setup Mode. Fully enable Secure Boot and reboot first."
  [[ "$secure_boot" == "1" ]] || die "Secure Boot is not active. TPM2 enrollment is aborted."
  [[ -s "$PCRLOCK_POLICY" ]] || die "PCRLock policy is missing or empty: $PCRLOCK_POLICY."

  check_root_luks

  echo "TPM2 devices:"
  systemd-cryptenroll --tpm2-device=list
  echo
  echo "Current LUKS2 enrollments:"
  systemd-cryptenroll "$ROOT_PART" || true
  echo

  backup="/root/luks-root-header-before-tpm2-$(date +%Y%m%d-%H%M%S).img"
  echo "Backing up the current LUKS2 header to: $backup"
  cryptsetup luksHeaderBackup "$ROOT_PART" --header-backup-file "$backup"
  chmod 600 "$backup"

  echo
  echo "IMPORTANT:"
  echo "  - The existing LUKS passphrase remains available."
  echo "  - Only old TPM2 enrollments are replaced after the new enrollment succeeds."
  echo "  - systemd-cryptenroll asks for the existing LUKS passphrase"
  echo "    and then for the new TPM2 PIN."
  echo
  read -r -p "Enter exactly 'ENROLL TPM2 PIN' to continue: " confirm
  [[ "$confirm" == "ENROLL TPM2 PIN" ]] || die "Aborted."

  systemd-cryptenroll \
    --wipe-slot=tpm2 \
    --tpm2-device=auto \
    --tpm2-with-pin=yes \
    --tpm2-pcrlock="$PCRLOCK_POLICY" \
    "$ROOT_PART"

  echo
  echo "TPM2 enrollment complete."
  systemd-cryptenroll "$ROOT_PART" || true
  echo "Reboot now and test TPM2+PIN. The normal LUKS passphrase remains the fallback."
}

usage() {
  cat <<EOF
Usage:
  sudo $0 prepare
  sudo $0 enroll-secureboot
  sudo $0 enroll-tpm
  sudo $0 status

Sequence after a fresh NixOS installation:

  1. First normal boot with systemd-boot
  2. sudo $0 prepare
     - creates sbctl keys if needed
     - switches profile.nix from installation.nix to default.nix
     - builds and activates Lanzaboote
  3. sudo $0 enroll-secureboot
  4. reboot
  5. sudo $0 status
  6. sudo $0 enroll-tpm
  7. reboot
  8. sudo $0 status
EOF
}

case "${1:-}" in
  prepare) prepare_secureboot ;;
  enroll-secureboot) enroll_secureboot ;;
  enroll-tpm) enroll_tpm ;;
  status) show_status ;;
  *) usage; exit 2 ;;
esac
