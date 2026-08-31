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

    # "New York Medium" is a local semantic alias for Apple's New York
    # variable family. Fontconfig pattern edits run before default weight
    # substitution, so the Medium promotion is applied in the font-result pass
    # instead. Both an explicit Regular request and Fontconfig's default Medium
    # request are normalized to the wght=500 variable-font instance. Explicit
    # Semibold/Bold requests never match these rules and retain their weight.
    localConf = ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <match target="font">
          <test target="pattern" qual="any" name="family" compare="eq">
            <string>New York Medium</string>
          </test>
          <test target="pattern" name="weight" compare="eq">
            <const>regular</const>
          </test>
          <edit name="weight" mode="assign">
            <const>medium</const>
          </edit>
          <edit name="style" mode="assign">
            <string>Medium</string>
          </edit>
          <edit name="fontvariations" mode="assign">
            <string>wght=500</string>
          </edit>
        </match>

        <match target="font">
          <test target="pattern" qual="any" name="family" compare="eq">
            <string>New York Medium</string>
          </test>
          <test target="pattern" name="weight" compare="eq">
            <const>medium</const>
          </test>
          <edit name="weight" mode="assign">
            <const>medium</const>
          </edit>
          <edit name="style" mode="assign">
            <string>Medium</string>
          </edit>
          <edit name="fontvariations" mode="assign">
            <string>wght=500</string>
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
