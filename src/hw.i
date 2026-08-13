; Amiga custom chip / CIA / Exec constants used by this project.
; Values are the standard, stable Amiga hardware/ABI offsets -- unchanged
; across all Kickstart versions and all OCS/ECS/AGA machines.

CUSTOM              EQU $DFF000

; --- custom chip registers (offsets from CUSTOM) ---
DMACONR              EQU $002
VPOSR                 EQU $004
VHPOSR                EQU $006
INTENAR               EQU $01C
INTREQR               EQU $01E
DSKLEN                 EQU $024
COP1LCH               EQU $080
COP1LCL               EQU $082
COPJMP1                EQU $088
DIWSTRT                EQU $08E
DIWSTOP                EQU $090
DDFSTRT                EQU $092
DDFSTOP                EQU $094
DMACON                  EQU $096
INTENA                  EQU $09A
INTREQ                   EQU $09C
BPL1PTH                  EQU $0E0        ; BPL2PTH=$0E4, BPL3PTH=$0E8, ... +4 each
BPLCON0                   EQU $100
BPLCON1                    EQU $102
BPLCON2                     EQU $104
BPL1MOD                      EQU $108
BPL2MOD                       EQU $10A
COLOR00                        EQU $180       ; COLOR01=$182 ... COLOR31=$1BE

AUD0LCH                         EQU $0A0       ; AUD1LCH=$0B0, AUD2LCH=$0C0, AUD3LCH=$0D0
AUD0LEN                          EQU $0A4
AUD0PER                           EQU $0A6
AUD0VOL                            EQU $0A8
AUD_CHAN_SPACING                    EQU $10

; --- DMACON / INTENA / INTREQ bits ---
DMAB_SETCLR       EQU 15
DMAB_BLTPRI         EQU 10
DMAB_DMAEN            EQU 9
DMAB_BPLEN              EQU 8
DMAB_COPEN                EQU 7
DMAB_BLTEN                  EQU 6
DMAB_SPREN                    EQU 5
DMAB_DSKEN                      EQU 4
DMAB_AUD0EN                       EQU 0
DMAB_AUD1EN                         EQU 1
DMAB_AUD2EN                           EQU 2
DMAB_AUD3EN                             EQU 3
DMAF_SETCLR       EQU $8000
DMAF_ALL             EQU $01FF        ; all standard DMA channel enable bits

INTB_SETCLR       EQU 15
INTB_INTEN          EQU 14
INTB_EXTER            EQU 13          ; CIA-B (disk index, serial, CIA-B timers)
INTB_VERTB               EQU 5
INTF_SETCLR       EQU $8000
INTF_INTEN          EQU $4000
INTF_EXTER            EQU $2000
INTF_VERTB               EQU $0020

BPLCON0B_HIRES      EQU 15
BPLCON0B_BPU2      EQU 14           ; bitplane-use bit 2 (of 3-bit BPU field, OCS)
BPLCON0B_COLOR       EQU 9
BPLCON0B_BPU0          EQU 12          ; BPU field is bits 14-12 on OCS (3 bits)
BPLCON0F_COLOR         EQU $0200

; --- CIA-A ($BFE001, odd addresses, registers spaced 256 bytes apart) ---
CIAAPRA               EQU $BFE001
CIAADDRA                EQU $BFE201

; --- CIA-B ($BFD000, even addresses) ---
CIABPRA                 EQU $BFD000
CIABTALO                  EQU $BFD400
CIABTAHI                   EQU $BFD500
CIABTBLO                     EQU $BFD600
CIABTBHI                       EQU $BFD700
CIABICR                          EQU $BFDD00
CIABCRA                            EQU $BFDE00
CIABCRB                              EQU $BFDF00

CIAICRB_TA        EQU 0
CIAICRB_TB          EQU 1
CIAICRB_SETCLR         EQU 7
CIACRAB_START      EQU 0
CIACRAB_RUNMODE       EQU 3           ; 0 = continuous
CIACRAB_LOAD             EQU 4

; E-clock: CIA timers are clocked at 1/10 of the colour clock, i.e.
; 715909Hz (NTSC) or 709379Hz (PAL) -- close enough that either constant
; is fine for a coarse PAL/NTSC frame-length measurement; the tempo timer
; itself uses the machine's own actual E-clock automatically since it's
; real hardware, not a software constant.
ECLOCK_PAL           EQU 709379
ECLOCK_NTSC            EQU 715909

; --- Exec / trackdisk.device ---
; struct Message / IORequest / IOStdReq offsets (stable across all KS versions)
LN_SUCC        EQU 0
LN_TYPE          EQU 8
LN_NAME            EQU 10
MN_REPLYPORT         EQU 14
MN_LENGTH              EQU 18
IO_DEVICE                EQU 20
IO_UNIT                    EQU 24
IO_COMMAND                   EQU 28
IO_FLAGS                       EQU 30
IO_ERROR                         EQU 31
IO_ACTUAL                          EQU 32
IO_LENGTH                            EQU 36
IO_DATA                                EQU 40
IO_OFFSET                                EQU 44
IOSTDREQ_SIZE                              EQU 48

; struct MsgPort offsets (struct Node mp_Node followed by port fields)
MP_LN_TYPE      EQU 8
MP_FLAGS          EQU 14
MP_SIGBIT           EQU 15
MP_SIGTASK             EQU 16
MP_MSGLIST                EQU 20            ; embedded struct List (14 bytes)
MSGPORT_SIZE                 EQU 34

; struct List offsets, relative to the start of the List struct itself
; (add MP_MSGLIST to get the absolute offset within a MsgPort)
LH_HEAD        EQU 0
LH_TAIL          EQU 4
LH_TAILPRED         EQU 8
LH_TYPE                EQU 12

NT_INTERRUPT      EQU 2
NT_MSGPORT          EQU 4
NT_MESSAGE            EQU 5
PA_SIGNAL                EQU 0

; struct Interrupt offsets (struct Node is_Node followed by is_Data/is_Code)
IS_DATA        EQU 14
IS_CODE          EQU 18
INTERRUPT_SIZE      EQU 22

CMD_READ       EQU 2
CMD_WRITE        EQU 3
TD_MOTOR           EQU 9

MEMF_PUBLIC     EQU 1
MEMF_CHIP         EQU 2
MEMF_CLEAR          EQU $10000

; Exec library vector offsets (LVOs), negative from the library base
_LVOAllocMem         EQU -198
_LVOFreeMem            EQU -210
_LVOFindTask             EQU -294
_LVOWait                   EQU -318
_LVOSignal                    EQU -324
_LVOAllocSignal                  EQU -330
_LVOFreeSignal                     EQU -336
_LVOOpenDevice                        EQU -444
_LVOCloseDevice                         EQU -450
_LVODoIO                                  EQU -456
_LVOSendIO                                  EQU -462
_LVOCheckIO                                   EQU -468
_LVOGetMsg                                      EQU -372
_LVOAddIntServer                            EQU -168
_LVORemIntServer                              EQU -174
_LVOAddTask                                     EQU -282
