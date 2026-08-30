#!/usr/bin/env python3
"""Extract Apple's Retina boot logo from an appleLogo.efires bundle.

The EFIRES container format used by Apple's EFI login resources starts with a
little-endian uint16 revision and uint16 image count. Each image table entry is
64 bytes of NUL-terminated filename followed by little-endian uint32 offset and
uint32 size fields.

This helper intentionally uses only the Python standard library so it can run
from a NixOS live system without carrying third-party extraction software.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

TARGET_NAME = "appleLogo_apple@2x.png"
EXPECTED_WIDTH = 168
EXPECTED_HEIGHT = 206
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
HEADER = struct.Struct("<HH")
IMAGE_HEADER = struct.Struct("<64sII")
PNG_IHDR = struct.Struct(">II")


def fail(message: str) -> "NoReturn":
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def png_dimensions(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or not data.startswith(PNG_SIGNATURE):
        fail("target EFIRES entry is not a PNG image")
    if data[12:16] != b"IHDR":
        fail("target PNG does not contain IHDR at the expected position")
    return PNG_IHDR.unpack_from(data, 16)


def extract(source: Path, destination: Path) -> None:
    try:
        bundle = source.read_bytes()
    except OSError as exc:
        fail(f"cannot read {source}: {exc}")

    if len(bundle) < HEADER.size:
        fail("EFIRES file is too small to contain a header")

    revision, image_count = HEADER.unpack_from(bundle, 0)
    table_end = HEADER.size + image_count * IMAGE_HEADER.size

    if image_count == 0:
        fail("EFIRES bundle contains no images")
    if table_end > len(bundle):
        fail("EFIRES image table extends beyond the input file")

    target_data: bytes | None = None

    for index in range(image_count):
        pos = HEADER.size + index * IMAGE_HEADER.size
        raw_name, offset, size = IMAGE_HEADER.unpack_from(bundle, pos)
        name = raw_name.split(b"\0", 1)[0].decode("utf-8", errors="strict")

        if offset > len(bundle) or size > len(bundle) - offset:
            fail(f"EFIRES entry {name!r} points outside the input file")

        if name == TARGET_NAME:
            target_data = bundle[offset : offset + size]
            break

    if target_data is None:
        available = []
        for index in range(image_count):
            pos = HEADER.size + index * IMAGE_HEADER.size
            raw_name, _, _ = IMAGE_HEADER.unpack_from(bundle, pos)
            available.append(raw_name.split(b"\0", 1)[0].decode("utf-8", errors="replace"))
        fail(
            f"{TARGET_NAME!r} not found in EFIRES revision {revision}; "
            f"available entries: {', '.join(available)}"
        )

    width, height = png_dimensions(target_data)
    if (width, height) != (EXPECTED_WIDTH, EXPECTED_HEIGHT):
        fail(
            f"unexpected boot-logo dimensions {width}x{height}; "
            f"expected {EXPECTED_WIDTH}x{EXPECTED_HEIGHT}"
        )

    try:
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(target_data)
    except OSError as exc:
        fail(f"cannot write {destination}: {exc}")

    print(f"EFIRES revision: {revision}")
    print(f"Images: {image_count}")
    print(f"Extracted: {TARGET_NAME}")
    print(f"Dimensions: {width}x{height}")
    print(f"Output: {destination}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract appleLogo_apple@2x.png from Apple's appleLogo.efires."
    )
    parser.add_argument("source", type=Path, help="path to appleLogo.efires")
    parser.add_argument("destination", type=Path, help="output PNG path")
    args = parser.parse_args()
    extract(args.source, args.destination)


if __name__ == "__main__":
    main()
