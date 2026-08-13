#!/usr/bin/env python3
"""
Build out/slideshow.adf: assembles boot.s and main.s with vasm, converts the
IFF images (via iff2raw.py's functions), and packs everything into a flat
901120-byte Amiga disk image at the fixed sector layout defined in layout.py
-- no AmigaDOS filesystem, just raw sectors read by our own boot block.

Requires vasmm68k_mot on PATH (or pointed to via the VASM environment
variable). Get it from http://sun.hasenbraten.de/vasm/ (choose the
m68k/mot syntax build).

Usage:
    python3 makeadf.py
"""
import os
import shutil
import struct
import subprocess
import sys
from pathlib import Path

import layout
import iff2raw
import mod2pt

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
OUT = ROOT / "out"

VASM = os.environ.get("VASM", "vasmm68k_mot")


def run_vasm(src_name, out_name):
    src_path = SRC / src_name
    out_path = OUT / out_name
    if shutil.which(VASM) is None:
        raise SystemExit(
            f"error: '{VASM}' not found on PATH.\n"
            f"Install vasm (m68k/mot syntax build) from "
            f"http://sun.hasenbraten.de/vasm/, or set the VASM environment "
            f"variable to its full path."
        )
    cmd = [VASM, "-Fbin", "-m68000", "-no-opt", "-o", str(out_path), str(src_path)]
    print("  $", " ".join(cmd))
    result = subprocess.run(cmd, cwd=SRC)
    if result.returncode != 0:
        raise SystemExit(f"error: vasm failed assembling {src_name}")
    return out_path.read_bytes()


def bootblock_checksum(data):
    """Standard Amiga boot-block checksum: sum all 256 longwords (with the
    checksum field itself treated as 0) using end-around-carry addition;
    the checksum value that makes the total equal 0xFFFFFFFF is valid."""
    assert len(data) == 1024
    total = 0
    for i in range(0, 1024, 4):
        if i == 4:
            continue
        word = struct.unpack(">I", data[i:i + 4])[0]
        total += word
        while total > 0xFFFFFFFF:
            total = (total & 0xFFFFFFFF) + (total >> 32)
    return 0xFFFFFFFF - total


def pad(data, size, what):
    if len(data) > size:
        raise SystemExit(f"error: {what} is {len(data)} bytes, exceeds budget of {size}")
    return data + b"\x00" * (size - len(data))


def build_boot_block():
    print("assembling boot.s ...")
    data = run_vasm("boot.s", "boot.bin")
    if len(data) > 1024:
        raise SystemExit(f"error: boot.bin is {len(data)} bytes, exceeds 1024-byte boot block budget")
    data = pad(data, 1024, "boot block")
    data = bytearray(data)
    if data[0:3] != b"DOS":
        raise SystemExit("error: boot.bin does not start with the 'DOS' id -- did boot.s assemble correctly?")
    checksum = bootblock_checksum(bytes(data))
    data[4:8] = struct.pack(">I", checksum)
    print(f"  boot block checksum = 0x{checksum:08X}")
    return bytes(data)


def build_stage2():
    print("assembling main.s ...")
    data = run_vasm("main.s", "main.bin")
    budget = layout.STAGE2_SECTORS * layout.SECTOR_SIZE
    print(f"  stage-2 is {len(data)} bytes (budget {budget})")
    return pad(data, budget, "stage-2 program")


def build_palette_and_images():
    print("converting IFF images ...")
    OUT.mkdir(exist_ok=True)
    palette_table = bytearray()
    image_blobs = []
    for name in layout.IMAGES:
        iff_path = ROOT / f"{name}.iff"
        plane_major, palette = iff2raw.convert_one(iff_path)
        palette_table += palette
        image_blobs.append(pad(plane_major, layout.IMAGE_SLOT_SECTORS * layout.SECTOR_SIZE, name))
        print(f"  {name}: {len(plane_major)} bytes image, palette ok")
    palette_bytes = pad(bytes(palette_table), layout.PALETTE_SECTORS * layout.SECTOR_SIZE, "palette table")
    return palette_bytes, image_blobs


def build_mod():
    mod_path = ROOT / "mod.sll8"
    raw = mod_path.read_bytes()
    converted = mod2pt.convert(raw)
    print(f"converted {mod_path.name} ({len(raw)} bytes) -> 31-sample M.K. format ({len(converted)} bytes)")
    return pad(converted, layout.MOD_SECTORS * layout.SECTOR_SIZE, "converted mod")


def main():
    OUT.mkdir(exist_ok=True)

    boot_block = build_boot_block()
    stage2 = build_stage2()
    palette_bytes, image_blobs = build_palette_and_images()
    mod_bytes = build_mod()

    adf = bytearray(b"\x00" * layout.ADF_TOTAL_BYTES)

    def place(data, sector, what):
        offset = sector * layout.SECTOR_SIZE
        end = offset + len(data)
        if end > len(adf):
            raise SystemExit(f"error: {what} at sector {sector} runs past the end of the disk")
        adf[offset:end] = data

    place(boot_block, 0, "boot block")
    place(stage2, layout.STAGE2_START_SECTOR, "stage-2")
    place(palette_bytes, layout.PALETTE_START_SECTOR, "palette table")
    place(mod_bytes, layout.MOD_START_SECTOR, "mod.sll8")
    for i, blob in enumerate(image_blobs):
        place(blob, layout.image_sector(i), layout.IMAGES[i])

    adf_path = OUT / "slideshow.adf"
    adf_path.write_bytes(adf)
    assert adf_path.stat().st_size == layout.ADF_TOTAL_BYTES
    print(f"wrote {adf_path} ({layout.ADF_TOTAL_BYTES} bytes)")


if __name__ == "__main__":
    main()
