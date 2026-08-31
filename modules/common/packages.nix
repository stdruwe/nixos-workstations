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
in
{
  nixpkgs.config.allowUnfree = true;

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
      bitwarden-desktop
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
