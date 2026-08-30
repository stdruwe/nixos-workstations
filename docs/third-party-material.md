# Third-party material and provenance

Last updated: 2026-08-30

This repository contains configuration, scripts, patches and a small amount of
redistributable third-party material. Machine-local vendor assets, fonts and
device-specific tuning data are deliberately kept outside Git.

A repository license, if added, must be scoped so it does not purport to grant
rights in third-party material beyond the rights provided by the respective
upstream source.

## Shared workstation wallpaper

The shared desktop/Plymouth wallpaper is not stored in Git. It is obtained from
the KDE Store entry:

- KDE Store: https://store.kde.org/p/1189184
- content ID: `1189184`
- title: `The Last Endeavor Noir Style Wallpaper`
- publisher shown by the source page: `CHARLIE-HENSON`
- license shown by the source page: Creative Commons Attribution (`cc-by`)

The KDE Store page does not identify a specific Creative Commons version, so no
particular CC BY version is asserted here.

`scripts/fetch-wallpaper.sh` resolves the current download URL through KDE's OCS
API and stores the image only under the ignored machine-local asset directory:

```text
assets/local/wallpaper.png
```

or, if the source payload is JPEG:

```text
assets/local/wallpaper.jpg
```

The installer fetches the wallpaper during non-destructive preflight. A normal
boot also has a best-effort repair service for a missing local copy. Clean
checkouts remain buildable without the wallpaper and use a plain black Plymouth
fallback until the local asset exists.

The ThinkPad 2880x1800, MacBook 2560x1600 and HP 1920x1080 Plymouth backgrounds
are generated from this local source during the respective Nix build; no
profile-specific derived background image is stored in Git.

## NixOS snowflake artwork

Tracked file:

```text
hosts/apple-macbook-air-8-1/assets/nix-snowflake-colours.svg
```

Verified upstream source:

- NixOS artwork repository: https://github.com/NixOS/nixos-artwork/blob/master/logo/nix-snowflake-colours.svg
- license: Creative Commons Attribution 4.0 International (CC BY 4.0)
- license text: https://creativecommons.org/licenses/by/4.0/

The upstream `logo/README.md` credits the original design to Simon Frankau and
a revision to Tim Cuthbertson. Preserve that attribution and the upstream
license when redistributing this asset.

## Optional Apple Plymouth boot logo

The Apple boot logo is machine-local and is not redistributed by this
repository.

The source material is Apple's `appleLogo.efires` resource bundle from the
machine's own macOS APFS Preboot volume. On the tested MacBook Air 8,1 it is
available under a path of the form:

```text
/System/Volumes/Preboot/<UUID>/usr/standalone/i386/EfiLoginUI/appleLogo.efires
```

`scripts/stage-apple-boot-assets-macos.sh` copies the EFIRES bundle from macOS
to the machine's Apple EFI System Partition as:

```text
/assets/appleLogo.efires
```

Under NixOS, `scripts/import-apple-boot-logo-linux.sh` mounts the verified Apple
EFI partition read-only and calls `scripts/extract-apple-logo-efires.py`. The
extractor selects:

```text
appleLogo_apple@2x.png   168x206
```

and writes it to the ignored local path:

```text
assets/local/apple-logo-2x.png
```

If the local logo is absent, the Apple profile remains buildable and Plymouth
skips the Apple-logo intro.

## HP logo

The HP Plymouth logo is not stored in Git.

Documented source:

- source page: https://cdnlogo.com/logo/hewlett-packard_10258.html
- direct SVG URL: https://static.cdnlogo.com/logos/h/4/hewlett-packard.svg
- source-page title: `Hewlett Packard Logo PNG Vector SVG`
- uploader shown by the source page: `Isla Kelly`

The source site does not provide a general open-source redistribution license
for the trademark artwork. `scripts/fetch-hp-plymouth-logo.sh` therefore keeps
the SVG only at:

```text
assets/local/hp-logo.svg
```

The helper accepts only the verified source payload with SHA-256:

```text
7c6db26bddfee7258ee2afe33cf60ef32639f9d276c57110e20dd87e57f9b0a9
```

If the local SVG is absent, the HP profile remains buildable and Plymouth skips
the HP-logo intro. The project is not affiliated with or endorsed by HP.

## ThinkPad logo

The ThinkPad Plymouth logo is not stored in Git.

Verified source information from Wikimedia Commons:

- source page: https://commons.wikimedia.org/wiki/File:ThinkPad_Logo.svg
- original-file URL: https://upload.wikimedia.org/wikipedia/commons/0/09/ThinkPad_Logo.svg
- source stated by Wikimedia Commons: Lenovo
- author stated by Wikimedia Commons: Lenovo Group Limited
- copyright classification shown on the source page: `PD-textlogo`
- the source page separately notes possible trademark protection

`scripts/fetch-thinkpad-plymouth-logo.sh` stores the downloaded source only at:

```text
assets/local/thinkpad-logo.svg
```

The helper accepts only the verified source payload with SHA-256:

```text
c4325e91bb8c48f7d20e7782f431acce49aa0fc380eaf31f1a20ecd3dbccb542
```

When present, the NixOS profile renders the source at 520 pixels wide, changes
the black wordmark to white and preserves the red TrackPoint dot. If the local
SVG is absent, a transparent placeholder keeps the rest of the Plymouth theme
functional. The project is not affiliated with or endorsed by Lenovo.

## ThinkPad EasyEffects tuning

Device-specific ThinkPad speaker tuning is generated locally and is not stored
in Git.

The local generation workflow uses:

- converter: `antoinecellerier/speaker-tuning-to-easyeffects`
- upstream repository: https://github.com/antoinecellerier/speaker-tuning-to-easyeffects
- converter license: MIT
- pinned converter release: `v2026.08`
- pinned converter commit: `86e0cb9d9756fc5c95648dd305f385192e696ade`

The matched Lenovo tuning input for the ThinkPad X1 Carbon Gen 13 is:

```text
SOUNDWIRE_MAN_025D_FUNC_1318_SUBSYS_233917AA.xml
```

`scripts/generate-thinkpad-easyeffects-local.sh` downloads Lenovo's audio-driver
package:

```text
https://download.lenovo.com/pccbbs/mobiles/n4ba127w.exe
```

and accepts only the package with SHA-256:

```text
70275ff0d2cdd079290a6848febaa415bb012cfe98dbca1502b58e088fbdb33b
```

The helper extracts the exact XML with `innoextract`, verifies the pinned
converter revision and generates all 27 preset JSON files and all 27 IRS files
under the ignored paths:

```text
audio/easyeffects/local/output/
audio/easyeffects/local/irs/
```

The ThinkPad installer performs this generation during non-destructive preflight
so a fresh installation receives the local tuning before the first NixOS build.

A user-adjusted `Dolby-Dynamic-Balanced.json` can optionally be saved with
`scripts/save-thinkpad-easyeffects-default.sh`. That override remains local at:

```text
audio/easyeffects/local/override/Dolby-Dynamic-Balanced.json
```

The generated default is used when no local override exists.

The converter's MIT license covers the converter software and its own
implementation. It must not be interpreted as relicensing OEM/Dolby tuning data
represented in generated device-specific presets or FIR data. Keeping all such
outputs local avoids redistributing that material from this repository.

The tracked `audio/easyeffects/output/Nothing.json`, EasyEffects database
settings and autoload metadata do not contain the device-specific FIR tuning.

## Broadcom/Linux patch

Tracked file:

```text
hosts/apple-macbook-air-8-1/brcmfmac-disable-nd-offload.patch
```

The patch modifies:

```text
drivers/net/wireless/broadcom/brcm80211/brcmfmac/core.c
```

The upstream Linux source file carries:

```text
SPDX-License-Identifier: ISC
Copyright (c) 2010 Broadcom Corporation
```

Treat the patch as a modification against ISC-licensed Broadcom/Linux source and
preserve the upstream licensing/copyright context when redistributing or
extracting it.

## `pkgs/apple-t2-brcm-firmware/`

This directory is a local packaging copy based on `NixOS/nixos-hardware` PR
#1933 / commit `48c8b5e0bd942604abf8034df9f43803fd31ffd7` (`apple/t2: improve
firmware extraction`).

Relevant upstream licensing:

- `NixOS/nixos-hardware`: CC0-1.0
- `AsahiLinux/asahi-installer` v0.7.9 used by `get-firmware.nix`: MIT
- the source files modified by `get-firmware-standalone.patch`: MIT
- extracted Apple firmware: proprietary/unfree and not part of this Git tree

The Nix package declares the extracted firmware unfree. Remove this temporary
packaging copy once the required firmware-extraction fix is available from the
pinned `nixos-hardware` source used by this configuration.

## Other upstream-derived helpers

Other files under `pkgs/` may be based on upstream packaging or project
metadata. Preserve explicit source URLs, upstream attribution and license
declarations where present.
