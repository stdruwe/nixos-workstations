#!/usr/bin/env bash

set -Eeuo pipefail

NIXOS_REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
HOME_MANAGER_REPO="${HOME_MANAGER_REPO:-$HOME/.config/home-manager}"
NIXOS_REMOTE="https://github.com/stdruwe/nixos-workstations.git"
HOME_MANAGER_REMOTE="https://github.com/stdruwe/home-manager-workstations.git"

TMP_DIR=""
MODE="main"
RELEASE_TAG=""

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
}
trap cleanup EXIT

die() {
  echo
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<EOF
Usage:
  $0 /path/to/output-directory
  $0 --release-tag vX.Y.Z[-PRERELEASE] /path/to/output-directory

Normal mode:
  Creates a portable installation package from clean, current main states of
  NixOS and Home Manager.

Release mode:
  Creates a version-bound installation package from exactly the same release
  tag in both repositories. Both checkouts must be on that tag. Examples:

    $0 --release-tag v0.1.0 ./dist
    $0 --release-tag v0.1.0-rc.1 ./dist

The package contains:
  - a clean NixOS checkout including .git
  - Home Manager as a local Git bundle under refs/heads/main
  - the tracked shared install.sh as the entry point
  - snapshot metadata with exact commit SHAs
  - a SHA-256 checksum

Default Home Manager path:
  $HOME_MANAGER_REPO

Alternative Home Manager checkout:
  HOME_MANAGER_REPO=/path/to/home-manager $0 /path/to/output-directory
EOF
}

case "$#" in
  1)
    DEST_DIR="$1"
    ;;
  3)
    [[ "$1" == "--release-tag" ]] || {
      usage
      exit 2
    }
    MODE="release"
    RELEASE_TAG="$2"
    DEST_DIR="$3"
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ "$MODE" == "release" ]]; then
  [[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]] \
    || die "Release tag must match vX.Y.Z or vX.Y.Z-PRERELEASE: $RELEASE_TAG"
fi

for command in git tar zstd sha256sum mktemp date mkdir rm chmod realpath basename grep cp; do
  command -v "$command" >/dev/null || die "Required program is missing: $command"
done

[[ -d "$NIXOS_REPO/.git" ]] || die "NixOS Git repository is missing: $NIXOS_REPO"
[[ -d "$HOME_MANAGER_REPO/.git" ]] || die "Home Manager Git repository is missing: $HOME_MANAGER_REPO"
[[ -x "$NIXOS_REPO/install.sh" ]] || die "Shared installer is missing or not executable: $NIXOS_REPO/install.sh"

mkdir -p "$DEST_DIR"
DEST_DIR="$(realpath -m -- "$DEST_DIR")"

nixos_git() {
  git -c "safe.directory=$NIXOS_REPO" -C "$NIXOS_REPO" "$@"
}

hm_git() {
  git -C "$HOME_MANAGER_REPO" "$@"
}

check_main_repo() {
  local name="$1"
  local repo_kind="$2"
  local branch
  local status
  local head
  local upstream

  if [[ "$repo_kind" == "nixos" ]]; then
    branch="$(nixos_git branch --show-current)"
    [[ "$branch" == "main" ]] || die "$name is not on main, but on ${branch:-<detached>}."

    status="$(nixos_git status --porcelain)"
    [[ -z "$status" ]] || die "$name contains uncommitted changes."

    echo "Updating $name origin/main..."
    nixos_git fetch --prune origin main

    head="$(nixos_git rev-parse HEAD)"
    upstream="$(nixos_git rev-parse origin/main)"
  else
    branch="$(hm_git branch --show-current)"
    [[ "$branch" == "main" ]] || die "$name is not on main, but on ${branch:-<detached>}."

    status="$(hm_git status --porcelain)"
    [[ -z "$status" ]] || die "$name contains uncommitted changes."

    echo "Updating $name origin/main..."
    hm_git fetch --prune origin main

    head="$(hm_git rev-parse HEAD)"
    upstream="$(hm_git rev-parse origin/main)"
  fi

  [[ "$head" == "$upstream" ]] || die "$name main is not exactly at origin/main. Update/push it first."
}

check_release_repo() {
  local name="$1"
  local repo_kind="$2"
  local status
  local head
  local tag_commit

  if [[ "$repo_kind" == "nixos" ]]; then
    status="$(nixos_git status --porcelain)"
    [[ -z "$status" ]] || die "$name contains uncommitted changes."

    echo "Checking $name release tag $RELEASE_TAG..."
    nixos_git fetch --force --prune origin \
      "refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"

    tag_commit="$(nixos_git rev-parse "refs/tags/$RELEASE_TAG^{commit}" 2>/dev/null)" \
      || die "$name does not contain a valid release tag $RELEASE_TAG."
    head="$(nixos_git rev-parse HEAD)"
  else
    status="$(hm_git status --porcelain)"
    [[ -z "$status" ]] || die "$name contains uncommitted changes."

    echo "Checking $name release tag $RELEASE_TAG..."
    hm_git fetch --force --prune origin \
      "refs/tags/$RELEASE_TAG:refs/tags/$RELEASE_TAG"

    tag_commit="$(hm_git rev-parse "refs/tags/$RELEASE_TAG^{commit}" 2>/dev/null)" \
      || die "$name does not contain a valid release tag $RELEASE_TAG."
    head="$(hm_git rev-parse HEAD)"
  fi

  [[ "$head" == "$tag_commit" ]] \
    || die "$name HEAD ($head) is not at release tag $RELEASE_TAG ($tag_commit)."
}

if [[ "$MODE" == "release" ]]; then
  check_release_repo "NixOS" nixos
  check_release_repo "Home Manager" home-manager

  NIXOS_SHA="$(nixos_git rev-parse "refs/tags/$RELEASE_TAG^{commit}")"
  HM_SHA="$(hm_git rev-parse "refs/tags/$RELEASE_TAG^{commit}")"
  BASE="nixos-install-${RELEASE_TAG}"
else
  check_main_repo "NixOS" nixos
  check_main_repo "Home Manager" home-manager

  NIXOS_SHA="$(nixos_git rev-parse HEAD)"
  HM_SHA="$(hm_git rev-parse HEAD)"
  NIXOS_SHORT="$(nixos_git rev-parse --short=8 HEAD)"
  HM_SHORT="$(hm_git rev-parse --short=8 HEAD)"
  STAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
  BASE="nixos-install-${STAMP}-${NIXOS_SHORT}-${HM_SHORT}"
fi

CREATED="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ARCHIVE="$DEST_DIR/${BASE}.tar.zst"
CHECKSUM="${ARCHIVE}.sha256"

[[ ! -e "$ARCHIVE" && ! -e "$CHECKSUM" ]] || die "Output file already exists: $ARCHIVE"

TMP_DIR="$(mktemp -d /tmp/nixos-install-package.XXXXXX)"
PACKAGE_DIR="$TMP_DIR/nixos-install"
NIXOS_PACKAGE_REPO="$PACKAGE_DIR/nixos"
HM_BUNDLE_REPO="$TMP_DIR/home-manager-bundle-source"
mkdir -p "$PACKAGE_DIR"

echo
if [[ "$MODE" == "release" ]]; then
  echo "Creating clean NixOS checkout for $RELEASE_TAG..."
else
  echo "Creating clean NixOS main checkout..."
fi

git clone --quiet --no-local --no-checkout "$NIXOS_REPO" "$NIXOS_PACKAGE_REPO"
git -C "$NIXOS_PACKAGE_REPO" checkout --quiet -B main "$NIXOS_SHA"
git -C "$NIXOS_PACKAGE_REPO" remote set-url origin "$NIXOS_REMOTE"
git -C "$NIXOS_PACKAGE_REPO" config branch.main.remote origin
git -C "$NIXOS_PACKAGE_REPO" config branch.main.merge refs/heads/main

[[ "$(git -C "$NIXOS_PACKAGE_REPO" rev-parse HEAD)" == "$NIXOS_SHA" ]] \
  || die "NixOS snapshot does not match the verified state."
[[ "$(git -C "$NIXOS_PACKAGE_REPO" branch --show-current)" == "main" ]] \
  || die "NixOS package checkout is not on the expected local main branch."
[[ -z "$(git -C "$NIXOS_PACKAGE_REPO" status --porcelain)" ]] \
  || die "NixOS package checkout is unexpectedly dirty."

if [[ "$MODE" == "release" ]]; then
  echo "Creating Home Manager bundle for $RELEASE_TAG as refs/heads/main..."
  git clone --quiet --no-local --no-checkout "$HOME_MANAGER_REPO" "$HM_BUNDLE_REPO"
  git -C "$HM_BUNDLE_REPO" checkout --quiet -B main "$HM_SHA"
  git -C "$HM_BUNDLE_REPO" bundle create "$PACKAGE_DIR/home-manager.bundle" refs/heads/main
else
  echo "Creating Home Manager main bundle..."
  hm_git bundle create "$PACKAGE_DIR/home-manager.bundle" refs/heads/main
fi

git -C "$PACKAGE_DIR" init -q
if ! git -C "$PACKAGE_DIR" bundle verify "$PACKAGE_DIR/home-manager.bundle" >/dev/null 2>&1; then
  die "Generated Home Manager bundle is invalid."
fi
rm -rf "$PACKAGE_DIR/.git"

if ! git bundle list-heads "$PACKAGE_DIR/home-manager.bundle" refs/heads/main \
  | grep -q "^${HM_SHA} refs/heads/main$"; then
  die "Home Manager bundle does not contain verified state $HM_SHA as refs/heads/main."
fi

if [[ "$MODE" == "release" ]]; then
  cat > "$PACKAGE_DIR/INSTALL-SNAPSHOT.txt" <<EOF
Release:                 $RELEASE_TAG
NixOS repository:        $NIXOS_REMOTE
NixOS ref:               refs/tags/$RELEASE_TAG
NixOS commit:            $NIXOS_SHA
Home Manager repository: $HOME_MANAGER_REMOTE
Home Manager ref:        refs/tags/$RELEASE_TAG
Home Manager commit:     $HM_SHA
Created:                 $CREATED

This installation package was created from the matching release tags
$RELEASE_TAG in both repositories. The local NixOS checkout in the package is
intentionally on branch main at the release commit so later updates can
continue normally through origin/main.

The Home Manager bundle is transport material for the fresh installation only.
It is not copied into /etc/nixos.
EOF
else
  cat > "$PACKAGE_DIR/INSTALL-SNAPSHOT.txt" <<EOF
NixOS repository:        $NIXOS_REMOTE
NixOS ref:               refs/heads/main
NixOS commit:            $NIXOS_SHA
Home Manager repository: $HOME_MANAGER_REMOTE
Home Manager ref:        refs/heads/main
Home Manager commit:     $HM_SHA
Created:                 $CREATED

The Home Manager bundle is transport material for the fresh installation only.
It is not copied into /etc/nixos.
EOF
fi

# A single tracked dispatcher is used both in the normal repository and in the
# portable package as the user-facing entry point. This prevents profile-
# specific arguments (target disk or --layout-check) from getting lost between
# diverging dispatcher implementations.
cp "$NIXOS_PACKAGE_REPO/install.sh" "$PACKAGE_DIR/install.sh"
chmod 0755 "$PACKAGE_DIR/install.sh"

echo "Packing installation directory..."
tar -C "$TMP_DIR" -cf - nixos-install \
  | zstd -10 -T0 --quiet --force -o "$ARCHIVE"

(
  cd "$DEST_DIR"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$CHECKSUM")"
)

echo
echo "============================================================"
echo " Installation package created"
echo "============================================================"
echo "Archive:     $ARCHIVE"
echo "Checksum:    $CHECKSUM"
if [[ "$MODE" == "release" ]]; then
  echo "Release:     $RELEASE_TAG"
fi
echo "NixOS:       $NIXOS_SHA"
echo "HomeMgr:     $HM_SHA"
echo
echo "On the live system:"
echo "  sha256sum -c $(basename "$CHECKSUM")"
echo "  tar --zstd -xf $(basename "$ARCHIVE")"
echo "  cd nixos-install"
echo "  sudo ./install.sh <hardware-profile> [profile-option]"
