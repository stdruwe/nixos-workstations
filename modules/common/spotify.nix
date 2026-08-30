{ pkgs, ... }:

let
  spotifyWayland = pkgs.symlinkJoin {
    name = "spotify-wayland";

    paths = [
      pkgs.spotify
    ];

    nativeBuildInputs = [
      pkgs.makeWrapper
    ];

    postBuild = ''
      wrapProgram $out/bin/spotify \
        --set NIXOS_OZONE_WL 1
    '';
  };
in
{
  environment.systemPackages = [
    spotifyWayland
  ];
}
