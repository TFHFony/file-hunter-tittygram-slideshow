; ============================================================================
; File-Hunter Slideshow -- stage-2 raw sector I/O
; ============================================================================
; Included directly into main.s (single assembly unit, no separate linker
; step).
;
; boot.s reused the trackdisk.device IOStdReq the boot strap handed it in
; A1 for its own CMD_READ, then returned (per the documented boot-code
; contract) rather than jumping directly to us. The strap closes that
; request as part of its cleanup before jumping here, so we can't reuse it
; -- we open our own trackdisk.device instance instead, same as any normal
; Exec program would, since by this point (after a proper return through
; the strap rather than a raw jump) normal task scheduling is expected to
; be functioning.
; ============================================================================

; DiskIO_Init
; in: a6 = ExecBase
; Opens our own trackdisk.device (unit 0). Call once, at stage-2 entry,
; before any other DiskIO_* routine.
DiskIO_Init:
        move.l  a6,g_execbase

        ; --- FindTask(NULL) -> d0 = ThisTask ---
        moveq   #0,d0
        move.l  d0,a1
        jsr     _LVOFindTask(a6)
        move.l  d0,g_sigtask

        ; --- AllocSignal(-1) -> d0 = free signal bit ---
        moveq   #-1,d0
        jsr     _LVOAllocSignal(a6)
        move.b  d0,g_sigbit

        ; --- build the MsgPort by hand ---
        lea     g_port,a0
        moveq   #0,d0
        move.l  d0,(a0)                 ; ln_Succ = 0
        move.l  d0,4(a0)                ; ln_Pred = 0
        move.b  #NT_MSGPORT,MP_LN_TYPE(a0)
        move.b  #PA_SIGNAL,MP_FLAGS(a0)
        move.b  g_sigbit,MP_SIGBIT(a0)
        move.l  g_sigtask,MP_SIGTASK(a0)
        lea     MP_MSGLIST+LH_HEAD(a0),a1
        lea     MP_MSGLIST+LH_TAIL(a0),a2
        move.l  a2,MP_MSGLIST+LH_HEAD(a0)
        move.l  d0,MP_MSGLIST+LH_TAIL(a0)
        move.l  a1,MP_MSGLIST+LH_TAILPRED(a0)

        ; --- build the IOStdReq by hand (ln_Type left 0, NOT NT_MESSAGE) ---
        lea     g_ioreq,a0
        moveq   #0,d1
        move.l  d1,(a0)
        move.l  d1,4(a0)
        lea     g_port,a1
        move.l  a1,MN_REPLYPORT(a0)
        move.w  #IOSTDREQ_SIZE,MN_LENGTH(a0)

        ; --- OpenDevice("trackdisk.device", 0, ioreq, 0) ---
        lea     g_tdname,a0
        moveq   #0,d0
        lea     g_ioreq,a1
        moveq   #0,d1
        jsr     _LVOOpenDevice(a6)
        ; nothing sensible to do on failure here -- if this fails every
        ; subsequent read will too, and will report a non-zero io_Error.
        rts

; DiskIO_ReadSectors
; in:  d0.l = start sector (logical, 0-based), d1.l = sector count,
;      a0   = destination buffer (must be big enough for count*SECTOR_SIZE)
; out: d0.l = 0 on success, non-zero io_Error code on failure
; trashes: d0/d1/a1/a6
DiskIO_ReadSectors:
        movem.l d2,-(sp)
        move.l  d0,d2                   ; d2 = start sector (word range is plenty)
        lea     g_ioreq,a1
        move.w  #CMD_READ,IO_COMMAND(a1)
        move.l  a0,IO_DATA(a1)
        mulu.w  #SECTOR_SIZE,d1
        move.l  d1,IO_LENGTH(a1)
        mulu.w  #SECTOR_SIZE,d2
        move.l  d2,IO_OFFSET(a1)
        move.l  g_execbase(pc),a6
        jsr     _LVODoIO(a6)
        lea     g_ioreq,a1
        moveq   #0,d0
        move.b  IO_ERROR(a1),d0
        movem.l (sp)+,d2
        rts

; --- storage ---
g_tdname:
        dc.b    'trackdisk.device',0
        even

g_execbase:
        dc.l    0
g_sigtask:
        dc.l    0
g_sigbit:
        dc.b    0
        even

        cnop    0,4
g_port:
        ds.b    MSGPORT_SIZE
g_ioreq:
        ds.b    IOSTDREQ_SIZE
