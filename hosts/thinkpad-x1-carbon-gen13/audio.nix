{ pkgs, ... }:

let
  easyeffectsConfig = ../../audio/easyeffects;
  localOutput = ../../audio/easyeffects/local/output;
  localIrs = ../../audio/easyeffects/local/irs;
  localOverride = ../../audio/easyeffects/local/override/Dolby-Dynamic-Balanced.json;

  localTuningAvailable =
    builtins.pathExists localOutput && builtins.pathExists localIrs;
  localOverrideAvailable = builtins.pathExists localOverride;

  startEasyEffects = pkgs.writeShellScript "start-easyeffects" ''
    set -eu

    DATA_DIR="$HOME/.local/share/easyeffects"
    CONFIG_DIR="$HOME/.config/easyeffects/db"

    mkdir -p \
      "$DATA_DIR/output" \
      "$DATA_DIR/irs" \
      "$DATA_DIR/autoload/output" \
      "$CONFIG_DIR"

    # Dolby-labelled presets and IRS files are a managed local set. Remove
    # previous runtime copies first so files removed from the generated source
    # do not survive indefinitely in the EasyEffects user directory.
    rm -f \
      "$DATA_DIR/output"/Dolby-*.json \
      "$DATA_DIR/irs"/Dolby-*.irs

    # The generic bypass preset is repository-owned configuration and remains
    # available even when local ThinkPad tuning has not been generated yet.
    ${pkgs.coreutils}/bin/install -m 0644 \
      ${easyeffectsConfig}/output/Nothing.json \
      "$DATA_DIR/output/Nothing.json"

    ${if localTuningAvailable then ''
      # All generator-produced Dolby presets and IRS files stay machine-local.
      ${pkgs.coreutils}/bin/install -m 0644 \
        ${localOutput}/*.json \
        "$DATA_DIR/output/"

      ${pkgs.coreutils}/bin/install -m 0644 \
        ${localIrs}/*.irs \
        "$DATA_DIR/irs/"

      ${if localOverrideAvailable then ''
        # A user-adjusted default can be saved locally without entering Git.
        ${pkgs.coreutils}/bin/install -m 0644 \
          ${localOverride} \
          "$DATA_DIR/output/Dolby-Dynamic-Balanced.json"
      '' else ''
        :
      ''}
    '' else ''
      :
    ''}

    # The tracked autoload rule selects Dolby-Dynamic-Balanced. Only install
    # it when the complete local tuning exists; a clean clone without the OEM
    # source must still start EasyEffects without a broken convolver preset.
    rm -f "$DATA_DIR/autoload/output"/*.json
    ${if localTuningAvailable then ''
      ${pkgs.coreutils}/bin/install -m 0644 \
        ${easyeffectsConfig}/autoload/output/*.json \
        "$DATA_DIR/autoload/output/"
    '' else ''
      :
    ''}

    if [ ! -e "$CONFIG_DIR/easyeffectsrc" ]; then
      ${pkgs.coreutils}/bin/install -m 0644 \
        ${easyeffectsConfig}/db/easyeffectsrc \
        "$CONFIG_DIR/easyeffectsrc"
    fi

    exec ${pkgs.easyeffects}/bin/easyeffects \
      --service-mode \
      --hide-window
  '';
in
{
  environment.etc."xdg/autostart/easyeffects-nixos.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=EasyEffects
    Comment=Audio effects for the internal ThinkPad speakers
    Exec=${startEasyEffects}
    OnlyShowIn=KDE;
    NoDisplay=true
    X-KDE-autostart-after=panel
  '';
}
