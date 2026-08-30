{ config, lib, pkgs, ... }:

let
  homeDirectory = config.workstation.homeDirectory;

  # The running guard must notice when either its orchestration or the actual
  # Topgrade configuration changed in /etc/nixos during the repository sync.
  # Hashing the source text makes this independent of Git metadata and also
  # survives a failed first rebuild: the old guard keeps its old embedded hash.
  topgradeDefinitionHash = builtins.hashString "sha256" (
    builtins.readFile ../../topgrade.nix
    + "\n-- topgrade guard --\n"
    + builtins.readFile ./topgrade-guard.nix
  );

  topgradeGuard = pkgs.writeShellScriptBin "topgrade" ''
    set -euo pipefail

    # Keep Topgrade and every subprocess it starts in English even when the
    # interactive desktop/session locale is German. Other locale categories
    # remain untouched so this changes messages only.
    export LC_MESSAGES=C.UTF-8
    export LANGUAGE=en

    realTopgrade=${pkgs.topgrade}/bin/topgrade
    configFile=${lib.escapeShellArg "${homeDirectory}/.config/topgrade.toml"}
    embeddedDefinitionHash=${lib.escapeShellArg topgradeDefinitionHash}

    # Keep special/step-selecting invocations exactly compatible with upstream
    # Topgrade. The guarded two-phase path is used for the normal `topgrade`
    # command and for verbose diagnostics only.
    guarded=1
    for arg in "$@"; do
      case "$arg" in
        -v)
          ;;
        *)
          guarded=0
          ;;
      esac
    done

    if [ "$guarded" != "1" ]; then
      exec "$realTopgrade" "$@"
    fi

    if [ ! -r "$configFile" ]; then
      echo "Topgrade configuration is not readable: $configFile" >&2
      exit 1
    fi

    definition_hash() {
      if [ ! -r /etc/nixos/topgrade.nix ] \
        || [ ! -r /etc/nixos/modules/common/topgrade-guard.nix ]; then
        echo "Cannot read the Topgrade definition below /etc/nixos." >&2
        return 1
      fi

      {
        ${pkgs.coreutils}/bin/cat /etc/nixos/topgrade.nix
        printf '\n-- topgrade guard --\n'
        ${pkgs.coreutils}/bin/cat /etc/nixos/modules/common/topgrade-guard.nix
      } | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d ' ' -f 1
    }

    strip_section() {
      inputFile="$1"
      section="$2"
      outputFile="$3"

      ${pkgs.gawk}/bin/awk -v target="[$section]" '
        $0 == target {
          skipping = 1
          next
        }
        skipping && /^\[[^]]+\][[:space:]]*$/ {
          skipping = 0
        }
        !skipping {
          print
        }
      ' "$inputFile" > "$outputFile"
    }

    tempDir="$(${pkgs.coreutils}/bin/mktemp -d)"
    trap '${pkgs.coreutils}/bin/rm -rf "$tempDir"' EXIT

    phaseOneConfig="$tempDir/phase-one.toml"
    continuationConfig="$tempDir/continuation.toml"

    # Phase 1 keeps Topgrade's existing pre_commands and native NixOS System
    # updater, but deliberately suppresses post_commands until the full run is
    # known to be safe to continue.
    strip_section "$configFile" post_commands "$phaseOneConfig"

    "$realTopgrade" --config "$phaseOneConfig" --only system "$@"

    currentDefinitionHash="$(definition_hash)"
    if [ "$currentDefinitionHash" != "$embeddedDefinitionHash" ]; then
      printf '\nTopgrade itself was updated by the Git/system upgrade.\n'
      printf 'The new NixOS generation is active; this run stops here instead of\n'
      printf 'continuing with the old Topgrade logic. Run `topgrade` again so the\n'
      printf 'entire update starts cleanly with the newly activated version.\n'
      exit 0
    fi

    # Phase 2 uses the current configuration, skips the already completed
    # repository-preparation and System steps, and runs Home Manager plus all
    # remaining normal Topgrade steps and post_commands.
    strip_section "$configFile" pre_commands "$continuationConfig"
    exec "$realTopgrade" --config "$continuationConfig" --disable system "$@"
  '';
in
{
  # topgrade.nix still installs the upstream binary. Giving the guard a higher
  # Nix profile priority resolves the deliberate bin/topgrade collision in
  # favour of this wrapper while keeping the upstream binary available through
  # its immutable store path above.
  environment.systemPackages = [ (lib.hiPrio topgradeGuard) ];
}
