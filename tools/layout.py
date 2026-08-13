"""
Single source of truth for the slideshow ADF's disk layout.

src/layout.i mirrors these values for the assembly side. If you change
anything here, update src/layout.i to match (makeadf.py does not currently
generate it automatically).
"""

SECTOR_SIZE = 512

# --- boot block ---
BOOT_SECTORS = 2                       # sectors 0-1, 1024 bytes total

# --- stage-2 program (main.s + diskio.s + ptplayer.asm linked together) ---
STAGE2_START_SECTOR = BOOT_SECTORS     # 2
STAGE2_SECTORS = 48                    # budget: 24576 bytes (ptplayer.asm is sizeable)

# --- palette table: one 32-colour (64-byte) CMAP entry per image ---
PALETTE_ENTRY_SIZE = 64                # 32 colours * 2 bytes
PALETTE_START_SECTOR = STAGE2_START_SECTOR + STAGE2_SECTORS   # 18

# --- slideshow order. Edit this list to reorder/add/remove slides -- ---
# --- everything else below derives from its length.                 ---
IMAGES = [
    "2022", "2ND", "FH25", "FONY35", "MSXDEV20", "ModelD", "OOPS", "PM", "TFHMSX",
]
NUM_IMAGES = len(IMAGES)

PALETTE_SECTORS = (NUM_IMAGES * PALETTE_ENTRY_SIZE + SECTOR_SIZE - 1) // SECTOR_SIZE  # 2

# --- music module: mod.sll8 converted at build time (see mod2pt.py) from
# 15-sample NoiseTracker to 31-sample "M.K." ProTracker format, since
# ptplayer.asm only understands the modern layout ---
MOD_START_SECTOR = PALETTE_START_SECTOR + PALETTE_SECTORS     # 20
MOD_SECTORS = 85                       # 43520 bytes, converted mod is 43200

# --- images: fixed-size raw bitplane slots, true Amiga plane-contiguous order ---
IMAGE_WIDTH = 256
IMAGE_HEIGHT = 212
IMAGE_PLANES = 6                       # EHB: 5 colour planes + 1 half-brite plane
IMAGE_ROWBYTES = IMAGE_WIDTH // 8      # 32
IMAGE_PLANE_SIZE = IMAGE_ROWBYTES * IMAGE_HEIGHT   # 6784
IMAGE_RAW_SIZE = IMAGE_PLANE_SIZE * IMAGE_PLANES   # 40704
IMAGE_SLOT_SECTORS = 80                # 40960 bytes >= 40704, rounds up to sector

IMAGE_START_SECTOR = MOD_START_SECTOR + MOD_SECTORS            # 104

ADF_TOTAL_SECTORS = 1760               # 80 cyl * 2 heads * 11 sectors
ADF_TOTAL_BYTES = ADF_TOTAL_SECTORS * SECTOR_SIZE   # 901120

# --- fixed chip-RAM runtime addresses ---
# Stage-2 is loaded to a fixed address (not AllocMem'd) so its code can use
# plain absolute addressing throughout instead of having to be written as
# fully position-independent code. This early in the boot process (right
# after the boot block's own trackdisk read, before Workbench/any dynamic
# allocations happen) a generously-high fixed chip RAM address is safe on
# any machine with at least 512KB chip RAM -- Kickstart's own low-memory
# footprint at this point is far smaller than this.
STAGE2_LOAD_ADDR = 0x30000     # code budget 48 sectors = 0x6000, ends at 0x36000
PALETTE_BUF_ADDR = 0x40000     # 576 bytes needed
MOD_BUF_ADDR = 0x41000         # 43520 bytes needed (converted 31-sample MOD)
IMAGE_BUF_ADDR = 0x60000       # 40960 bytes needed
# highest byte used: 0x60000 + 40960 = 0x6A000 (~424KB), still comfortably
# under a stock 512KB (0x80000) chip RAM A500.
# highest byte used: 0x40000 + 40960 = 0x4A000 (~294KB), comfortably under
# even a stock 512KB (0x80000) chip RAM A500.


def image_sector(index):
    """Logical sector where image `index` (0-based) starts."""
    return IMAGE_START_SECTOR + index * IMAGE_SLOT_SECTORS


def total_sectors_used():
    return IMAGE_START_SECTOR + NUM_IMAGES * IMAGE_SLOT_SECTORS


if __name__ == "__main__":
    used = total_sectors_used()
    print(f"NUM_IMAGES          = {NUM_IMAGES}")
    print(f"PALETTE_START_SECTOR = {PALETTE_START_SECTOR} ({PALETTE_SECTORS} sector(s))")
    print(f"MOD_START_SECTOR     = {MOD_START_SECTOR} ({MOD_SECTORS} sectors)")
    print(f"IMAGE_START_SECTOR   = {IMAGE_START_SECTOR} ({IMAGE_SLOT_SECTORS} sectors/image)")
    for i, name in enumerate(IMAGES):
        print(f"  [{i}] {name:10s} sector {image_sector(i)}")
    print(f"Total sectors used   = {used} / {ADF_TOTAL_SECTORS} "
          f"({used*SECTOR_SIZE/1024:.1f}KB / {ADF_TOTAL_BYTES/1024:.0f}KB)")
