#!/usr/bin/env bash

# Shared helper functions for the three hardware-specific installers.

INSTALL_COMMON_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_MANAGER_REPOSITORY="https://github.com/stdruwe/home-manager-workstations.git"
APPLE_FONT_CACHE_DIR="/tmp/nixos-apple-font-cache"

install_die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

install_need_command() {
  command -v "$1" >/dev/null || install_die "Required program is missing: $1"
}

install_validate_home_manager_bundle() {
  local bundle="${HOME_MANAGER_BUNDLE:-/tmp/home-manager.bundle}"
  local verify_dir

  install_need_command git
  install_need_command mktemp
  install_need_command readlink

  [[ -f "$bundle" ]] || install_die "Home Manager bundle is missing: $bundle

Create it on an already authorized machine:
  git -C \"\$HOME/.config/home-manager\" bundle create /tmp/home-manager.bundle main

Copy the bundle to the live system as /tmp/home-manager.bundle before starting the installer.
Alternatively, HOME_MANAGER_BUNDLE may point to another local bundle path."

  verify_dir="$(mktemp -d /tmp/home-manager-bundle-verify.XXXXXX)"
  git -C "$verify_dir" init -q

  if ! git -C "$verify_dir" bundle verify "$bundle" >/dev/null 2>&1; then
    rm -rf "$verify_dir"
    install_die "Home Manager bundle is incomplete or invalid: $bundle"
  fi

  if ! git bundle list-heads "$bundle" refs/heads/main | grep -q ' refs/heads/main$'; then
    rm -rf "$verify_dir"
    install_die "Home Manager bundle does not contain refs/heads/main: $bundle"
  fi

  rm -rf "$verify_dir"

  HOME_MANAGER_BUNDLE_PATH="$(readlink -f -- "$bundle")"
  export HOME_MANAGER_BUNDLE_PATH
}

install_seed_home_manager_lock() {
  local repo_dir="$1"

  if [[ -f "$repo_dir/flake.lock" ]]; then
    return 0
  fi

  [[ -f "$repo_dir/flake.lock.bootstrap" ]] \
    || install_die "Home Manager bootstrap lock is missing: $repo_dir/flake.lock.bootstrap"

  cp "$repo_dir/flake.lock.bootstrap" "$repo_dir/flake.lock"
}

install_prompt_identity() {
  local default_host_name="$1"

  # Home Manager is part of the installation contract. The local bundle is
  # verified before user data is requested and, in particular, before any disk
  # is modified.
  if [[ -z "${HOME_MANAGER_BUNDLE_PATH:-}" ]]; then
    install_validate_home_manager_bundle
  fi

  while true; do
    read -r -p "Hostname [${default_host_name}]: " INSTALL_HOST_NAME
    INSTALL_HOST_NAME="${INSTALL_HOST_NAME:-$default_host_name}"

    if [[ "$INSTALL_HOST_NAME" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
      break
    fi

    echo "Invalid hostname. Allowed characters are lowercase letters, digits and hyphens."
  done

  while true; do
    read -r -p "Username: " INSTALL_USER

    if [[ "$INSTALL_USER" =~ ^[a-z_][a-z0-9_-]{0,30}$ ]]; then
      break
    fi

    echo "Invalid username. Allowed characters are lowercase letters, digits, _ and -."
  done

  while true; do
    read -r -p "Full name: " INSTALL_FULL_NAME
    [[ -n "$INSTALL_FULL_NAME" ]] && break
    echo "The full name must not be empty."
  done

  export INSTALL_HOST_NAME INSTALL_USER INSTALL_FULL_NAME
}

install_prepare_wallpaper() {
  local target_dir="$1"
  local helper="$INSTALL_COMMON_DIR/fetch-wallpaper.sh"

  install_need_command curl
  install_need_command python3
  [[ -f "$helper" ]] || install_die "Wallpaper fetch helper is missing: $helper"

  printf '\nPreparing shared wallpaper...\n'
  if ! bash "$helper" "$target_dir/assets/local"; then
    install_die "Shared wallpaper could not be downloaded from the documented KDE Store source."
  fi
}

install_prepare_apple_fonts() {
  local target_dir="$1"
  local font_tmp
  local output_dir
  local sevenzip
  local -a nix_build_args

  install_need_command curl
  install_need_command find
  install_need_command grep
  install_need_command mktemp
  install_need_command nix-build

  nix_build_args=(
    '<nixpkgs>'
    -A p7zip
    --no-out-link
  )

  # The T2 ISO requires the explicitly updated nixpkgs path. The two standard
  # NixOS installers can use their regular <nixpkgs> path.
  if [[ -n "${NIXPKGS_PATH:-}" ]]; then
    nix_build_args+=( -I "nixpkgs=$NIXPKGS_PATH" )
  fi

  sevenzip="$(nix-build "${nix_build_args[@]}")/bin/7z"
  [[ -x "$sevenzip" ]] || install_die "7z from nixpkgs could not be provided."

  font_tmp="$(mktemp -d /tmp/apple-fonts-common.XXXXXX)"
  output_dir="$font_tmp/output"
  mkdir -p "$output_dir" "$APPLE_FONT_CACHE_DIR"

  extract_apple_font_dmg() {
    local name="$1"
    local url="$2"
    local stage="$font_tmp/$name"
    local dmg="$APPLE_FONT_CACHE_DIR/$name.dmg"
    local dmg_partial="${dmg}.part"
    local pkg
    local payload_cpio
    local payload_gzip
    local fonts_dir
    local -a pkg_candidates
    local -a payload_cpio_candidates
    local -a payload_gzip_candidates
    local -a fonts_dir_candidates

    mkdir -p "$stage/dmg" "$stage/pkg" "$stage/payload" "$stage/cpio"

    if [[ -s "$dmg" ]]; then
      printf '  Using %s from the live-session cache.\n' "$name"
    else
      printf '  Downloading %s from Apple...\n' "$name"
      rm -f "$dmg_partial"
      if ! curl \
        --fail \
        --location \
        --proto '=https' \
        --proto-redir '=https' \
        --tlsv1.2 \
        --retry 3 \
        --retry-all-errors \
        --output "$dmg_partial" \
        "$url"; then
        rm -f "$dmg_partial"
        rm -rf "$font_tmp"
        install_die "$name: download from Apple failed."
      fi
      [[ -s "$dmg_partial" ]] || {
        rm -rf "$font_tmp"
        install_die "$name: Apple DMG is empty."
      }
      mv -f "$dmg_partial" "$dmg"
    fi

    "$sevenzip" x -y "-o$stage/dmg" "$dmg" >/dev/null

    mapfile -t pkg_candidates < <(find "$stage/dmg" -type f -name '*.pkg' -print)
    [[ "${#pkg_candidates[@]}" -eq 1 ]] || {
      rm -rf "$font_tmp"
      install_die "$name: expected exactly one PKG file in the DMG, found ${#pkg_candidates[@]}."
    }
    pkg="${pkg_candidates[0]}"

    "$sevenzip" x -y "-o$stage/pkg" "$pkg" >/dev/null

    # Depending on the 7z version, the CPIO payload appears either directly as
    # Payload~ or first as the gzip file Payload. Both observed Apple forms are
    # handled strictly.
    mapfile -t payload_cpio_candidates < <(find "$stage/pkg" -type f -name 'Payload~' -print)

    if [[ "${#payload_cpio_candidates[@]}" -eq 0 ]]; then
      mapfile -t payload_gzip_candidates < <(find "$stage/pkg" -type f -name 'Payload' -print)
      [[ "${#payload_gzip_candidates[@]}" -eq 1 ]] || {
        rm -rf "$font_tmp"
        install_die "$name: neither a unique Payload~ nor a unique Payload was found."
      }
      payload_gzip="${payload_gzip_candidates[0]}"
      "$sevenzip" x -y "-o$stage/payload" "$payload_gzip" >/dev/null
      mapfile -t payload_cpio_candidates < <(find "$stage/payload" -type f -name 'Payload~' -print)
    fi

    [[ "${#payload_cpio_candidates[@]}" -eq 1 ]] || {
      rm -rf "$font_tmp"
      install_die "$name: expected exactly one CPIO Payload~, found ${#payload_cpio_candidates[@]}."
    }
    payload_cpio="${payload_cpio_candidates[0]}"

    "$sevenzip" x -y "-o$stage/cpio" "$payload_cpio" >/dev/null
    mapfile -t fonts_dir_candidates < <(find "$stage/cpio" -type d -path '*/Library/Fonts' -print)
    [[ "${#fonts_dir_candidates[@]}" -eq 1 ]] || {
      rm -rf "$font_tmp"
      install_die "$name: expected exactly one Library/Fonts directory, found ${#fonts_dir_candidates[@]}."
    }
    fonts_dir="${fonts_dir_candidates[0]}"

    if ! find "$fonts_dir" -maxdepth 1 -type f \
      \( -iname '*.otf' -o -iname '*.ttf' \) \
      -print -quit | grep -q .; then
      rm -rf "$font_tmp"
      install_die "$name: no OTF/TTF files were found in the Apple payload."
    fi

    find "$fonts_dir" -maxdepth 1 -type f \
      \( -iname '*.otf' -o -iname '*.ttf' \) \
      -exec cp -f {} "$output_dir"/ \;
  }

  printf '\nPreparing shared Apple fonts...\n'
  extract_apple_font_dmg \
    "SF-Pro" \
    "https://devimages-cdn.apple.com/design/resources/download/SF-Pro.dmg"
  extract_apple_font_dmg \
    "SF-Mono" \
    "https://devimages-cdn.apple.com/design/resources/download/SF-Mono.dmg"
  extract_apple_font_dmg \
    "NY" \
    "https://devimages-cdn.apple.com/design/resources/download/NY.dmg"

  find "$output_dir" -maxdepth 1 -type f \
    \( -iname '*sf*pro*.otf' -o -iname '*sf*pro*.ttf' \) \
    -print -quit | grep -q . || {
      rm -rf "$font_tmp"
      install_die "SF Pro was not found after extraction."
    }

  find "$output_dir" -maxdepth 1 -type f \
    \( -iname '*sf*mono*.otf' -o -iname '*sf*mono*.ttf' \) \
    -print -quit | grep -q . || {
      rm -rf "$font_tmp"
      install_die "SF Mono was not found after extraction."
    }

  find "$output_dir" -maxdepth 1 -type f \
    \( -iname '*newyork*.otf' -o -iname '*newyork*.ttf' \) \
    -print -quit | grep -q . || {
      rm -rf "$font_tmp"
      install_die "Apple New York was not found after extraction."
    }

  # Replace the previous local font source only after all three families have
  # been extracted successfully. A download/extraction failure therefore leaves
  # the previous state untouched.
  mkdir -p "$target_dir/fonts"
  rm -rf "$target_dir/fonts/apple"
  mv "$output_dir" "$target_dir/fonts/apple"
  rm -rf "$font_tmp"
}

install_preflight_home_manager() {
  local tmp_dir
  local repo_dir

  [[ -n "${HOME_MANAGER_BUNDLE_PATH:-}" ]] || install_die "Home Manager bundle has not been prepared."
  [[ -n "${PROFILE:-}" ]] || install_die "Technical hardware profile is not set for Home Manager."

  tmp_dir="$(mktemp -d /tmp/home-manager-preflight.XXXXXX)"
  repo_dir="$tmp_dir/home-manager"

  if ! git clone --quiet --branch main "$HOME_MANAGER_BUNDLE_PATH" "$repo_dir"; then
    rm -rf "$tmp_dir"
    install_die "Home Manager bundle could not be cloned for preflight."
  fi

  install_seed_home_manager_lock "$repo_dir"

  printf '\nEvaluating Home Manager profile %s before destructive actions...\n' "$PROFILE"
  if ! USER="$INSTALL_USER" HOME="/home/$INSTALL_USER" \
    nix --extra-experimental-features "nix-command flakes" \
      eval \
      --impure \
      --no-write-lock-file \
      --raw \
      "path:$repo_dir#homeConfigurations.${PROFILE}.activationPackage.drvPath" \
      >/dev/null; then
    rm -rf "$tmp_dir"
    install_die "Home Manager profile ${PROFILE} could not be evaluated."
  fi

  rm -rf "$tmp_dir"
}

install_write_local_identity() {
  local target_dir="$1"
  local profile_rel="$2"

  mkdir -p "$target_dir"

  nix \
    --extra-experimental-features "nix-command" \
    eval \
    --impure \
    --json \
    --expr '{
      hostName = builtins.getEnv "INSTALL_HOST_NAME";
      userName = builtins.getEnv "INSTALL_USER";
      fullName = builtins.getEnv "INSTALL_FULL_NAME";
    }' \
    > "$target_dir/identity.json"

  cat > "$target_dir/profile.nix" <<EOF
{ ... }:

{
  imports = [
    ./${profile_rel}
  ];
}
EOF

  install_prepare_wallpaper "$target_dir"

  # All three installers end with exactly the same Apple-sourced font payload,
  # regardless of which legacy/bootstrap files the respective live installation
  # path provided beforehand.
  install_prepare_apple_fonts "$target_dir"

  # User configuration must also be valid before the installer accepts the
  # destructive confirmation.
  install_preflight_home_manager
}

install_prepare_home_manager_target() {
  local target_root="$1"
  local target_home="$target_root/home/$INSTALL_USER"
  local repo_dir="$target_home/.config/home-manager"
  local activation_path
  local pending_file="$target_root/var/lib/nixos/home-manager-initial-activation"

  [[ -n "${HOME_MANAGER_BUNDLE_PATH:-}" ]] || install_die "Home Manager bundle has not been prepared."

  printf '\nCopying Home Manager configuration into the target system...\n'
  mkdir -p "$target_home/.config"
  rm -rf "$repo_dir"
  git clone --quiet --branch main "$HOME_MANAGER_BUNDLE_PATH" "$repo_dir" \
    || install_die "Home Manager bundle could not be cloned into the target system."
  git -C "$repo_dir" remote set-url origin "$HOME_MANAGER_REPOSITORY"
  install_seed_home_manager_lock "$repo_dir"

  # Build directly against the local chroot store under /mnt. This places the
  # activation package and its complete closure into /mnt/nix during
  # installation, so the first boot needs neither GitHub nor another download.
  printf 'Building Home Manager activation package for %s into the target store...\n' "$PROFILE"
  if ! activation_path="$(
    USER="$INSTALL_USER" HOME="/home/$INSTALL_USER" \
      nix --extra-experimental-features "nix-command flakes" \
        --store "$target_root" \
        build \
        --impure \
        --no-link \
        --print-out-paths \
        "path:$repo_dir#homeConfigurations.${PROFILE}.activationPackage"
  )"; then
    install_die "Home Manager activation package could not be built into the target store."
  fi

  [[ "$activation_path" == /nix/store/* ]] \
    || install_die "Unexpected Home Manager store path: $activation_path"
  [[ -x "$target_root$activation_path/activate" ]] \
    || install_die "Home Manager activation is missing from the target store: $activation_path/activate"

  mkdir -p "$(dirname "$pending_file")"
  printf '%s\n' "$activation_path" > "$pending_file"

  echo "Home Manager is prepared for one-time activation before the first graphical login."
}

install_set_fresh_password() {
  local target_root="$1"

  echo
  echo "Set a new password for ${INSTALL_USER}:"
  echo

  nixos-enter \
    --root "$target_root" \
    -c "passwd ${INSTALL_USER}"

  install_prepare_home_manager_target "$target_root"
}

install_prepare_repo_permissions() {
  local target_root="$1"

  # The repository root belongs to root:wheel. All existing entries receive
  # wheel as their group and group-write permissions; the NixOS module also
  # establishes persistent default ACLs on the first boot.
  nixos-enter --root "$target_root" -c '
    set -e
    chown root:wheel /etc/nixos
    chgrp -R wheel /etc/nixos
    chmod 2775 /etc/nixos
    find /etc/nixos -type d -exec chmod g+rws {} +
    find /etc/nixos -type f ! -perm /111 -exec chmod g+rw {} +
    find /etc/nixos -type f -perm /111 -exec chmod g+rwx {} +
  '
}
