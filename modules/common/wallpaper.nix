{ config, lib, ... }:

let
  candidates = [
    {
      fileName = "wallpaper.png";
      source = ../../assets/local/wallpaper.png;
    }
    {
      fileName = "wallpaper.jpg";
      source = ../../assets/local/wallpaper.jpg;
    }
    {
      fileName = "wallpaper.jpeg";
      source = ../../assets/local/wallpaper.jpeg;
    }
  ];

  existing = builtins.filter (candidate: builtins.pathExists candidate.source) candidates;
  selected = if builtins.length existing == 1 then builtins.head existing else null;
in
{
  options.workstation.wallpaper = {
    source = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      readOnly = true;
      description = "Machine-local shared wallpaper source used by built system assets.";
    };

    runtimePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      readOnly = true;
      description = "Persistent /etc/nixos path to the selected machine-local shared wallpaper.";
    };
  };

  config = {
    workstation.wallpaper = {
      source = if selected == null then null else selected.source;
      runtimePath =
        if selected == null then
          null
        else
          "/etc/nixos/assets/local/${selected.fileName}";
    };

    assertions = [
      {
        assertion = builtins.length existing <= 1;
        message = ''
          Multiple shared wallpapers exist under /etc/nixos/assets/local.
          Keep exactly one of wallpaper.png, wallpaper.jpg or wallpaper.jpeg.
        '';
      }
    ];
  };
}
