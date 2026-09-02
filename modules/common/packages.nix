{ config, pkgs, ... }:

let
  isHpZ2 = config.workstation.profile == "hp-z2-tower-g9";
  localSources = ../../.local-sources/lon.nix;
  sources = import (if builtins.pathExists localSources then localSources else ../../lon.nix);

  btopPackage = pkgs.btop.override {
    rocmSupport = isHpZ2;
  };

  powertop216 = pkgs.callPackage ../../pkgs/powertop-2.16.nix { };
  filebotOfficial = pkgs.callPackage ../../pkgs/filebot-official.nix { };
  nixosNeedsReboot = pkgs.callPackage ../../pkgs/nixos-needsreboot.nix { };

  zenSourceData = builtins.fromJSON (builtins.readFile "${sources.zen-browser}/sources.json");
  zenVariant = zenSourceData.variants.beta.${pkgs.stdenv.hostPlatform.system};
  zenUnwrapped = pkgs.callPackage "${sources.zen-browser}/package.nix" {
    name = "beta";
    variant = zenVariant;
  };
  zenBrowser = pkgs.wrapFirefox zenUnwrapped {
    icon = "zen-browser";
  };

  # Bitwarden prefers memfd_secret for its in-memory key container on Linux.
  # The kernel deliberately disables hibernation while secret memory exists,
  # which also prevents suspend-then-hibernate. Force Bitwarden to use its
  # supported keyctl backend instead; the workstation swap lives inside LUKS2.
  bitwardenDesktop = pkgs.symlinkJoin {
    name = "bitwarden-desktop-keyctl";
    paths = [ pkgs.bitwarden-desktop ];
    nativeBuildInputs = [ pkgs.makeWrapper ];

    postBuild = ''
      wrapProgram "$out/bin/bitwarden" \
        --set SECURE_KEY_CONTAINER_BACKEND keyctl
    '';
  };

  # Keep Threema on the phone-bound Threema Web architecture instead of the
  # legacy Desktop 1.x package or the independent Desktop 2.x multi-device
  # client. Chromium runs it as an isolated app with its own persistent profile,
  # so Threema session data is not shared with the user's normal browsers.
  threemaWebLauncher = pkgs.writeShellScriptBin "threema-web" ''
    exec ${pkgs.chromium}/bin/chromium \
      --app=https://web.threema.ch/ \
      --user-data-dir="$HOME/.local/share/threema-web/chromium" \
      --no-first-run \
      --no-default-browser-check \
      "$@"
  '';

  threemaWebDesktop = pkgs.makeDesktopItem {
    name = "threema-web";
    desktopName = "Threema Web";
    genericName = "Instant Messenger";
    comment = "Threema Web in an isolated Chromium profile";
    exec = "threema-web";
    icon = "web-browser";
    categories = [
      "Network"
      "InstantMessaging"
    ];
  };

  threemaWeb = pkgs.symlinkJoin {
    name = "threema-web";
    paths = [
      threemaWebLauncher
      threemaWebDesktop
    ];
  };
in
{
  nixpkgs.config.allowUnfree = true;

  # btop upstream uses Linux perf events for Intel GPU statistics and CPU power
  # monitoring. Grant only CAP_PERFMON to the wrapped executable instead of
  # running btop as root or broadening it to CAP_SYS_ADMIN/CAP_DAC_READ_SEARCH.
  # Direct Intel RAPL energy_uj access is handled separately and more narrowly
  # through the powercap group in modules/common/rapl-access.nix. Preserve this
  # split unless the relevant btop monitors have been retested unprivileged;
  # see docs/operational-invariants.md.
  security.wrappers.btop = {
    source = "${btopPackage}/bin/btop";
    owner = "root";
    group = "root";
    capabilities = "cap_perfmon+ep";
  };

  environment.systemPackages =
    (with pkgs; [
      curl
      wget
      nano
      tmux
      mc
      gh
      htop
      btopPackage
      fastfetch

      # General command-line and file-management tools.
      jq
      yq-go
      ripgrep
      fd
      bat
      eza
      tree
      rsync
      rclone
      pv
      git-lfs

      # Nix/NixOS inspection tools.
      nvd
      nix-tree
      nix-diff

      pciutils
      usbutils
      ethtool
      iw
      nvme-cli
      powertop216
      nixosNeedsReboot
      libva-utils
      efibootmgr
      bash-language-server
      shellcheck
      shfmt
      smartmontools
      intel-gpu-tools
      nixd
      nixfmt
      mpv
      plezy
      zenBrowser
      bitwardenDesktop
      obsidian
      kitty
      vlc
      mediainfo
      mediainfo-gui
      filebotOfficial
      codex
      sbctl
      libreoffice
      hunspell
      hunspellDicts.de-de
      hunspellDicts.en-us
      p7zip
      unzip
      unrar
      file
      libarchive
      innoextract
      inkscape
      gimp
      filezilla
      remmina
      wl-clipboard
      qrencode
      yt-dlp
      ffmpeg

      # Desktop synchronization, file transfer, diffing and diagrams.
      nextcloud-client
      localsend
      meld
      drawio

      # Video editing, recording and transcoding.
      kdePackages.kdenlive
      obs-studio
      handbrake

      # Audio editing and PipeWire routing diagnostics.
      audacity
      qpwgraph

      # Desktop communication clients.
      signal-desktop
      element-desktop
      threemaWeb

      # E-books and database administration.
      calibre
      dbeaver-bin

      # Additional raster graphics tooling.
      krita

      (python3.withPackages (
        ps: with ps; [
          numpy
          scipy
          rich
          rich-argparse
        ]
      ))
    ])
    ++ pkgs.lib.optionals config.networking.modemmanager.enable [ pkgs.gpsd ];
}
