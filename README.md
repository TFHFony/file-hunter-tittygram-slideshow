# File-Hunter.com & Tittygram Slideshow (Amiga)

A bootable Amiga floppy image (`.adf`) that shows 9 pictures in an infinite
loop with fade transitions, over background music -- no AmigaDOS, no
Workbench, no filesystem. The boot block loads everything else itself via
raw `trackdisk.device` sector reads.

Target: OCS, EHB (Extra Half-Brite, 32 colours + 32 half-bright shades),
~272x212 display, PAL and NTSC both auto-detected at boot.

## Status

**Working**, confirmed in FS-UAE (A500/OCS, Kickstart 1.3): boots, shows all
9 images with correct colours and fade transitions, plays music, and loops
forever. One known minor cosmetic issue remains -- see below.

Getting here took a full assemble-test-fix cycle in FS-UAE; several
non-obvious bugs were found and fixed along the way (see "Bugs found during
bring-up" below) that a first-draft, never-assembled version could not have
caught. Still only tested in one emulator on one Kickstart version -- not
yet verified on real hardware or other Kickstart revisions.

## Layout

```
src/
  hw.i          chipset/CIA/Exec register and structure offsets
  layout.i      disk sector layout + runtime chip-RAM addresses (assembly side)
  boot.s        stage-1 boot block (1024 bytes, sectors 0-1)
  main.s        stage-2: PAL/NTSC detect, display setup, fades, slideshow loop,
                music-tick glue (includes diskio.s and ptplayer.asm)
  diskio.s      raw sector-read helper (included into main.s)
  ptplayer.asm  third-party ProTracker replay routine (public domain, Frank
                Wille) -- see "Music player" below
tools/
  layout.py     disk sector layout (Python side -- must mirror src/layout.i)
  iff2raw.py    converts the *.iff images to raw Amiga bitplane blobs
  mod2pt.py     converts mod.sll8 (15-sample NoiseTracker) to 31-sample
                "M.K." ProTracker format at build time, for ptplayer.asm
  makeadf.py    assembles boot.s/main.s with vasm and packs out/slideshow.adf
  vasm/         local copy of the vasm assembler (not committed, see .gitignore)
  fsuae/        local copy of FS-UAE (not committed, see .gitignore)
  run.fs-uae    example FS-UAE config for testing out/slideshow.adf
*.iff            the 9 slides (already EHB, 256x212, 6 bitplanes -- as supplied)
mod.sll8         background music (15-sample NoiseTracker-format module)
```

## Disk layout (901120-byte ADF, 1760 x 512-byte sectors)

Run `python3 tools/layout.py` to print the live computed layout (sector
numbers derive from `NUM_IMAGES`, so adding/removing/reordering slides is
just editing the `IMAGES` list in `tools/layout.py` -- keep `src/layout.i`
in sync by hand, since nothing currently generates it automatically).
Currently: boot block at sector 0, stage-2 program at sector 2 (48-sector
budget), palette table at 50, converted MOD at 52 (85 sectors), the 9
images at 80 sectors each starting at sector 137. 857 of 1760 sectors used
(~428KB of 880KB).

## Building

Requires [vasm](http://sun.hasenbraten.de/vasm/) (the m68k/mot syntax
build) on your `PATH` as `vasmm68k_mot` (or set the `VASM` env var to its
full path), plus Python 3.

```bash
./build.sh
```
or on Windows:
```bash
build.bat
```

This runs `tools/makeadf.py`, which converts `mod.sll8` to ProTracker
format, assembles `boot.s` and `main.s`, converts the `.iff` images,
patches the boot-block checksum, and writes `out/slideshow.adf`.

## Testing

Boot `out/slideshow.adf` in an Amiga emulator (FS-UAE or WinUAE) configured
as a plain A500 (OCS, 512KB chip RAM), as floppy drive DF0. An example
`tools/run.fs-uae` config is included (edit the `kickstart_file` path to
point at your own Kickstart ROM -- not included in this repo, Kickstart is
copyrighted Commodore/Amiga software). Verified
so far under PAL Kickstart 1.3 only; NTSC and other Kickstart versions are
untested.

## Known remaining issue

**Right edge slightly cropped.** The display window is a formulaic
best-effort fit (see `SetupDisplayRegs` in `main.s`) and consistently cuts
off a sliver of the image's right edge at the "exact" 256px width. Widening
it by one extra fetched word (272px, current setting) mostly fixes this at
the cost of a very thin, technically-incorrect strip on the right (the
image buffer has no per-row padding, so the extra fetched pixels are
actually the start of the next row). Widening further breaks badly (tried
288px: severe diagonal tearing) -- something about the DIWSTOP/DDFSTOP
horizontal math is still not quite right beyond this point. Not
investigated further given diminishing returns for a cosmetic issue.

## Bugs found during bring-up (for anyone touching this code)

The first-draft version (written without incremental testing) had several
real bugs, found by actually booting it in FS-UAE:

- **Boot-code contract.** Boot blocks are handed an *already-open*
  trackdisk.device request in A1 by Kickstart's own "strap" loader, and
  must return via `D0`/`A0` (not jump) so the strap can clean up and hand
  off. The original code built its own separate device request from
  scratch and jumped directly to stage-2, bypassing that contract --
  works up to a point, but disk I/O in stage-2 hung.
- **`ln_Type` must not be preset to `NT_MESSAGE`** on a hand-built
  IOStdReq -- that field is used internally by the I/O completion
  mechanism.
- **Missing copper list.** Agnus does not reset `BPL1PT`..`BPL6PT` on its
  own each frame -- without a copper list rewriting them every VBlank, the
  pointers just kept advancing through all of chip RAM. This is required
  even for a fully static, non-animated image.
- **`DDFSTRT`/`DDFSTOP` must match the buffer's actual row stride.** Using
  the "standard" wider fetch window than the buffer's real per-row byte
  count desyncs the bitplane pointer every line, without `BPL1MOD`/
  `BPL2MOD` compensation.
- **`AddIntServer` interrupt handlers must explicitly set the Z flag on
  exit** (documented AmigaOS behaviour) -- restoring registers via `movem`
  right before `rts` does not affect condition codes, so the exit
  condition has to be set as the literal last instruction.
- **CIA-B's EXTER request bit in `INTREQ` is separate from the CIA's own
  `ICR` latch** and isn't cleared by reading `ICR` -- left uncleared, the
  CPU re-enters the handler continuously.
- **A register an interrupt handler doesn't preserve (D0 here, by design)
  must never be used to hold state across a loop that runs with interrupts
  enabled** -- `HoldSlide`'s wait loop originally kept its target tick
  count in D0, which the music interrupt was free to clobber mid-wait,
  hanging the slideshow forever on the first image.
- **A hand-rolled CIA-B Timer A interrupt never reliably fired** for
  reasons that resisted extensive debugging (LVOs, register conventions,
  and bit layouts were all verified correct against primary sources) --
  ultimately abandoned in favour of driving tempo from VBlank instead
  (a path already proven reliable elsewhere in this code), and then in
  favour of `ptplayer.asm` entirely (see below).

## Music player

The original custom NoiseTracker-scoped replay routine (driven by VBlank)
worked but had audible tempo/timing bugs. It's been replaced with
[**ptplayer**](https://aminet.net/package/mus/play/ptplayer) by Frank Wille
(also vasm's author) -- public domain, purpose-built for exactly this kind
of bare-metal game/demo use case. Built with `MINIMAL=1` (no sound-effect
mixing, smaller code) and `VBLANK_MUSIC=1` (skip ptplayer's own CIA-B
Timer-A tempo interrupt; `main.s`'s own VBlank interrupt calls `_mt_music`
instead, at an exact PAL/NTSC-neutral 50 ticks/sec via a small
Bresenham-style rate accumulator -- the same technique the original custom
player used for the same reason). ptplayer still uses CIA-B Timer-B
internally for DMA-enable/repeat-pointer timing, installed by writing
directly to the CPU's level-6 autovector rather than through Exec's
`AddIntServer` chain -- notably a *different* mechanism than the
`AddIntServer`-based approach that didn't work reliably for the original
player's Timer-A interrupt, and it has worked correctly every time tested.

`mod.sll8` is a classic 15-sample NoiseTracker-format module; ptplayer only
understands the modern 31-sample "M.K." layout, so `tools/mod2pt.py`
converts it at build time (mechanical transformation: pad 15 sample headers
to 31, insert the format tag, everything else copied unchanged).

## Credits

- **Code**: Arnaud de Klerk (The File-Hunter) & Claude (Anthropic)
- **Photos**: Arnaud de Klerk / The File-Hunter (file-hunter.com), sourced
  from Tittygram
- **Music**: `mod.sll8`, by Sten Lysholm Larsen
- **Music player**: [ptplayer](https://aminet.net/package/mus/play/ptplayer)
  by Frank Wille, public domain
