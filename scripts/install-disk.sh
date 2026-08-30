#!/usr/bin/env bash

# Shared target-disk handling for destructive x86 workstation installers.
# The repository intentionally contains no disk serial numbers or fixed disk IDs.

install_select_target_disk() {
  local requested_disk="${1:-}"
  local selected_disk=""
  local selection=""
  local details=""
  local i
  local -a disks=()

  if [[ -n "$requested_disk" ]]; then
    selected_disk="$requested_disk"
  else
    mapfile -t disks < <(
      lsblk -dnpo NAME,TYPE \
        | while read -r disk_name disk_type; do
            if [[ "$disk_type" == "disk" ]]; then
              printf '%s\n' "$disk_name"
            fi
          done
    )

    [[ "${#disks[@]}" -gt 0 ]] || install_die "No whole-disk block devices were found."

    echo
    echo "Available target disks:"
    for i in "${!disks[@]}"; do
      details="$(lsblk -dnro SIZE,MODEL,TRAN "${disks[$i]}")"
      printf '  %d) %s  %s\n' "$((i + 1))" "${disks[$i]}" "$details"
    done

    while true; do
      read -r -p "Select the target disk [1-${#disks[@]}]: " selection
      if [[ "$selection" =~ ^[0-9]+$ ]] \
        && (( selection >= 1 && selection <= ${#disks[@]} )); then
        selected_disk="${disks[$((selection - 1))]}"
        break
      fi
      echo "Invalid selection."
    done
  fi

  [[ -e "$selected_disk" ]] || install_die "Target disk not found: $selected_disk"

  TARGET_DISK="$selected_disk"
  REAL_DISK="$(readlink -f -- "$TARGET_DISK")"

  [[ -b "$REAL_DISK" ]] || install_die "Target is not a block device: $REAL_DISK"
  [[ "$(lsblk -dnro TYPE "$REAL_DISK" | tr -d '[:space:]')" == "disk" ]] \
    || install_die "Target is not a whole disk: $REAL_DISK"

  if lsblk -nrpo MOUNTPOINT "$REAL_DISK" | grep -Eq '[^[:space:]]'; then
    install_die "The selected target disk has mounted filesystems. Unmount them before continuing: $REAL_DISK"
  fi

  export TARGET_DISK REAL_DISK
}

install_partition_by_label() {
  local disk="$1"
  local expected_label="$2"
  local name=""
  local label=""
  local found=""

  while read -r name label; do
    if [[ "$label" == "$expected_label" ]]; then
      [[ -z "$found" ]] \
        || install_die "More than one partition with label '$expected_label' exists on $disk."
      found="$name"
    fi
  done < <(lsblk -nrpo NAME,PARTLABEL "$disk")

  [[ -n "$found" ]] \
    || install_die "Partition label '$expected_label' was not found on $disk."

  printf '%s\n' "$found"
}
