; ============================================================================
; File-Hunter Slideshow -- stage-1 boot block
; ============================================================================
; Loaded by the Kickstart ROM's trackdisk boot code to chip RAM address $400
; (the first 1024 bytes of the disk = logical sectors 0-1) and entered at
; offset 12, i.e. right after the three header longwords below. Must be
; <= 1024 bytes total. makeadf.py patches the checksum longword after
; assembly using the standard Amiga boot-block checksum algorithm.
;
; This is plain trackdisk.device usage via Exec (in ROM) -- there is no
; AmigaDOS/dos.library/filesystem involved anywhere in this loader.
;
; Boot-code contract (confirmed against the official RKM "Amiga Floppy Boot
; Process and Physical Layout" reference -- verified after an earlier,
; unconventional approach of opening our own fresh trackdisk.device request
; from scratch turned out to hang on every blocking/polling I/O call. That
; approach was actively wrong, not just "extra work": the strap's own
; already-open request is the one whose task/scheduling context is known to
; work at this point in the boot process, since the strap just used it to
; read us in):
;   - Entry: A1 = an ALREADY-OPEN trackdisk.device IOStdReq (unit 0). We may
;     clobber the A1 *register*, but must not corrupt the request it points
;     at beyond what we intentionally set up for our own read.
;   - We must return (RTS), not jump, when we're done:
;       D0 = 0 and A0 = address to run next, on success (the strap frees
;            the boot sector/picture memory, CLOSES this I/O request, and
;            jumps to A0 itself -- we must NOT close it or jump ourselves).
;       D0 = non-zero on failure (the strap raises a system alert and
;            reboots).
;
; Because the strap closes the device before jumping to stage-2, stage-2
; cannot keep reusing this same request -- it opens its own (see
; diskio.s's DiskIO_Init), by which point normal Exec task scheduling is
; expected to be functioning normally.
; ============================================================================

        include "hw.i"
        include "layout.i"

        org     $400

; --- boot block header (must be the first 12 bytes) ---
        dc.b    'DOS',0                 ; id + flags (0, unused: no AmigaDOS filesystem)
        dc.l    0                       ; checksum -- patched by makeadf.py
        dc.l    0                       ; unused (would be root block ptr under AmigaDOS)

; --- entry point, offset 12 ---
; in: a1 = open trackdisk.device IOStdReq (unit 0), courtesy of the strap
start:
        move.l  4.w,a6                  ; a6 = ExecBase (always valid, fixed address)

        ; --- CMD_READ stage-2 into its fixed load address, reusing the
        ; request the strap handed us in A1 ---
        move.w  #CMD_READ,IO_COMMAND(a1)
        move.l  #STAGE2_LOAD_ADDR,IO_DATA(a1)
        move.l  #STAGE2_SECTORS*SECTOR_SIZE,IO_LENGTH(a1)
        move.l  #STAGE2_START_SECTOR*SECTOR_SIZE,IO_OFFSET(a1)
        jsr     _LVODoIO(a6)
        tst.b   IO_ERROR(a1)
        bne     readfail

        ; --- success: return to the strap, which cleans up and jumps to A0 ---
        moveq   #0,d0
        lea     STAGE2_LOAD_ADDR,a0
        rts

readfail:
        ; failure: non-zero D0 makes the strap raise a system alert/reboot
        moveq   #-1,d0
        rts

; Boot block must not exceed 1024 bytes (2 sectors) -- makeadf.py checks the
; assembled boot.bin's actual size and refuses to build if it doesn't fit,
; rather than relying on assembler-specific assertion directive syntax here.
