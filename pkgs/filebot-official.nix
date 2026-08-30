{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  makeWrapper,
  autoPatchelfHook,
  openjdk17,
  zlib,
  libzen,
  libmediainfo,
  curlWithGnuTls,
  libmms,
  glib,
  libx11,
  libxext,
  libxrender,
  libxtst,
  libxi,
  libxxf86vm,
  gtk3,
  pango,
  atk,
  cairo,
  gdk-pixbuf,
  freetype,
  fontconfig,
  alsa-lib,
  libglvnd,
}:

let
  localSource = ../.local-sources/filebot-source.nix;
  source = import (if builtins.pathExists localSource then localSource else ./filebot-source.nix);

  runtimeLibraries = [
    zlib
    libzen
    libmediainfo
    curlWithGnuTls
    libmms
    glib

    # The official amd64 DEB ships a private JRE. Its AWT / JavaFX native
    # libraries still link against the normal Linux desktop stack, which is
    # globally available on Debian but must be made explicit on NixOS.
    libx11
    libxext
    libxrender
    libxtst
    libxi
    libxxf86vm
    gtk3
    pango
    atk
    cairo
    gdk-pixbuf
    freetype
    fontconfig
    alsa-lib
    libglvnd
  ];

  runtimeLibraryPath = lib.makeLibraryPath runtimeLibraries;
in
stdenv.mkDerivation {
  pname = "filebot";
  inherit (source) version;

  src = fetchurl {
    url = "https://get.filebot.net/filebot/FileBot_${source.version}/FileBot_${source.version}_amd64.deb";
    sha256 = source.sha256;
  };

  nativeBuildInputs = [
    dpkg
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = runtimeLibraries;

  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out" "$TMPDIR/filebot-deb"
    dpkg-deb -x "$src" "$TMPDIR/filebot-deb"

    if [ ! -d "$TMPDIR/filebot-deb/usr" ]; then
      echo "FileBot DEB does not contain the expected /usr payload" >&2
      exit 1
    fi

    cp -a "$TMPDIR/filebot-deb/usr/." "$out/"

    launcher="$out/share/filebot/bin/filebot.sh"
    if [ ! -f "$launcher" ]; then
      echo "FileBot DEB does not contain the expected launcher: $launcher" >&2
      exit 1
    fi

    # The Debian launcher may contain absolute /usr paths. Relocate them into
    # the immutable Nix store package before adding the local HiDPI wrapper.
    substituteInPlace "$launcher" \
      --replace "/usr/share/filebot" "$out/share/filebot"

    mkdir -p "$out/bin"
    rm -f "$out/bin/filebot"

    makeWrapper "$launcher" "$out/bin/filebot" \
      --prefix PATH : ${lib.makeBinPath [ openjdk17 ]} \
      --set FILEBOT_HOME "$out/share/filebot" \
      --prefix LD_LIBRARY_PATH : "$out/share/filebot/lib/Linux-x86_64:${runtimeLibraryPath}" \
      --prefix JAVA_OPTS " " "-Dsun.java2d.uiScale=2"

    # Keep the upstream desktop integration and icons, but make absolute Debian
    # paths point at the Nix store package instead of /usr.
    for desktopDir in \
      "$out/share/applications" \
      "$out/share/kservices5" \
      "$out/share/file-manager/actions"; do
      if [ -d "$desktopDir" ]; then
        while IFS= read -r -d $'\0' desktopFile; do
          substituteInPlace "$desktopFile" \
            --replace "/usr/bin/filebot" "$out/bin/filebot" \
            --replace "Exec=filebot" "Exec=$out/bin/filebot" \
            --replace "TryExec=filebot" "TryExec=$out/bin/filebot" \
            --replace "/usr/share/filebot" "$out/share/filebot"
        done < <(find "$desktopDir" -type f -name '*.desktop' -print0)
      fi
    done

    runHook postInstall
  '';

  meta = {
    description = "Ultimate TV and Movie Renamer";
    homepage = "https://www.filebot.net/";
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "filebot";
  };
}
