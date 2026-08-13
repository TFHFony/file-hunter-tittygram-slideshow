#!/usr/bin/env python3
"""
Convert the slideshow's IFF ILBM (EHB) images into fixed-size raw Amiga
bitplane blobs + a combined palette table, ready to be embedded on the ADF
by makeadf.py.

Amiga hardware wants each bitplane as one contiguous block (BPLxPT points
at IMAGE_PLANE_SIZE contiguous bytes per plane), but ILBM's on-disk BODY
chunk is stored row-major/plane-minor (all planes of row 0, then all planes
of row 1, ...). This tool decompresses the ByteRun1-packed BODY and
re-orders it into plane-major/row-minor order so main.s can DMA it directly
with no runtime reformatting.
"""
import struct
import sys
from pathlib import Path

import layout

SRC_DIR = Path(__file__).resolve().parent.parent
OUT_DIR = SRC_DIR / "out"


def read_chunks(data, start, end):
    pos = start
    chunks = []
    while pos + 8 <= end:
        tag = data[pos:pos + 4]
        size = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        chunk_data = data[pos + 8:pos + 8 + size]
        chunks.append((tag, chunk_data))
        pos += 8 + size + (size & 1)   # chunks are padded to even length
    return chunks


def unpack_byterun1(data, expected_size):
    """Standard IFF ByteRun1 (PackBits-style) decompressor."""
    out = bytearray()
    i = 0
    n = len(data)
    while len(out) < expected_size and i < n:
        b = data[i]
        i += 1
        if b <= 127:
            count = b + 1
            out += data[i:i + count]
            i += count
        elif b >= 129:
            count = 257 - b
            val = data[i]
            i += 1
            out += bytes([val]) * count
        # b == 128: no-op, skip
    if len(out) != expected_size:
        raise ValueError(f"unpacked {len(out)} bytes, expected {expected_size}")
    return bytes(out)


def deinterleave(body, width, height, nplanes):
    """ILBM row-major/plane-minor -> Amiga plane-major/row-minor."""
    rowbytes = width // 8
    planes = [bytearray(rowbytes * height) for _ in range(nplanes)]
    src = 0
    for y in range(height):
        for p in range(nplanes):
            planes[p][y * rowbytes:(y + 1) * rowbytes] = body[src:src + rowbytes]
            src += rowbytes
    out = bytearray()
    for p in planes:
        out += p
    return bytes(out)


def rgb8_to_amiga12(r, g, b):
    return ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)


def convert_one(iff_path):
    data = iff_path.read_bytes()
    if data[0:4] != b"FORM" or data[8:12] != b"ILBM":
        raise ValueError(f"{iff_path}: not a FORM ILBM file")
    form_size = struct.unpack(">I", data[4:8])[0]
    chunks = read_chunks(data, 12, 8 + form_size)

    bmhd = cmap = camg = body = None
    for tag, cdata in chunks:
        if tag == b"BMHD":
            bmhd = cdata
        elif tag == b"CMAP":
            cmap = cdata
        elif tag == b"CAMG":
            camg = cdata
        elif tag == b"BODY":
            body = cdata

    if bmhd is None or cmap is None or body is None:
        raise ValueError(f"{iff_path}: missing BMHD/CMAP/BODY chunk")

    w, h = struct.unpack(">HH", bmhd[0:4])
    nplanes = bmhd[8]
    compression = bmhd[10]

    if (w, h, nplanes) != (layout.IMAGE_WIDTH, layout.IMAGE_HEIGHT, layout.IMAGE_PLANES):
        raise ValueError(
            f"{iff_path}: expected {layout.IMAGE_WIDTH}x{layout.IMAGE_HEIGHT}x"
            f"{layout.IMAGE_PLANES}, got {w}x{h}x{nplanes}"
        )

    raw_row_major_size = (w // 8) * h * nplanes
    if compression == 1:
        row_major = unpack_byterun1(body, raw_row_major_size)
    elif compression == 0:
        row_major = body[:raw_row_major_size]
    else:
        raise ValueError(f"{iff_path}: unsupported compression method {compression}")

    plane_major = deinterleave(row_major, w, h, nplanes)
    assert len(plane_major) == layout.IMAGE_RAW_SIZE

    ncolors = len(cmap) // 3
    if ncolors < 32:
        raise ValueError(f"{iff_path}: CMAP has only {ncolors} colours, need 32")
    palette = bytearray()
    for c in range(32):
        r, g, b = cmap[c * 3], cmap[c * 3 + 1], cmap[c * 3 + 2]
        palette += struct.pack(">H", rgb8_to_amiga12(r, g, b))

    ehb_flag = False
    if camg is not None and len(camg) >= 4:
        viewmode = struct.unpack(">I", camg[0:4])[0]
        ehb_flag = bool(viewmode & 0x0080)
    if not ehb_flag:
        print(f"  warning: {iff_path.name} has no EHB CAMG flag set", file=sys.stderr)

    return plane_major, bytes(palette)


def main():
    OUT_DIR.mkdir(exist_ok=True)
    palette_table = bytearray()
    for name in layout.IMAGES:
        iff_path = SRC_DIR / f"{name}.iff"
        print(f"converting {iff_path.name} ...")
        plane_major, palette = convert_one(iff_path)
        raw_path = OUT_DIR / f"{name}.raw"
        raw_path.write_bytes(plane_major)
        palette_table += palette
        print(f"  -> {raw_path.name} ({len(plane_major)} bytes), "
              f"colour0={palette[0:2].hex()}")

    pal_path = OUT_DIR / "palette.bin"
    pal_path.write_bytes(palette_table)
    print(f"wrote {pal_path} ({len(palette_table)} bytes, "
          f"{len(layout.IMAGES)} x {layout.PALETTE_ENTRY_SIZE})")


if __name__ == "__main__":
    main()
