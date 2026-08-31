{ config, lib, pkgs, ... }:

let
  layout = config.workstation.deployment.plasmaDisplayLayout or null;
  outputs = if layout == null then [ ] else layout.outputs or [ ];
  delaySeconds = if layout == null then 30 else layout.delaySeconds or 30;

  outputArgs = lib.concatMap (
    output:
      let
        outputId = output.id or "";
      in
      [
        "output.${outputId}.enable"
        "output.${outputId}.scale.${toString (output.scale or 1)}"
        "output.${outputId}.position.${output.position or "0,0"}"
        "output.${outputId}.priority.${toString (output.priority or 1)}"
      ]
      ++ lib.optional (output ? brightness)
        "output.${outputId}.brightness.${toString output.brightness}"
  ) outputs;

  applyDisplayLayout = pkgs.writeShellScript "hp-z2-tower-g9-display-layout" ''
    set -eu
    exec ${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor \
      ${lib.escapeShellArgs outputArgs}
  '';
in
{
  assertions = lib.optionals (layout != null) [
    {
      assertion = outputs != [ ];
      message = "deployment.json plasmaDisplayLayout.outputs must not be empty.";
    }
    {
      assertion = lib.all (output: (output.id or "") != "") outputs;
      message = "Every deployment.json plasmaDisplayLayout output must have a non-empty id.";
    }
  ];

  # Display identities, positions and scaling are deployment-specific rather
  # than properties of the HP Z2 hardware profile. Apply them only when local
  # deployment.json provides an explicit Plasma display layout.
  #
  # The default 30-second delay is intentional. Plasma must first finish its
  # initial screen/panel discovery with the login-time display state. Applying
  # the final two-monitor layout too early caused Plasma to repeatedly create
  # or migrate application bars/panels while the output topology was still
  # changing. The matching Home Manager HP profile therefore waits 35 seconds
  # before its one-time second-panel bootstrap, leaving a small margin after
  # this display-layout timer. Do not change this delay independently without
  # reviewing that ordering and the panel bootstrap together.
  systemd.user.services.hp-z2-tower-g9-display-layout = lib.mkIf (outputs != [ ]) {
    description = "Apply HP Z2 Tower G9 display layout";
    partOf = [ "graphical-session.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = applyDisplayLayout;
    };
  };

  systemd.user.timers.hp-z2-tower-g9-display-layout = lib.mkIf (outputs != [ ]) {
    description = "Delay HP Z2 Tower G9 display layout after login";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];

    timerConfig = {
      OnActiveSec = "${toString delaySeconds}s";
      AccuracySec = "1s";
      Unit = "hp-z2-tower-g9-display-layout.service";
    };
  };
}
