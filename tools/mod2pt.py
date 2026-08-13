"""
Convert the classic 15-sample NoiseTracker-format mod.sll8 into a standard
31-sample ProTracker-format module (with an "M.K." tag), because ptplayer.asm
(the third-party replay routine now used for music) only understands the
modern 31-sample layout.

This is a well-defined, mechanical transformation: the original file's 15
sample headers become the first 15 of 31 (the other 16 are all-zero/unused
instrument slots), the "M.K." tag is inserted, and everything else --
songname, order table, pattern data, sample data -- is copied unchanged.
Pattern data itself needs no changes: the sample-number field in a MOD
pattern row is always a 5-bit (0-31) value regardless of how many
instruments the file actually defines; the 15-sample file simply never
uses values above 15.
"""
import struct

OLD_HEADER_SIZE = 20 + 15 * 30 + 1 + 1 + 128          # 600
NEW_HEADER_SIZE = 20 + 31 * 30 + 1 + 1 + 128 + 4       # 1084


def convert(data: bytes) -> bytes:
    songname = data[0:20]
    old_samples = data[20:20 + 15 * 30]
    songlength = data[470:471]
    restart = data[471:472]
    order_table = data[472:600]
    rest = data[OLD_HEADER_SIZE:]                       # patterns + sample data, unchanged

    new_samples = old_samples + b"\x00" * (30 * 16)      # pad 15 -> 31 sample slots

    out = bytearray()
    out += songname
    out += new_samples
    out += songlength
    out += restart
    out += order_table
    out += b"M.K."
    out += rest

    assert len(out) == len(data) + (NEW_HEADER_SIZE - OLD_HEADER_SIZE)
    return bytes(out)


if __name__ == "__main__":
    import sys
    from pathlib import Path

    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "mod.sll8"
    dst = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "out" / "mod_pt.mod"
    dst.parent.mkdir(exist_ok=True)
    converted = convert(src.read_bytes())
    dst.write_bytes(converted)
    print(f"{src.name}: {src.stat().st_size} bytes -> {dst.name}: {len(converted)} bytes")
