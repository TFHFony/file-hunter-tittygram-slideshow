; ============================================================================
; File-Hunter Slideshow -- stage-2 main program
; ============================================================================
; Loaded whole by boot.s to the fixed address STAGE2_LOAD_ADDR. Per the
; documented boot-code contract, the strap module -- not boot.s itself --
; jumps here (after closing boot.s's trackdisk.device request and freeing
; the boot sector's memory), so no particular register state is assumed;
; we fetch ExecBase ourselves and open our own trackdisk.device instance
; (see diskio.s). No AmigaDOS anywhere -- only Exec (ROM-resident) and
; direct chipset register access.
;
; Flow: detect PAL/NTSC (needed for correct display geometry and, via
; player.s, correct music tempo) -> set up a static 6-bitplane EHB display
; -> load and start the background module -> loop forever: fade the current
; picture to black, load the next one from its fixed disk slot, fade it up
; from black, hold it for a few seconds, repeat.
;
; No copper list: this is a single static full-screen bitmap with CPU-driven
; palette fades timed to VBlank, so a copper list would add complexity for
; no benefit here (it earns its keep for per-line effects or multiple
; screens per frame, neither of which apply to a slideshow).
; ============================================================================

        include "hw.i"
        include "layout.i"

        org     STAGE2_LOAD_ADDR

; --- display geometry ---
; Standard reference values for a normal non-overscan low-res Amiga screen
; are DIWSTRT=$2C81/DIWSTOP=$F4C1/DDFSTRT=$0038/DDFSTOP=$00D0 (320x200,
; HSTART=$81). Our window is narrower (256px) and centered, so HSTART/HSTOP
; are shifted right by (320-256)/2=32 color clocks; DDFSTRT/DDFSTOP are left
; at the standard values since they already fetch a superset of pixels wide
; enough to cover our narrower, shifted window (the extra fetched pixels
; simply fall outside DIWSTRT/DIWSTOP and are never displayed). Vertically,
; height is 212 (12 more than the 200-line reference), so VSTART is nudged
; up slightly from the reference $2C to keep the image centered, with a
; separate PAL/NTSC value since the two have different total visible lines
; and this measurably affects framing on real hardware. All of this is the
; single most likely area to need visual tuning once this is actually run
; in an emulator -- these are best-effort formulaic values, not
; hardware-verified ones.
; Widened by 16px on the right vs. an exact 256px match (DIWSTOP byte +$10,
; DDFSTOP +$08 for one extra fetched word) -- the exact-256px version was
; consistently missing a sliver of content on the right edge, so this
; trades a possible thin, incorrect strip on the right (the buffer has no
; per-row padding, so the extra fetched word is technically the start of
; the next row) for reliably showing the whole intended image width.
; Horizontal shifted left by 8 CCK from the previous version (HSTART
; $A1->$99, HSTOP $B1->$A9) to recenter the 272px window: widening it
; earlier (to capture content that was going missing at exactly 256px)
; only extended the right edge, which left the window centered on CCK 297
; instead of the reference 289 -- a real rightward bias, not just a missing
; sliver. Width is unchanged (still 272px / 17 fetched words), just shifted.
DIWSTRT_PAL   EQU $2899
DIWSTOP_PAL   EQU $FCA9
DIWSTRT_NTSC  EQU $2299
DIWSTOP_NTSC  EQU $F6A9

FADE_STEPS    EQU 16
SLIDE_TICKS   EQU 250          ; 250 * 20ms = 5 seconds per slide

; ----------------------------------------------------------------------------
_start:
        move.l  4.w,a6                          ; a6 = ExecBase
        bsr     DiskIO_Init                      ; opens our own trackdisk.device

        bsr     DetectPALNTSC           ; -> d0.w = 0 PAL / 1 NTSC
        move.w  d0,pal_ntsc_flag

        bsr     SetupDisplayRegs
        bsr     SetupCopper              ; takes over from Kickstart's own
                                          ; copper list, and is what keeps
                                          ; BPL1PT..BPL6PT reset every frame
                                          ; (see SetupCopper for why this is
                                          ; required even for a static image)
        bsr     ZeroPalette

        ; --- load the music module (pre-converted at build time to 31-sample
        ; "M.K." format by mod2pt.py, since ptplayer.asm only understands
        ; that layout) and start playback via ptplayer.asm ---
        move.l  #MOD_START_SECTOR,d0
        move.l  #MOD_SECTORS,d1
        lea     MOD_BUF_ADDR,a0
        bsr     DiskIO_ReadSectors

        bsr     MusicStart

        ; --- load the palette table (one 64-byte CMAP entry per image) ---
        move.l  #PALETTE_START_SECTOR,d0
        move.l  #PALETTE_SECTORS,d1
        lea     PALETTE_BUF_ADDR,a0
        bsr     DiskIO_ReadSectors

        ; --- slideshow loop: fade out, load next, fade in, hold, repeat ---
        moveq   #0,d7                   ; d7 = current image index
.showloop:
        bsr     FadeToBlack

        move.w  d7,d0
        mulu.w  #IMAGE_SLOT_SECTORS,d0
        add.l   #IMAGE_START_SECTOR,d0
        move.l  #IMAGE_SLOT_SECTORS,d1
        lea     IMAGE_BUF_ADDR,a0
        bsr     DiskIO_ReadSectors

        bsr     SetBitplanePointers

        move.w  d7,d0
        bsr     FadeFromBlack

        bsr     HoldSlide

        addq.w  #1,d7
        cmp.w   #NUM_IMAGES,d7
        blt.s   .nowrap
        moveq   #0,d7
.nowrap:
        bra     .showloop

; ----------------------------------------------------------------------------
; WaitVBL -- busy-wait for the next vertical blank.
; ----------------------------------------------------------------------------
WaitVBL:
        movem.l d0,-(sp)
        move.w  #INTF_VERTB,CUSTOM+INTREQ      ; clear any pending VERTB flag
.poll:
        move.w  CUSTOM+INTREQR,d0
        btst    #INTB_VERTB,d0
        beq.s   .poll
        movem.l (sp)+,d0
        rts

; ----------------------------------------------------------------------------
; ReadCIABTimerA -> d0.w = current 16-bit CIA-B Timer A value.
; TALO must be read first: reading it latches TAHI so the pair stays
; consistent even if the timer ticks between the two byte reads.
; ----------------------------------------------------------------------------
ReadCIABTimerA:
        moveq   #0,d0
        move.b  CIABTALO,d0
        moveq   #0,d1
        move.b  CIABTAHI,d1
        lsl.w   #8,d1
        or.w    d1,d0
        rts

; ----------------------------------------------------------------------------
; DetectPALNTSC -> d0.w = 0 (PAL) or 1 (NTSC)
; Measures one VBlank-to-VBlank frame period against CIA-B's E-clock using
; Timer A as a free-running down-counter (borrowed briefly here, before
; Player_Start claims it permanently for music tempo). PAL frames are
; ~14188 E-clock ticks, NTSC frames ~11932 -- 13000 cleanly separates them.
; ----------------------------------------------------------------------------
DetectPALNTSC:
        movem.l d1-d2,-(sp)

        move.b  #$FF,CIABTALO
        move.b  #$FF,CIABTAHI
        move.b  #%00010001,CIABCRA      ; START=1, continuous, LOAD=1

        bsr     WaitVBL
        bsr     ReadCIABTimerA
        move.w  d0,d2                    ; d2 = reading #1

        bsr     WaitVBL
        bsr     ReadCIABTimerA           ; d0 = reading #2

        move.w  d2,d1
        sub.w   d0,d1                     ; d1 = ticks elapsed (counts down, so #1-#2)
        cmp.w   #13000,d1
        bhi.s   .ispal
        moveq   #1,d0                      ; NTSC
        bra.s   .done
.ispal:
        moveq   #0,d0                       ; PAL
.done:
        movem.l (sp)+,d1-d2
        rts

; ----------------------------------------------------------------------------
; SetupDisplayRegs -- static 6-bitplane EHB display, no copper list.
; ----------------------------------------------------------------------------
SetupDisplayRegs:
        movem.l d0,-(sp)
        move.w  pal_ntsc_flag,d0
        bne.s   .ntsc
        move.w  #DIWSTRT_PAL,CUSTOM+DIWSTRT
        move.w  #DIWSTOP_PAL,CUSTOM+DIWSTOP
        bra.s   .common
.ntsc:
        move.w  #DIWSTRT_NTSC,CUSTOM+DIWSTRT
        move.w  #DIWSTOP_NTSC,CUSTOM+DIWSTOP
.common:
        ; Fetch one word (16px) wider than our buffer's exact row width
        ; (17 words = 272px, vs the buffer's real 256px/32 bytes-per-line),
        ; matching the widened DIWSTOP above. BPL1MOD/BPL2MOD compensate so
        ; the pointer still only advances 32 bytes/line despite fetching
        ; 34: MOD = 32-34 = -2. The extra word fetched is technically the
        ; first word of the next row (the buffer has no per-row padding),
        ; visible as a thin strip at the right edge -- an accepted
        ; trade-off for reliably showing the full intended image width;
        ; fetching exactly 256px left a sliver of real content missing on
        ; the right instead.
        move.w  #$0050,CUSTOM+DDFSTRT           ; shifted left 8 CCK with DIWSTRT/DIWSTOP above
        move.w  #$00D0,CUSTOM+DDFSTOP
        move.w  #0,CUSTOM+BPLCON1
        move.w  #0,CUSTOM+BPLCON2
        move.w  #$FFFE,CUSTOM+BPL1MOD
        move.w  #$FFFE,CUSTOM+BPL2MOD
        ; BPU=6 (bits14-12=110), COLOR=1 (bit9) -> 6 bitplanes with HAM off
        ; is exactly EHB mode on OCS/ECS Denise (there is no separate
        ; explicit "EHB enable" bit).
        move.w  #$6200,CUSTOM+BPLCON0
        movem.l (sp)+,d0
        rts

; ----------------------------------------------------------------------------
; SetupCopper -- build a small copper list whose only job is to rewrite
; BPL1PT..BPL6PT at the top of every single frame, and hand control of the
; copper over to it (taking over from Kickstart's own list).
;
; This is required even for a completely static, non-scrolling display:
; Agnus does NOT reset the bitplane pointers on its own at the start of
; each frame -- it just keeps advancing them, line after line, frame after
; frame, forever. Without something rewriting them back to the start of
; our image buffer every frame, they drift through all of chip RAM over
; time (confirmed by testing: without this, the display showed what looked
; like chip RAM's entire contents scrolling past as "animation"). The
; copper is the standard, simplest way to do that rewrite every frame
; without CPU involvement.
;
; SetBitplanePointers (below) only patches this list's *data* words on each
; image change; the register-offset words and the end marker, set up here
; once, never need to change.
; ----------------------------------------------------------------------------
SetupCopper:
        movem.l d0-d2/a0,-(sp)
        lea     copperlist,a0
        moveq   #0,d1                    ; plane counter 0..5
        move.w  #BPL1PTH,d2               ; running register offset
.regloop:
        move.w  d2,(a0)+                   ; PTH register offset
        move.w  #0,(a0)+                    ; PTH data (patched later)
        addq.w  #2,d2
        move.w  d2,(a0)+                     ; PTL register offset
        move.w  #0,(a0)+                      ; PTL data (patched later)
        addq.w  #2,d2
        addq.w  #1,d1
        cmp.w   #6,d1
        blt.s   .regloop
        move.w  #$FFFF,(a0)+                    ; end-of-copper-list marker
        move.w  #$FFFE,(a0)+                     ; (a position that never matches)

        lea     copperlist,a0
        move.l  a0,d0
        swap    d0
        move.w  d0,CUSTOM+COP1LCH
        swap    d0
        move.w  d0,CUSTOM+COP1LCL
        move.w  #0,CUSTOM+COPJMP1          ; strobe: jump copper to COP1LC now
        move.w  #$8080,CUSTOM+DMACON       ; SETCLR + COPEN (enable copper DMA)
        movem.l (sp)+,d0-d2/a0
        rts

; ----------------------------------------------------------------------------
; SetBitplanePointers -- patch the copper list's data words to point at the
; just-loaded image buffer's 6 contiguous per-plane blocks. The copper
; itself applies these to BPL1PT..BPL6PT at the top of every frame from
; here on (see SetupCopper) -- we never write those registers directly.
; ----------------------------------------------------------------------------
SetBitplanePointers:
        movem.l d0-d1/a0-a1,-(sp)
        lea     IMAGE_BUF_ADDR,a0
        lea     copperlist+2,a1            ; -> BPL1PTH's data word
        moveq   #5,d1                       ; 6 planes
.loop:
        move.l  a0,d0
        swap    d0
        move.w  d0,(a1)                      ; PTH data word
        swap    d0
        move.w  d0,4(a1)                       ; PTL data word
        adda.l  #IMAGE_PLANE_SIZE,a0
        adda.w  #8,a1                            ; next plane's PTH data word
        dbra    d1,.loop
        movem.l (sp)+,d0-d1/a0-a1
        rts

; ----------------------------------------------------------------------------
; ScaleColor12 -- in: d0.w = $0RGB colour, d1.w = scale numerator (0..FADE_STEPS)
;                 out: d0.w = colour with each nibble scaled by d1/FADE_STEPS
; ----------------------------------------------------------------------------
ScaleColor12:
        movem.l d2-d4,-(sp)
        move.w  d0,d2
        move.w  d2,d3
        lsr.w   #8,d3
        and.w   #$F,d3
        mulu.w  d1,d3
        lsr.w   #4,d3
        and.w   #$F,d3
        lsl.w   #8,d3
        move.w  d3,d4
        move.w  d2,d3
        lsr.w   #4,d3
        and.w   #$F,d3
        mulu.w  d1,d3
        lsr.w   #4,d3
        and.w   #$F,d3
        lsl.w   #4,d3
        or.w    d3,d4
        move.w  d2,d3
        and.w   #$F,d3
        mulu.w  d1,d3
        lsr.w   #4,d3
        and.w   #$F,d3
        or.w    d3,d4
        move.w  d4,d0
        movem.l (sp)+,d2-d4
        rts

; ----------------------------------------------------------------------------
; ZeroPalette -- black out the live COLOR registers and the shadow copy.
; ----------------------------------------------------------------------------
ZeroPalette:
        movem.l d0/a0,-(sp)
        lea     CUSTOM+COLOR00,a0
        moveq   #31,d0
.loop:
        move.w  #0,(a0)+
        dbra    d0,.loop
        lea     current_palette,a0
        moveq   #31,d0
.loop2:
        clr.w   (a0)+
        dbra    d0,.loop2
        movem.l (sp)+,d0/a0
        rts

; ----------------------------------------------------------------------------
; FadeToBlack -- fades current_palette (the live, on-screen colours) down to
; black over FADE_STEPS VBlanks, then zeroes the shadow copy to match.
; ----------------------------------------------------------------------------
FadeToBlack:
        movem.l d0-d5/a0-a1,-(sp)
        move.w  #FADE_STEPS,d5
.loop:
        bsr     WaitVBL
        subq.w  #1,d5
        lea     current_palette,a0
        lea     CUSTOM+COLOR00,a1
        moveq   #31,d4
.colloop:
        move.w  (a0)+,d0
        move.w  d5,d1
        bsr     ScaleColor12
        move.w  d0,(a1)+
        dbra    d4,.colloop
        tst.w   d5
        bne.s   .loop

        lea     current_palette,a0
        moveq   #31,d0
.zloop:
        clr.w   (a0)+
        dbra    d0,.zloop
        movem.l (sp)+,d0-d5/a0-a1
        rts

; ----------------------------------------------------------------------------
; FadeFromBlack -- in: d0.w = image index. Fades from black up to that
; image's palette (PALETTE_BUF_ADDR + index*PALETTE_ENTRY_SIZE) over
; FADE_STEPS VBlanks, then copies the target into current_palette.
; ----------------------------------------------------------------------------
FadeFromBlack:
        movem.l d0-d6/a0-a2,-(sp)
        move.w  d0,d6
        mulu.w  #PALETTE_ENTRY_SIZE,d6
        lea     PALETTE_BUF_ADDR,a2
        adda.l  d6,a2                    ; a2 -> target palette (32 words)

        moveq   #0,d5
.loop:
        bsr     WaitVBL
        addq.w  #1,d5
        move.l  a2,a0
        lea     CUSTOM+COLOR00,a1
        moveq   #31,d4
.colloop:
        move.w  (a0)+,d0
        move.w  d5,d1
        bsr     ScaleColor12
        move.w  d0,(a1)+
        dbra    d4,.colloop
        cmp.w   #FADE_STEPS,d5
        blt.s   .loop

        move.l  a2,a0
        lea     current_palette,a1
        moveq   #31,d0
.copyloop:
        move.w  (a0)+,(a1)+
        dbra    d0,.copyloop

        movem.l (sp)+,d0-d6/a0-a2
        rts

; ----------------------------------------------------------------------------
; HoldSlide -- wait SLIDE_TICKS ticks (20ms each -> PAL/NTSC-neutral
; wall-clock time), using MusicInterrupt's free-running tick counter.
;
; Uses D2, not D0/D1, to hold the target across the wait loop. MusicInterrupt
; deliberately does NOT preserve D0 (it's used to set the exit Z flag for
; the AddIntServer chain), and per the documented contract D1 is scratch
; too -- any interrupt (ours or anyone else's) can clobber either at any
; time. A register that's genuinely preserved across our own interrupt
; (D2-D7/A2-A6) is required for anything held across a loop that runs with
; interrupts enabled, which this does.
; ----------------------------------------------------------------------------
HoldSlide:
        movem.l d2,-(sp)
        move.l  total_ticks,d2
        add.l   #SLIDE_TICKS,d2
.wait:
        cmp.l   total_ticks,d2
        bhi.s   .wait
        movem.l (sp)+,d2
        rts

; ----------------------------------------------------------------------------
; MusicStart -- start ptplayer.asm (MINIMAL/VBLANK_MUSIC build, see bottom of
; file) on the already-loaded, build-time-converted MOD, and install our own
; VBlank interrupt to drive it at a PAL/NTSC-neutral 50 ticks/sec.
;
; ptplayer with VBLANK_MUSIC=1 skips its own CIA-B Timer-A tempo interrupt
; entirely -- we call _mt_music ourselves instead, from MusicInterrupt below,
; using the same Bresenham-style rate accumulator this project's own player
; used (PAL VBlank=50Hz needs no correction; NTSC VBlank=60Hz fires a tick on
; 5 of every 6 frames -- both average out to exactly 50 ticks/sec). ptplayer
; still uses CIA-B Timer-B internally (via _mt_install_cia) for DMA-enable/
; repeat-pointer timing, installed by writing directly to the CPU's level-6
; autovector rather than through Exec's AddIntServer chain.
; ----------------------------------------------------------------------------
MusicStart:
        movem.l d0-d1/a0-a1/a6,-(sp)

        clr.w   tick_accum
        tst.w   pal_ntsc_flag
        beq.s   .pal
        move.w  #60,vblank_rate
        moveq   #0,d0                    ; ptplayer PALflag: 0 = NTSC
        bra.s   .havepalflag
.pal:
        move.w  #50,vblank_rate
        moveq   #1,d0                     ; ptplayer PALflag: nonzero = PAL
.havepalflag:
        lea     CUSTOM,a6
        suba.l  a0,a0                      ; VectorBase = 0 (plain 68000, no VBR)
        jsr     _mt_install_cia

        lea     CUSTOM,a6
        lea     MOD_BUF_ADDR,a0
        suba.l  a1,a1                       ; a1 = NULL: samples follow the patterns
        moveq   #0,d0                        ; start at song position 0
        jsr     _mt_init

        lea     music_interrupt_struct,a1
        clr.l   (a1)
        clr.l   4(a1)
        move.b  #NT_INTERRUPT,8(a1)
        move.b  #0,9(a1)
        lea     music_int_name,a0
        move.l  a0,10(a1)
        clr.l   IS_DATA(a1)
        lea     MusicInterrupt(pc),a0
        move.l  a0,IS_CODE(a1)

        move.l  4.w,a6                      ; back to ExecBase for AddIntServer
        moveq   #INTB_VERTB,d0
        jsr     _LVOAddIntServer(a6)

        move.w  #INTF_SETCLR+INTF_INTEN+INTF_VERTB,CUSTOM+INTENA

        movem.l (sp)+,d0-d1/a0-a1/a6
        rts

; ----------------------------------------------------------------------------
; MusicInterrupt -- VBlank interrupt server (is_Code). Drives total_ticks
; (used by HoldSlide) and calls ptplayer's _mt_music at a PAL/NTSC-neutral
; 50 ticks/sec via the accumulator described above MusicStart.
;
; Z-flag exit convention per the documented AddIntServer contract (see the
; extensive comment this project's own player.s originally had on this):
; D0 is deliberately left out of the preserved register set so it's free to
; set the exit condition as the very last thing before rts.
; ----------------------------------------------------------------------------
MusicInterrupt:
        movem.l d1-d7/a0-a6,-(sp)
        move.w  #INTF_VERTB,CUSTOM+INTREQ

        addq.l  #1,total_ticks

        move.w  tick_accum,d1
        add.w   #50,d1
        cmp.w   vblank_rate,d1
        blt.s   .notick
        sub.w   vblank_rate,d1
        move.w  d1,tick_accum
        lea     CUSTOM,a6
        jsr     _mt_music
        movem.l (sp)+,d1-d7/a0-a6
        moveq   #-1,d0                    ; Z clear: this interrupt was ours
        rts
.notick:
        move.w  d1,tick_accum
        movem.l (sp)+,d1-d7/a0-a6
        moveq   #-1,d0                       ; still ours (every VBlank), just no tick this time
        rts

; --- storage ---
pal_ntsc_flag:
        dc.w    0
total_ticks:
        dc.l    0
tick_accum:
        dc.w    0
vblank_rate:
        dc.w    0

music_int_name:
        dc.b    'FHSlideshowMusic',0
        even

        cnop    0,2
current_palette:
        ds.w    32

        cnop    0,4
copperlist:
        ds.w    6*4+2           ; 6 planes * (reg,data,reg,data) + end marker

        cnop    0,4
music_interrupt_struct:
        ds.b    INTERRUPT_SIZE

        include "diskio.s"

MINIMAL          EQU 1
VBLANK_MUSIC     EQU 1
        include "ptplayer.asm"
