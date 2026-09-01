{
  lib,
  pkgs,
  nixosHardware,
}:

let
  patchset = builtins.fromJSON (
    builtins.readFile "${nixosHardware}/apple/t2/pkgs/linux-t2/stable.json"
  );

  # Linux 6.18.48 gained its own magicmouse reset-resume implementation.
  # The pinned T2/Asahi patch bundle still carries the older SPI-only
  # implementation as patch 12/18, so applying the bundle verbatim now adds a
  # duplicate function and collides with the upstream .reset_resume member.
  obsoleteResetResumeCommit = "38ab43df5df32d202219a5eb1ba834ab31097846";

  t2Patches = map (
    { name, hash }:
    let
      sourcePatch = pkgs.fetchurl {
        inherit name hash;
        url = patchset.base_url + name;
      };

      patch =
        if name == "4001-asahi-trackpad.patch" then
          pkgs.runCommand "t2-4001-asahi-trackpad-without-obsolete-reset-resume.patch"
            {
              nativeBuildInputs = [
                pkgs.gawk
                pkgs.gnugrep
              ];
            }
            ''
              marker='From ${obsoleteResetResumeCommit} Mon Sep 17 00:00:00 2001'

              if ! grep -Fqx "$marker" ${sourcePatch}; then
                echo "The pinned T2 trackpad patch changed; review the Linux 6.18.48 compatibility workaround." >&2
                exit 1
              fi

              gawk -v marker="$marker" '
                $0 == marker {
                  skip = 1
                  next
                }
                /^From [0-9a-f]+ Mon Sep 17 00:00:00 2001$/ {
                  skip = 0
                }
                !skip {
                  print
                }
              ' ${sourcePatch} > "$out"

              if grep -Fq 'Subject: [PATCH 12/18] HID: magicmouse: Add .reset_resume for SPI trackpads' "$out"; then
                echo "Failed to remove the obsolete T2 magicmouse reset-resume subpatch." >&2
                exit 1
              fi
            ''
        else
          sourcePatch;
    in
    {
      inherit name patch;
    }
  ) patchset.patches;
in
pkgs.linux_6_18.override {
  pname = "linux-t2";

  structuredExtraConfig = with lib.kernel; {
    APPLE_BCE = module;
    APPLE_GMUX = module;
    APFS_FS = module;
    BRCMFMAC = module;
    BT_BCM = module;
    BT_HCIBCM4377 = module;
    BT_HCIUART_BCM = yes;
    BT_HCIUART = module;
    HID_APPLETB_BL = module;
    HID_APPLETB_KBD = module;
    HID_APPLE = module;
    HID_MAGICMOUSE = module;
    DRM_APPLETBDRM = module;
    HID_SENSOR_ALS = module;
    SND_PCM = module;
    STAGING = yes;
  };

  kernelPatches = t2Patches;

  argsOverride.extraMeta = {
    description = "The Linux kernel with patches from the T2 Linux project";
    maintainers = with lib.maintainers; [ soopyc ];
  };
}
