{ pkgs, ... }:

let
  nixosBootPickerIcon = pkgs.runCommand "nixos-volume-icon.icns" { } ''
    for size in 16 32 48 128 256 512 1024; do
      ${pkgs.imagemagick}/bin/magick \
        ${./assets/nix-snowflake-colours.svg} \
        -background none \
        -resize "''${size}x''${size}" \
        "$TMPDIR/nixos-''${size}.png"
    done

    ${pkgs.libicns}/bin/png2icns \
      "$out" \
      "$TMPDIR/nixos-16.png" \
      "$TMPDIR/nixos-32.png" \
      "$TMPDIR/nixos-48.png" \
      "$TMPDIR/nixos-128.png" \
      "$TMPDIR/nixos-256.png" \
      "$TMPDIR/nixos-512.png" \
      "$TMPDIR/nixos-1024.png"
  '';
in
{
  # Apple's Startup Manager uses .VolumeIcon.icns from the root of the ESP.
  # systemd-boot extraFiles keeps the icon on the dedicated NixOS ESP only.
  boot.loader.systemd-boot.extraFiles.".VolumeIcon.icns" = nixosBootPickerIcon;
}
