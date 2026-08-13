; Disk layout constants -- MUST mirror tools/layout.py exactly.
; Sector = 512 bytes. All *_SECTOR values are logical sectors (0-based,
; cyl*22 + head*11 + sector) as stored in the flat .adf file.

SECTOR_SIZE         EQU 512

BOOT_SECTORS         EQU 2

STAGE2_START_SECTOR EQU 2
STAGE2_SECTORS      EQU 48

PALETTE_ENTRY_SIZE   EQU 64            ; 32 colours * 2 bytes
NUM_IMAGES           EQU 9
PALETTE_START_SECTOR EQU 50
PALETTE_SECTORS      EQU 2

; mod.sll8 converted at build time (mod2pt.py) from 15-sample NoiseTracker
; to 31-sample "M.K." ProTracker format, since ptplayer.asm only
; understands the modern layout.
MOD_START_SECTOR    EQU 52
MOD_SECTORS          EQU 85
MOD_SIZE_BYTES        EQU 43200         ; converted mod length (rest of last sector is padding)

IMAGE_WIDTH           EQU 256
IMAGE_HEIGHT          EQU 212
IMAGE_PLANES          EQU 6
IMAGE_ROWBYTES        EQU 32            ; IMAGE_WIDTH/8
IMAGE_PLANE_SIZE      EQU 6784          ; IMAGE_ROWBYTES*IMAGE_HEIGHT
IMAGE_RAW_SIZE        EQU 40704         ; IMAGE_PLANE_SIZE*IMAGE_PLANES
IMAGE_SLOT_SECTORS    EQU 80
IMAGE_SLOT_BYTES      EQU 40960         ; IMAGE_SLOT_SECTORS*SECTOR_SIZE

IMAGE_START_SECTOR   EQU 137

; imageSector(n) = IMAGE_START_SECTOR + n*IMAGE_SLOT_SECTORS -- computed
; at runtime in main.s (mulu #IMAGE_SLOT_SECTORS, dN ; add #IMAGE_START_SECTOR)
; rather than tabulated here, so NUM_IMAGES can change without editing code.

; --- fixed chip-RAM runtime addresses (mirrors tools/layout.py) ---
; Stage-2 is loaded to a fixed address rather than AllocMem'd, so its code
; (main.s/diskio.s/ptplayer.asm) can use plain absolute addressing
; throughout instead of needing to be fully position-independent.
STAGE2_LOAD_ADDR      EQU $30000       ; code budget 48 sectors = $6000, ends at $36000
PALETTE_BUF_ADDR      EQU $40000       ; 576 bytes needed
MOD_BUF_ADDR          EQU $41000       ; 43520 bytes needed (converted 31-sample MOD)
IMAGE_BUF_ADDR        EQU $60000       ; 40960 bytes needed
