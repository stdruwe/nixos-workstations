# /etc/nixos/modules/common/fonts.nix

{ lib, pkgs, ... }:

let
  # Fonts extracted locally from the official Apple packages.
  #
  # Expected path:
  #   /etc/nixos/fonts/apple/
  #
  # The shared installer path obtains SF Pro, SF Mono and New York directly
  # from Apple's official Developer DMGs. These include SF Pro, SF Pro Text,
  # SF Pro Display, SF Pro Rounded, SF Mono and New York.
  appleFonts = pkgs.stdenvNoCC.mkDerivation {
    pname = "apple-fonts-local";
    version = "1";

    src = ../../fonts/apple;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/share/fonts/opentype/apple
      mkdir -p $out/share/fonts/truetype/apple

      # OpenType fonts
      find . -type f -iname '*.otf' \
        -exec cp -v {} $out/share/fonts/opentype/apple/ \;

      # TrueType fonts
      find . -type f -iname '*.ttf' \
        -exec cp -v {} $out/share/fonts/truetype/apple/ \;

      runHook postInstall
    '';
  };
in
{
  fonts.packages = with pkgs; [
    appleFonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  fonts.fontconfig = {
    antialias = true;

    hinting = {
      enable = true;
      autohint = false;
      style = "slight";
    };

    subpixel = {
      rgba = "rgb";
      lcdfilter = "default";
    };

    # "New York Medium" is a local semantic alias. Apple ships New York as a
    # variable family, so the alias keeps the real family name while promoting
    # only regular-weight serif requests to Medium. Explicit Bold/Semibold
    # requests therefore continue to resolve to their requested weight.
    localConf = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <match target="pattern">
          <test qual="any" name="family" compare="eq">
            <string>serif</string>
          </test>
          <test name="weight" compare="eq">
            <const>regular</const>
          </test>
          <edit name="weight" mode="assign">
            <const>medium</const>
          </edit>
        </match>

        <match target="pattern">
          <test qual="any" name="family" compare="eq">
            <string>New York Medium</string>
          </test>
          <test name="weight" compare="eq">
            <const>regular</const>
          </test>
          <edit name="weight" mode="assign">
            <const>medium</const>
          </edit>
        </match>
      </fontconfig>
    '';

    aliases."New York Medium" = {
      prefer = [ "New York" ];
    };

    defaultFonts = lib.mkForce {
      sansSerif = [
        "SF Pro"
        "Noto Sans"
      ];

      serif = [
        "New York Medium"
        "Noto Serif"
      ];

      monospace = [
        "SF Mono"
        "Noto Sans Mono"
      ];

      emoji = [
        "Noto Color Emoji"
      ];
    };
  };

  environment.etc."xdg/kdeglobals".text = ''
    [General]
    ColorScheme=BreezeDark
    font=SF Pro,10,-1,5,50,0,0,0,0,0
    fixed=SF Mono,10,-1,5,50,0,0,0,0,0
    menuFont=SF Pro,10,-1,5,50,0,0,0,0,0
    smallestReadableFont=SF Pro,8,-1,5,50,0,0,0,0,0
    toolBarFont=SF Pro,10,-1,5,50,0,0,0,0,0

    XftAntialias=true
    XftHintStyle=hintslight
    XftSubPixel=rgb

    [Icons]
    Theme=breeze-dark

    [KDE]
    LookAndFeelPackage=org.kde.breezedark.desktop
    SingleClick=true

    [WM]
    activeFont=SF Pro,10,-1,5,50,0,0,0,0,0
  '';
}
