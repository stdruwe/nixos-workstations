{ config, lib, pkgs, ... }:

let
  userName = config.workstation.userName;
  homeDirectory = config.workstation.homeDirectory;
  homeManagerDir = "${homeDirectory}/.config/home-manager";
  homeManagerProfile = config.workstation.profile;
  localSourcesDir = "/etc/nixos/.local-sources";

  updateManagedDependenciesRaw =
    lib.attrByPath [ "topgrade" "updateManagedDependencies" ] true config.workstation.deployment;
  updateManagedDependencies =
    if builtins.isBool updateManagedDependenciesRaw then
      updateManagedDependenciesRaw
    else
      throw "deployment.json topgrade.updateManagedDependencies must be a boolean";

  updateFileBotSource = pkgs.writeShellScript "update-filebot-source" ''
    set -euo pipefail

    sourceFile=${lib.escapeShellArg "${localSourcesDir}/filebot-source.nix"}

    echo "Checking current FileBot release..."

    version="$(${pkgs.curl}/bin/curl \
      -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 2 \
      --retry-delay 2 \
      --retry-all-errors \
      https://www.filebot.net/download.html \
      | ${pkgs.gnugrep}/bin/grep -oE 'FileBot_[0-9]+\.[0-9]+\.[0-9]+_amd64\.deb' \
      | ${pkgs.coreutils}/bin/sort -Vu \
      | ${pkgs.coreutils}/bin/tail -n 1 \
      | ${pkgs.gnused}/bin/sed -E 's/^FileBot_([0-9.]+)_amd64\.deb$/\1/')"

    if ! printf '%s\n' "$version" | ${pkgs.gnugrep}/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "Could not determine the current stable FileBot version." >&2
      exit 1
    fi

    checksumUrl="https://raw.githubusercontent.com/filebot/website/master/get.filebot.net/filebot/FileBot_"$version"/FileBot_"$version"_amd64.deb.sha256"
    sha256="$(${pkgs.curl}/bin/curl \
      -fsSL \
      --connect-timeout 10 \
      --max-time 60 \
      --retry 2 \
      --retry-delay 2 \
      --retry-all-errors \
      "$checksumUrl" \
      | ${pkgs.coreutils}/bin/tr -d '[:space:]')"

    if ! printf '%s\n' "$sha256" | ${pkgs.gnugrep}/bin/grep -Eq '^[0-9a-fA-F]{64}$'; then
      echo "Invalid SHA-256 checksum returned for FileBot $version." >&2
      exit 1
    fi

    currentVersion="$(${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*version = "\([^"]*\)";/\1/p' "$sourceFile")"
    currentSha256="$(${pkgs.gnused}/bin/sed -n 's/^[[:space:]]*sha256 = "\([^"]*\)";/\1/p' "$sourceFile")"

    if [ "$currentVersion" = "$version" ] && [ "$currentSha256" = "$sha256" ]; then
      echo "FileBot $version is already current."
      exit 0
    fi

    printf '{\n  version = "%s";\n  sha256 = "%s";\n}\n' "$version" "$sha256" > "$sourceFile.tmp"
    mv "$sourceFile.tmp" "$sourceFile"

    echo "Prepared local FileBot update: $currentVersion -> $version"
  '';

  # Home Manager refuses to replace pre-existing unmanaged files. During a
  # declarative migration that is correct but otherwise turns an ordinary
  # Topgrade run into a manual recovery exercise. Keep the safety check, but
  # move the old file losslessly into a unique state-directory backup instead
  # of deleting it or using a fixed .backup suffix that can collide again.
  homeManagerCollisionBackup = pkgs.writeShellScript "home-manager-topgrade-backup" ''
    set -euo pipefail

    if [ "$#" -ne 1 ]; then
      echo "Expected exactly one Home Manager collision path, got $#." >&2
      exit 2
    fi

    sourcePath="$1"
    home=${lib.escapeShellArg homeDirectory}
    backupBase=${lib.escapeShellArg "${homeDirectory}/.local/state/home-manager-backups"}

    case "$sourcePath" in
      "$home"/*)
        ;;
      *)
        echo "Refusing to move Home Manager collision outside $home: $sourcePath" >&2
        exit 1
        ;;
    esac

    if [ ! -e "$sourcePath" ] && [ ! -L "$sourcePath" ]; then
      exit 0
    fi

    relativePath="''${sourcePath#"$home"/}"
    runId="$(${pkgs.coreutils}/bin/date +%Y%m%d-%H%M%S)-$PPID"
    backupRoot="$backupBase/$runId"
    destination="$backupRoot/$relativePath"
    counter=0

    while [ -e "$destination" ] || [ -L "$destination" ]; do
      counter=$((counter + 1))
      destination="$backupRoot/$relativePath.$counter"
    done

    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$destination")"
    ${pkgs.coreutils}/bin/mv -- "$sourcePath" "$destination"

    printf 'Home Manager: backed up unmanaged collision\n  %s\n  -> %s\n' \
      "$sourcePath" "$destination"
  '';

  prepareConfig = pkgs.writeShellScript "topgrade-prepare-config" ''
    set -euo pipefail

    bitwardenSocket=${lib.escapeShellArg "${homeDirectory}/.bitwarden-ssh-agent.sock"}
    if [ -S "$bitwardenSocket" ]; then
      export SSH_AUTH_SOCK="$bitwardenSocket"
    fi

    export GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o ConnectionAttempts=1 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"

    localSourcesDir=${lib.escapeShellArg localSourcesDir}
    homeManagerDir=${lib.escapeShellArg homeManagerDir}
    homeManagerProfile=${lib.escapeShellArg homeManagerProfile}
    nixosCandidateLog=${lib.escapeShellArg "${homeDirectory}/.local/state/topgrade/nixos-candidate.log"}
    nixosCandidateChecked=0
    nixosCandidateBuildable=0

    retry_network() {
      description="$1"
      shift
      maxAttempts=3
      attempt=1

      while true; do
        if "$@"; then
          return 0
        else
          status=$?
        fi

        if [ "$attempt" -ge "$maxAttempts" ]; then
          echo "$description failed after $attempt attempts." >&2
          return "$status"
        fi

        echo "$description failed (attempt $attempt/$maxAttempts); retrying in 2 seconds..." >&2
        ${pkgs.coreutils}/bin/sleep 2
        attempt=$((attempt + 1))
      done
    }

    sync_repo() {
      repo="$1"
      echo "Updating $repo from its configured upstream..."
      retry_network "Git pull for $repo" \
        ${pkgs.git}/bin/git -C "$repo" pull --ff-only
    }

    lock_sha256() {
      ${pkgs.coreutils}/bin/sha256sum "$1" | ${pkgs.coreutils}/bin/cut -d ' ' -f 1
    }

    ensure_local_nixos_sources() {
      ${pkgs.coreutils}/bin/mkdir -p "$localSourcesDir"

      if [ ! -f "$localSourcesDir/lon.lock" ]; then
        ${pkgs.coreutils}/bin/cp /etc/nixos/lon.lock "$localSourcesDir/lon.lock"
      fi
      if [ ! -f "$localSourcesDir/lon.nix" ]; then
        ${pkgs.coreutils}/bin/cp /etc/nixos/lon.nix "$localSourcesDir/lon.nix"
      fi
      if [ ! -f "$localSourcesDir/filebot-source.nix" ]; then
        ${pkgs.coreutils}/bin/cp /etc/nixos/pkgs/filebot-source.nix "$localSourcesDir/filebot-source.nix"
      fi
    }

    ensure_local_home_manager_lock() {
      if [ -f "$homeManagerDir/flake.lock" ]; then
        return 0
      fi

      if [ ! -f "$homeManagerDir/flake.lock.bootstrap" ]; then
        echo "Home Manager bootstrap lock is missing: $homeManagerDir/flake.lock.bootstrap" >&2
        exit 1
      fi

      ${pkgs.coreutils}/bin/cp "$homeManagerDir/flake.lock.bootstrap" "$homeManagerDir/flake.lock"
      echo "Created machine-local Home Manager flake.lock from the bootstrap lock."
    }

    print_nixos_failure_excerpt() {
      if [ ! -s "$nixosCandidateLog" ]; then
        return 0
      fi

      relevant="$(${pkgs.gnugrep}/bin/grep -E 'Hunk .*FAILED|out of .* hunks FAILED|saving rejects' "$nixosCandidateLog" \
        | ${pkgs.coreutils}/bin/head -n 4 || true)"

      if [ -z "$relevant" ]; then
        relevant="$(${pkgs.gnugrep}/bin/grep -E 'builder failed|error:.*Cannot build|error: build of' "$nixosCandidateLog" \
          | ${pkgs.coreutils}/bin/tail -n 6 || true)"
      fi

      if [ -n "$relevant" ]; then
        printf '  Relevant build failure:\n'
        printf '%s\n' "$relevant" | ${pkgs.gnused}/bin/sed 's/^/    /'
      fi
    }

    report_nixos_update_skipped() {
      reason="$1"
      printf '\nNixOS system update: SKIPPED\n'
      printf '  Reason: %s\n' "$reason"
      printf '  The installed NixOS channel and active system remain unchanged.\n'
      printf '  Topgrade continues with Home Manager and the remaining updates.\n'
      print_nixos_failure_excerpt
      if [ -s "$nixosCandidateLog" ]; then
        printf '  Full build log: %s\n' "$nixosCandidateLog"
      fi
      printf '\n'
    }

    validate_nixos_profile() {
      echo "Building $homeManagerProfile against current nixos-unstable before upgrade..."
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$nixosCandidateLog")"
      nixosCandidateChecked=1

      if ${pkgs.nix}/bin/nix-build \
        '<nixpkgs/nixos>' \
        --attr config.system.build.toplevel \
        --no-out-link \
        -I nixpkgs=channel:nixos-unstable \
        -I "nixos-config=/etc/nixos/hosts/$homeManagerProfile/default.nix" \
        >"$nixosCandidateLog" 2>&1; then
        nixosCandidateBuildable=1
        echo "NixOS candidate build succeeded."
        return 0
      fi

      nixosCandidateBuildable=0
      return 1
    }

    validate_home_manager_profile() {
      lockFile="$1"
      echo "Validating updated local Home Manager inputs for $homeManagerProfile..."
      USER=${lib.escapeShellArg userName} HOME=${lib.escapeShellArg homeDirectory} \
        ${pkgs.nix}/bin/nix build \
          --impure \
          --no-link \
          --no-update-lock-file \
          --no-write-lock-file \
          --reference-lock-file "$lockFile" \
          "path:$homeManagerDir#homeConfigurations.\"$homeManagerProfile\".activationPackage"
    }

    local_nixos_sources_changed() {
      backupDir="$1"
      ! ${pkgs.diffutils}/bin/cmp -s "$backupDir/lon.lock" "$localSourcesDir/lon.lock" \
        || ! ${pkgs.diffutils}/bin/cmp -s "$backupDir/lon.nix" "$localSourcesDir/lon.nix" \
        || ! ${pkgs.diffutils}/bin/cmp -s "$backupDir/filebot-source.nix" "$localSourcesDir/filebot-source.nix"
    }

    restore_local_nixos_sources() {
      backupDir="$1"
      ${pkgs.coreutils}/bin/cp "$backupDir/lon.lock" "$localSourcesDir/lon.lock"
      ${pkgs.coreutils}/bin/cp "$backupDir/lon.nix" "$localSourcesDir/lon.nix"
      ${pkgs.coreutils}/bin/cp "$backupDir/filebot-source.nix" "$localSourcesDir/filebot-source.nix"
      ${pkgs.coreutils}/bin/rm -rf "$backupDir"
    }

    run_lon_update() {
      set +e
      lonOutput="$(cd "$localSourcesDir" && ${pkgs.lon}/bin/lon update 2>&1)"
      lonStatus=$?
      set -e

      if [ "$lonStatus" -eq 1 ] && printf '%s\n' "$lonOutput" | ${pkgs.gnugrep}/bin/grep -qx 'No updates available'; then
        lonStatus=0
      fi
    }

    update_local_nixos_sources() {
      backupDir="$(${pkgs.coreutils}/bin/mktemp -d)"
      ${pkgs.coreutils}/bin/cp "$localSourcesDir/lon.lock" "$backupDir/lon.lock"
      ${pkgs.coreutils}/bin/cp "$localSourcesDir/lon.nix" "$backupDir/lon.nix"
      ${pkgs.coreutils}/bin/cp "$localSourcesDir/filebot-source.nix" "$backupDir/filebot-source.nix"

      if ! ${updateFileBotSource}; then
        restore_local_nixos_sources "$backupDir"
        return 1
      fi

      run_lon_update

      if [ "$lonStatus" -ne 0 ] && ! local_nixos_sources_changed "$backupDir"; then
        echo "lon update failed without changing local managed files; retrying once..." >&2
        ${pkgs.coreutils}/bin/sleep 2
        run_lon_update
      fi

      printf '%s\n' "$lonOutput"

      if [ "$lonStatus" -ne 0 ]; then
        restore_local_nixos_sources "$backupDir"
        return "$lonStatus"
      fi

      if ! local_nixos_sources_changed "$backupDir"; then
        echo "Local NixOS managed sources are already current."
        if ! validate_nixos_profile; then
          ${pkgs.coreutils}/bin/rm -rf "$backupDir"
          return 1
        fi
        ${pkgs.coreutils}/bin/rm -rf "$backupDir"
        echo "Current NixOS profile builds successfully against current nixos-unstable."
        return 0
      fi

      if ! validate_nixos_profile; then
        echo "Updated local NixOS sources failed the full system build; restoring the previous machine-local state." >&2
        restore_local_nixos_sources "$backupDir"
        nixosCandidateChecked=0
        nixosCandidateBuildable=0
        return 1
      fi

      ${pkgs.coreutils}/bin/rm -rf "$backupDir"
      echo "Installed fully built machine-local NixOS source updates."
    }

    update_local_home_manager_lock() {
      candidateDir="$(${pkgs.coreutils}/bin/mktemp -d)"
      candidateLock="$candidateDir/flake.lock"

      update_home_manager_candidate() {
        ${pkgs.coreutils}/bin/rm -f "$candidateLock"
        ${pkgs.nix}/bin/nix flake update \
          --flake "path:$homeManagerDir" \
          --reference-lock-file "$homeManagerDir/flake.lock" \
          --output-lock-file "$candidateLock"
      }

      if ! retry_network "Updating machine-local Home Manager flake inputs" update_home_manager_candidate; then
        ${pkgs.coreutils}/bin/rm -rf "$candidateDir"
        return 1
      fi

      currentLockSha="$(lock_sha256 "$homeManagerDir/flake.lock")"
      candidateLockSha="$(lock_sha256 "$candidateLock")"

      if [ "$currentLockSha" = "$candidateLockSha" ]; then
        echo "Machine-local Home Manager flake inputs are already current."
        ${pkgs.coreutils}/bin/rm -rf "$candidateDir"
        return 0
      fi

      if ! validate_home_manager_profile "$candidateLock"; then
        echo "Updated Home Manager inputs failed validation; keeping the previous machine-local lock." >&2
        ${pkgs.coreutils}/bin/rm -rf "$candidateDir"
        return 1
      fi

      ${pkgs.coreutils}/bin/cp "$candidateLock" "$homeManagerDir/flake.lock.topgrade-new"
      ${pkgs.coreutils}/bin/mv "$homeManagerDir/flake.lock.topgrade-new" "$homeManagerDir/flake.lock"
      ${pkgs.coreutils}/bin/rm -rf "$candidateDir"
      echo "Installed validated machine-local Home Manager flake inputs."
    }

    update_nixos_system() {
      if [ "$nixosCandidateChecked" -ne 1 ]; then
        if ! validate_nixos_profile; then
          report_nixos_update_skipped "The current candidate for $homeManagerProfile does not build against nixos-unstable."
          return 0
        fi
      elif [ "$nixosCandidateBuildable" -ne 1 ]; then
        report_nixos_update_skipped "The current candidate for $homeManagerProfile does not build against nixos-unstable."
        return 0
      fi

      echo "NixOS candidate is buildable; updating the installed root channel..."
      if ! /run/wrappers/bin/sudo ${pkgs.nix}/bin/nix-channel --update; then
        report_nixos_update_skipped "The installed NixOS channel could not be updated."
        return 0
      fi

      echo "Verifying the updated installed channel before activation..."
      if ! /run/wrappers/bin/sudo ${pkgs.nix}/bin/nix-build \
        '<nixpkgs/nixos>' \
        --attr config.system.build.toplevel \
        --no-out-link \
        -I "nixos-config=/etc/nixos/hosts/$homeManagerProfile/default.nix"; then
        echo "Updated root channel failed verification; rolling it back..." >&2
        if /run/wrappers/bin/sudo ${pkgs.nix}/bin/nix-channel --rollback; then
          report_nixos_update_skipped "The updated channel failed the second build verification and was rolled back automatically."
          return 0
        fi

        echo "NixOS channel rollback failed; stopping Topgrade to avoid an unknown channel state." >&2
        return 1
      fi

      echo "Activating the verified NixOS update..."
      if ! /run/wrappers/bin/sudo /run/current-system/sw/bin/nixos-rebuild switch; then
        echo "NixOS activation failed; attempting to roll back the root channel..." >&2
        if ! /run/wrappers/bin/sudo ${pkgs.nix}/bin/nix-channel --rollback; then
          echo "NixOS channel rollback also failed; manual recovery is required." >&2
        fi
        return 1
      fi

      printf '\nNixOS system update: OK\n\n'
    }

    sync_repo /etc/nixos
    sync_repo "$homeManagerDir"

    ensure_local_nixos_sources
    ensure_local_home_manager_lock

    if [ ${lib.escapeShellArg (if updateManagedDependencies then "1" else "0")} = "1" ]; then
      if ! update_local_nixos_sources; then
        echo "Machine-local NixOS dependency update was not accepted; continuing with the previous local source state." >&2
      fi

      if ! update_local_home_manager_lock; then
        echo "Home Manager input update failed; keeping the previous machine-local lock and continuing." >&2
      fi
    else
      echo "Machine-local managed dependency updates are disabled by deployment.json."
    fi

    update_nixos_system
  '';

  nixosNeedsReboot = pkgs.callPackage ./pkgs/nixos-needsreboot.nix { };

  checkReboot = pkgs.writeShellScript "topgrade-check-reboot" ''
    set +e
    output="$(${nixosNeedsReboot}/bin/nixos-needsreboot --dry-run 2>&1)"
    status=$?
    set -e

    case "$status" in
      0)
        printf 'Reboot required: no\n'
        ;;
      2)
        printf 'Reboot required: yes\n'
        if [ -n "$output" ]; then
          printf '%s\n' "$output"
        fi
        ;;
      *)
        printf '%s\n' "$output" >&2
        exit "$status"
        ;;
    esac
  '';

  topgradeConfig = pkgs.writeText "topgrade.toml" ''
    [misc]
    disable = ["nix", "system"]
    no_self_update = true
    nix_handler = "vanilla"
    pre_sudo = true
    show_skipped = false
    cleanup = false
    notify_end = "on_failure"

    [pre_commands]
    "Sync configuration repositories and update local dependencies" = "${prepareConfig}"

    [post_commands]
    ${lib.optionalString (config.workstation.profile == "hp-z2-tower-g9") ''
    "Update ESPHome remote-build container" = "/run/wrappers/bin/sudo ${pkgs.systemd}/bin/systemctl start esphome-container-update.service"
    ''}
    "Check whether NixOS needs reboot" = "${checkReboot}"

    [linux]
    home_manager_arguments = [
      "--impure",
      "-B",
      "${homeManagerCollisionBackup}",
      "--flake",
      "path:${homeManagerDir}#${homeManagerProfile}",
    ]

    [git]
    pull_predefined = false

    [firmware]
    upgrade = false
  '';
in
{
  environment.systemPackages = with pkgs; [
    topgrade
    lon
  ];

  systemd.tmpfiles.rules = [
    "d ${homeDirectory}/.config 0755 ${userName} users -"
    "L+ ${homeDirectory}/.config/topgrade.toml - - - - ${topgradeConfig}"
  ];
}
