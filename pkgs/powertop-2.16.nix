{
  lib,
  stdenv,
  fetchFromGitHub,

  meson,
  ninja,
  pkg-config,
  gettext,

  ncurses,
  libnl,
  libtracefs,
  libtraceevent,
  pciutils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "powertop";
  version = "2.16";

  src = fetchFromGitHub {
    owner = "fenrus75";
    repo = "powertop";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ouGLEu4dbn/r4i4yaS3w36mo4qRtzaFgS6YTSCNAcOM=";
  };

  # Programs required only during the build.
  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    gettext
  ];

  # Libraries PowerTOP is built against.
  buildInputs = [
    ncurses
    libnl
    libtracefs
    libtraceevent
    pciutils
  ];

  # Some tests require special runtime conditions. Keep them disabled for this
  # local package for now.
  mesonFlags = [
    "-Denable-tests=false"
  ];

  # NixOS has no traditional /sbin/modprobe. Let PowerTOP use modprobe from
  # PATH instead.
  postPatch = ''
    substituteInPlace src/main.cpp \
      --replace-fail "/sbin/modprobe" "modprobe"
  '';

  meta = {
    description = "Linux tool to diagnose power consumption and power management";
    homepage = "https://github.com/fenrus75/powertop";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
    mainProgram = "powertop";
  };
})
