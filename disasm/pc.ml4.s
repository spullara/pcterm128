; =============================================================================
; pc.ml4.s - PC-Term 128, module PC.ML4: "C128 TURBODISK" fast loader
; =============================================================================
; Original file : pc.ml4 (C128 PRG, load address $1300, 977 bytes, to $16D0)
; Assembler     : ca65/ld65 (cc65 2.19). Rebuild and compare with
;                 disasm/verify.sh
; Loaded by     : pcboot line 1031  BLOAD"pc.ml4",p4864,u(dv%(1)) and
;                 then "sys4864" is typed through the keyboard buffer.
; Called by     : $1300 SYS4864  Enable   (pcboot line 1031)
;                 $1303 SYS4867  Disable  (pcterm line 0: IF PEEK(4906)=67,
;                       that is "C" of the message at $132A, the turbo is
;                       still in memory, so "sys4867:run1" is typed)
;
; What it is: a fast LOAD for a 1541-type drive. Enable points the
; KERNAL LOAD vector ILOAD ($0330) at TurboLoad. A normal LOAD of a
; PRG file then:
;   1. copies the file name into the drive-code image (FNBUF, $16C0),
;   2. uploads 512 bytes ($1500-$16FF) to drive RAM $0500-$06FF with
;      "M-W" commands (UploadDrive),
;   3. starts the drive code with the "UC" (= U3, JMP $0500) command,
;   4. receives each 256-byte sector with a 2-bit serial protocol
;      (RecvBlock) and stores the data in memory.
; Verify, and LOAD"$", go to the normal KERNAL LOAD.
; The README called this "routines for increasing the disk speed"; that
; is correct (it speeds up LOAD only; SAVE is not changed).
;
; Layout:
;   $1300-$14EC  C128 code and messages
;   $14ED-$14F2  "M-W" command template
;   $14F3-$14FF  $FF fill
;   $1500-$16B5  1541 drive code, assembled for drive address $0500
;   $16B6-$16BF  $FF fill
;   $16C0-$16D0  file name buffer (drive $06C0), $A0 = shifted space
; =============================================================================

        .setcpu "6502"

; ===== C128 symbols ==========================================================
; KERNAL jump table
SECOND  := $FF93                ; send secondary address after LISTEN
CIOUT   := $FFA8                ; send byte on serial bus
UNLSN   := $FFAE                ; send UNLISTEN
LISTEN  := $FFB1                ; send LISTEN to device in A
; KERNAL internals (not in the jump table)
KLOAD   := $F26C                ; normal LOAD routine (default ILOAD value)
FNFETCH := $F7AE                ; ? lda (FNADR),y from bank FNBANK
EALSTA  := $F7BF                ; ? sta (EAL),y in bank BA (X changed)
; Screen editor jump table
EDPRINT := $C00C                ; print character in A ; ?
; Zero page / system RAM
VERCK   := $93                  ; 0 = LOAD, else VERIFY
BSOUR   := $95                  ; serial byte buffer (used as temp)
EAL     := $AE                  ; current load address (2 bytes)
FNLEN   := $B7                  ; file name length
SA      := $B9                  ; secondary address
FA      := $BA                  ; device number
MEMUSS  := $C3                  ; load address from caller X/Y (2 bytes)
SAVD030 := $FA                  ; saved $D030 (program use)
INDEX   := $FB                  ; byte index / pointer (program use)
UPSRC   := $FB                  ; UploadDrive: host pointer $FB/$FC
UPDST   := $FD                  ; UploadDrive: drive address $FD/$FE
UPCNT   := $FF                  ; UploadDrive: chunks left
ILOAD   := $0330                ; KERNAL LOAD vector (2 bytes)
SECBUF  := $0C00                ; received sector (256 bytes)
                                ; +0 next track (0 = last, $FF = error)
                                ; +1 next sector / last byte index
                                ; +2,+3 load address in first sector
; Hardware
VICCR1  := $D011                ; VIC control register 1 (bit 4 = screen on)
VICCLK  := $D030                ; VIC clock register (bit 0 = 2 MHz)
CI2PRA  := $DD00                ; CIA 2 port A: serial bus lines
                                ; bit 7 DATA in, bit 6 CLK in, bit 4 CLK out

ERR_NOTFOUND = 4                ; KERNAL error: FILE NOT FOUND

        .word   $1300           ; PRG load address
        .org    $1300

; -----------------------------------------------------------------------------
; $1300 SYS4864 -> Enable
; -----------------------------------------------------------------------------
        jmp     Enable

; -----------------------------------------------------------------------------
; Disable - $1303 (SYS4867)
; Purpose : Restore the normal KERNAL LOAD and print "C128 TURBODISK
;           DISABLED".
; Inputs  : none.  Outputs: ILOAD = $F26C. A, Y changed.
; -----------------------------------------------------------------------------
Disable:
        lda     #<KLOAD
        sta     ILOAD
        lda     #>KLOAD
        sta     ILOAD+1
        ldy     #MsgOff-Msgs

; -----------------------------------------------------------------------------
; PrintMsg - $130F
; Purpose : Print a zero-terminated message.
; Inputs  : Y = offset of the message from Msgs.
; -----------------------------------------------------------------------------
PrintMsg:
        lda     Msgs,y
        beq     @done
        jsr     EDPRINT
        iny
        bne     PrintMsg
@done:
        rts

; -----------------------------------------------------------------------------
; Enable - $131B (SYS4864 via the JMP at $1300)
; Purpose : Point ILOAD at TurboLoad and print "C128 TURBODISK ENABLED".
; Inputs  : none.  Outputs: ILOAD = $135C. A, Y changed.
; -----------------------------------------------------------------------------
Enable:
        lda     #<TurboLoad
        sta     ILOAD
        lda     #>TurboLoad
        sta     ILOAD+1
        ldy     #MsgOn-Msgs
        bne     PrintMsg        ; always taken

; ---- messages ($1329) -------------------------------------------------------
Msgs:
MsgOff: .byte   $0D, "C128 TURBODISK DISABLED", $0D, $00
MsgOn:  .byte   $0D, "C128 TURBODISK ENABLED", $0D, $00

; -----------------------------------------------------------------------------
; TurboLoad - $135C (reached through ILOAD from KERNAL LOAD)
; Purpose : Fast LOAD of a PRG file from a 1541-type drive.
; Inputs  : A = 0 for LOAD (else VERIFY); FA, SA, FNLEN, FNADR/FNBANK,
;           MEMUSS ($C3/$C4) as set by the KERNAL LOAD entry.
; Outputs : C clear = OK, X/Y = end address + 1 (lo/hi);
;           C set = error, A = 4 (file not found) or A = 0 (drive error
;           during the load ; ?).
; Note    : Interrupts are off and the VIC screen is blanked during the
;           transfer; VIC clock register $D030 is saved and restored.
;           Only the file name part after "0:" (if any) is sent.
; -----------------------------------------------------------------------------
TurboLoad:
        sta     VERCK
        lda     VERCK
        beq     DoLoad
NormalLoad:
        lda     VERCK
        jmp     KLOAD           ; verify or directory: normal LOAD

DoLoad:
        ldx     #$10            ; fill the file name buffer with $A0
        lda     #$A0
@fill:  sta     FNBUF,x
        dex
        bpl     @fill
        ldy     #$00
        jsr     FNFETCH         ; first character of the name
        cmp     #'$'
        beq     NormalLoad      ; directory -> normal LOAD
        lda     VICCLK
        sta     SAVD030
        lda     #$0B
        sta     VICCR1          ; screen off
        lda     #$FD
        sta     VICCLK          ; 2 MHz
        ldy     #$01
        jsr     FNFETCH
        cmp     #':'            ; "0:name"? then skip "0:"
        beq     @skip2
        ldy     #$00
        beq     @copy           ; always taken
@skip2: iny
@copy:  ldx     #$FF
@cpy:   inx
        jsr     FNFETCH
        sta     FNBUF,x
        iny
        cpy     FNLEN
        bcc     @cpy
        jsr     UploadDrive
        lda     FA              ; send "UC" (= U3: JMP $0500) on channel 15
        jsr     LISTEN
        lda     #$6F
        jsr     SECOND
        lda     #'U'
        jsr     CIOUT
        lda     #'C'
        jsr     CIOUT
        jsr     UNLSN
        sei
        jsr     RecvBlock       ; first sector (or error block)
        bit     SECBUF
        bmi     ErrNotFound     ; track $FF = file not found
        ldy     MEMUSS          ; SA = 0: load at caller address
        ldx     MEMUSS+1
        lda     SA
        beq     @addr
        ldy     SECBUF+2        ; SA <> 0: load at file address
        ldx     SECBUF+3
@addr:  sty     EAL
        stx     EAL+1
        ldx     #$04            ; data starts after link + load address
        lda     SECBUF
        beq     LastBlock       ; one-sector file
        jsr     StoreFrom
NextBlock:
        jsr     RecvBlock
        lda     SECBUF
        bmi     ErrDrive        ; $FF = error in drive
        beq     LastBlk2
        jsr     StoreFull
        jmp     NextBlock

LastBlk2:
        ldx     #$02
; LastBlock - $13F6: store SECBUF+X .. SECBUF+(SECBUF+1), then finish
LastBlock:
        stx     INDEX
        ldy     #$00
@loop:  lda     SECBUF,x
        jsr     EALSTA
        iny
        inc     INDEX
        ldx     INDEX
        cpx     SECBUF+1
        bcc     @loop
        lda     SECBUF,x        ; last byte (index = SECBUF+1)
        jsr     EALSTA
        iny
        jsr     AddEAL
        clc
; LoadExit - $1415: restore VIC, return X/Y = EAL
LoadExit:
        ldx     SAVD030
        stx     VICCLK
        ldx     #$1B
        stx     VICCR1          ; screen on
        ldx     EAL
        ldy     EAL+1
        cli
        rts

ErrNotFound:
        lda     #ERR_NOTFOUND
        .byte   $2C             ; BIT abs: skip the next LDA
ErrDrive:
        lda     #$00            ; ?
        sec
        bcs     LoadExit        ; always taken

; -----------------------------------------------------------------------------
; StoreFull - $142D / StoreFrom - $142F
; Purpose : Store SECBUF+X .. SECBUF+$FF at (EAL) and add the count to EAL.
;           StoreFull starts at X = 2 (after the track/sector link).
; Inputs  : X = first index (StoreFrom); EAL = destination.
; Outputs : EAL advanced. A, X, Y, INDEX changed.
; -----------------------------------------------------------------------------
StoreFull:
        ldx     #$02
StoreFrom:
        stx     INDEX
        ldy     #$00
@loop:  lda     SECBUF,x
        jsr     EALSTA
        iny
        inc     INDEX
        ldx     INDEX
        bne     @loop
; AddEAL - $1440: EAL = EAL + Y
AddEAL:
        clc
        tya
        adc     EAL
        sta     EAL
        lda     EAL+1
        adc     #$00
        sta     EAL+1
        rts

; -----------------------------------------------------------------------------
; RecvBlock - $144D
; Purpose : Receive 256 bytes from the drive code (DrvSend) into SECBUF.
; Protocol: per byte: wait for DATA in = 0 (drive ready), set CLK out,
;           wait for DATA in = 1 (drive answer), release CLK, wait a
;           short time, then read 4 times DATA/CLK (2 bits each, bit 7
;           first). The bits come in inverted, so the byte is EOR $FF.
; Inputs  : none.  Outputs: SECBUF filled. A, X, Y changed.
; Note    : Runs at 1 MHz ($D030 = $FC) because the timing is fixed;
;           sets 2 MHz ($FD) again at the end.
; -----------------------------------------------------------------------------
RecvBlock:
        lda     #$FC
        sta     VICCLK          ; 1 MHz
        ldy     #$00
@byte:  lda     CI2PRA
        bmi     @byte           ; wait DATA in = 0
        lda     #$17
        sta     CI2PRA          ; CLK out on
@ack:   lda     CI2PRA
        bpl     @ack            ; wait DATA in = 1
        lda     #$07
        sta     CI2PRA          ; CLK out off
        ldx     #$04
@dly:   dex
        nop
        bne     @dly
        ldx     #$04
@bits:  lda     CI2PRA
        asl     a               ; C = DATA in
        php
        asl     a               ; C = CLK in
        rol     BSOUR
        plp
        rol     BSOUR
        dex
        bne     @bits
        lda     BSOUR
        eor     #$FF
        sta     SECBUF,y
        iny
        bne     @byte
        lda     #$FD
        sta     VICCLK          ; 2 MHz
        rts

; -----------------------------------------------------------------------------
; UploadDrive - $148E
; Purpose : Copy $1500-$16FF (drive code + file name) to drive RAM
;           $0500-$06FF with 16 "M-W" commands of 32 bytes each.
; Inputs  : FA = device.  Outputs: drive RAM written. $FB-$FF changed.
; Note    : $16D1-$16FF is past the end of this file; whatever is in
;           memory there is sent too. ; ?
; -----------------------------------------------------------------------------
UploadDrive:
        lda     #$10
        sta     UPCNT
        lda     #$00
        sta     UPSRC
        sta     UPDST
        lda     #>DriveCode     ; $15
        sta     UPSRC+1
        lda     #>DRVORG        ; $05
        sta     UPDST+1
@chunk: lda     FA
        jsr     LISTEN
        lda     #$6F            ; channel 15
        jsr     SECOND
        lda     UPDST
        ldy     UPDST+1
        sta     MWCmd+3
        sty     MWCmd+4
        ldy     #$00
@hdr:   lda     MWCmd,y         ; "M-W" lo hi $20
        jsr     CIOUT
        iny
        cpy     #$06
        bne     @hdr
        ldy     #$00
@data:  lda     (UPSRC),y
        jsr     CIOUT
        iny
        cpy     #$20
        bcc     @data
        lda     UPSRC           ; C is set here, so add $1F+1
        adc     #$1F
        sta     UPSRC
        lda     UPSRC+1
        adc     #$00
        sta     UPSRC+1
        lda     UPDST           ; C is clear here
        adc     #$20
        sta     UPDST
        lda     UPDST+1
        adc     #$00
        sta     UPDST+1
        jsr     UNLSN
        dec     UPCNT
        bne     @chunk
        rts

; ---- "M-W" command template ($14ED): "M-W", address lo, hi, 32 bytes ----
MWCmd:  .byte   "M-W", $00, $00, $20

        .res    $1500 - *, $FF  ; $14F3-$14FF fill

        .assert * = $1500, error, "drive code must start at $1500"
DriveCode:

; =============================================================================
; 1541 drive code. Runs in the drive at $0500 (started by "UC").
; =============================================================================
DRVORG  = $0500
        .org    DRVORG

; ---- 1541 symbols -----------------------------------------------------------
; ROM
D_INITDR := $D042               ; initialize drive (read BAM) ; ?
D_IDLE   := $D945               ; ? end of command / back to DOS
D_CMDERR := $C1C8               ; DOS error: A = error number
D_GCRDEC := $F8E0               ; decode GCR data block in buffer to binary
D_CHKSUM := $F5E9               ; compute data block checksum (A)
D_HDRGCR := $F934               ; convert header $16-$1A to GCR at $24
; I/O
D_SERIAL := $1800               ; VIA1 port B: bit 1 DATA out, bit 3 CLK out,
                                ;   bit 2 CLK in (set = line low)
D_T1HI   := $1805               ; VIA1 timer 1 high byte (timeout)
D_DCTRL  := $1C00               ; VIA2 port B: bit 7 = 0 at SYNC
D_DDATA  := $1C01               ; VIA2 port A: byte from the disk head
D_T1LHI  := $1C07               ; VIA2 timer 1 latch high (default $3A)
D_PCR    := $1C0C               ; VIA2 peripheral control (read mode)
; Zero page
D_JOB0   := $00                 ; job code for buffer 0 ($0300)
D_TRK0   := $06                 ; track for buffer 0
D_SEC0   := $07                 ; sector for buffer 0
D_DISKID := $12                 ; disk ID (2 bytes)
D_HDR    := $16                 ; header: ID ID track sector checksum
D_HDRGCRB:= $24                 ; header in GCR (8 bytes compared)
D_BUFPNT := $30                 ; buffer pointer (2 bytes)
D_ZP32   := $32                 ; ? set to $0006 before reading
D_BLKID  := $38                 ; data block ID read from disk
D_CHKBYT := $3A                 ; data block checksum read from disk
D_DIRPTR := $3B                 ; directory entry pointer (program use)
D_ERRSAV := $44                 ; error number (program use)
D_DBID   := $47                 ; expected data block ID ($07)
D_ENTRY  := $4B                 ; directory entry 0..7 (program use)
D_SNDBYT := $85                 ; byte being sent (program use)
D_RETRY  := $86                 ; read retries (program use)
; RAM
D_BUF0   := $0300               ; buffer 0: +0 track, +1 sector, data
D_OVFL   := $0100               ; GCR overflow bytes ($01BA-$01FF)

JOB_SEEK = $B0

; -----------------------------------------------------------------------------
; DrvMain - drive $0500 (host $1500)
; Purpose : Find the file named in DrvFName in the directory (track 18)
;           and send all its sectors to the C128.
; Inputs  : DrvFName ($06C0, 16 chars, $A0 padded, "*" and "?" allowed).
; Outputs : each sector (256 bytes, link bytes included) sent by DrvSend.
;           Not found: one block with track = $FF is sent, then DOS
;           continues at D_IDLE.
; Note    : Only closed PRG files (type $82, lock bit ignored) match.
;           Only name characters 1-15 are compared (Y = 3..$11). ; ?
; -----------------------------------------------------------------------------
DrvMain:
        jsr     D_INITDR
        sei
        lda     #$15
        sta     D_T1LHI         ; ? faster head stepping
        lda     #18             ; directory: track 18, sector 1
        ldy     #1
        sta     D_BUF0
        sty     D_BUF0+1
DirSector:
        jsr     DrvRead
        lda     #>D_BUF0
        sta     D_DIRPTR+1
        ldx     #$00
        stx     D_ENTRY
        beq     NextEntry       ; always taken
CheckEntry:
        ldy     #$00
        lda     (D_DIRPTR),y    ; file type
        and     #$BF            ; ignore lock bit
        cmp     #$82            ; closed PRG?
        bne     NoMatch
        iny                     ; Y = 3: first name character
        iny
        iny
@cmp:   lda     DrvFName-3,y
        cmp     #'*'
        beq     Found
        cmp     #'?'
        beq     @ok
        cmp     (D_DIRPTR),y
        bne     NoMatch
@ok:    iny
        cpy     #$12            ; first 15 characters equal ; ? 16th never compared
        beq     Found
        bne     @cmp            ; always taken
NoMatch:
        inc     D_ENTRY
        ldx     D_ENTRY
        cpx     #$08
        beq     NextDirSec
NextEntry:
        lda     EntryOfs,x
        sta     D_DIRPTR
        bne     CheckEntry      ; always taken
NextDirSec:
        lda     D_BUF0          ; link track
        beq     NotFound        ; last directory sector
        ldy     D_BUF0+1
        jmp     DirSector

NotFound:
        lda     #$FF
        sta     D_BUF0          ; error marker for the C128
        jsr     DrvSend
        lda     #$3A
        sta     D_T1LHI
        cli
        jmp     D_IDLE

; offsets of the 8 directory entries in a sector (file type byte)
EntryOfs:
        .byte   $02, $22, $42, $62, $82, $A2, $C2, $E2

; ---- file found: send all its sectors ($0576) ----
Found:
        inc     D_DIRPTR        ; -> entry+3: first track/sector of file
        ldy     #$00
        lda     (D_DIRPTR),y
        sta     D_BUF0
        iny
        lda     (D_DIRPTR),y
        sta     D_BUF0+1
@next:  jsr     DrvRead
        jsr     DrvSend
        lda     D_BUF0          ; link track 0 = last sector
        bne     @next
        lda     #$3A
        sta     D_T1LHI
        rts

; -----------------------------------------------------------------------------
; DrvSend - drive $0596
; Purpose : Send the 256 bytes of D_BUF0 to the C128 (see RecvBlock).
;           Per byte: pull DATA low, wait for CLK from the C128, release,
;           then send 4 bit pairs: bit 3 (CLK) = higher bit, bit 1
;           (DATA) = lower bit, high bits first.
; Inputs  : D_BUF0.  Outputs: none. A, X, Y changed.
; -----------------------------------------------------------------------------
DrvSend:
        ldy     #$00
@byte:  lda     D_BUF0,y
        sta     D_SNDBYT
        lda     #$02
        sta     D_SERIAL        ; DATA low = "ready"
@wait:  lda     D_SERIAL
        and     #$04            ; CLK in?
        beq     @wait
        lda     #$00
        sta     D_SERIAL
        ldx     #$04
@bits:  lda     #$00
        asl     D_SNDBYT
        rol     a
        asl     a
        asl     D_SNDBYT
        rol     a
        asl     a               ; A = b7<<3 | b6<<1
        sta     D_SERIAL
        dex
        bne     @bits
        pha                     ; delay
        pla
        pha
        pla
        lda     #$00
        sta     D_SERIAL
        iny
        bne     @byte
        rts

; -----------------------------------------------------------------------------
; DrvRead - drive $05CD
; Purpose : Read the sector D_BUF0+0/+1 (track/sector) into D_BUF0 with
;           its own GCR read loop. A seek job is used only when the
;           track changes. 3 tries.
; Inputs  : D_BUF0 = track, D_BUF0+1 = sector.
; Outputs : D_BUF0 = sector data. On error: sends a $FF block, then
;           jumps to D_CMDERR (does not return).
; -----------------------------------------------------------------------------
DrvRead:
        lda     #$03
        sta     D_RETRY
        ldy     D_BUF0+1
        sty     D_SEC0
        lda     D_BUF0
        cmp     D_TRK0
        php
        sta     D_TRK0
        plp
        beq     ReadTry         ; same track: no seek
        lda     #JOB_SEEK
        sta     D_JOB0
        cli                     ; let the DOS job loop run
@wait:  bit     D_JOB0
        bmi     @wait
        sei
        lda     D_JOB0
        cmp     #$01            ; 1 = OK
        bne     SeekErr
ReadTry:
        lda     #$EE
        sta     D_PCR           ; read mode, byte-ready on
        lda     #$06
        sta     D_ZP32          ; ?
        lda     #$00
        sta     D_ZP32+1
        sta     D_BUFPNT
        lda     #>D_BUF0
        sta     D_BUFPNT+1
        jsr     FindHdrSync
@rd1:   bvc     @rd1            ; 256 GCR bytes -> $0300
        clv
        lda     D_DDATA
        sta     D_BUF0,y
        iny
        bne     @rd1
        ldy     #$BA            ; 70 more GCR bytes -> $01BA-$01FF
@rd2:   bvc     @rd2
        clv
        lda     D_DDATA
        sta     D_OVFL,y
        iny
        bne     @rd2
        jsr     D_GCRDEC
        lda     D_BLKID
        cmp     D_DBID
        beq     @idok
        lda     #$22            ; 22, READ ERROR (no data block)
        bne     Retry
@idok:  jsr     D_CHKSUM
        cmp     D_CHKBYT
        beq     @sumok
        lda     #$23            ; 23, READ ERROR (checksum)
        bne     Retry
@sumok: lda     #$EC
        sta     D_PCR
        rts

Retry:
        dec     D_RETRY
        bne     ReadTry
        beq     DrvError        ; always taken
SeekErr:
        clc
        adc     #$18            ; ? job code -> error number
DrvError:
        sta     D_ERRSAV
        lda     #$FF
        sta     D_BUF0          ; error marker for the C128
        jsr     DrvSend
        lda     #$3A
        sta     D_T1LHI
        lda     D_ERRSAV
        jmp     D_CMDERR

; -----------------------------------------------------------------------------
; FindHdrSync - drive $065C
; Purpose : Find the header of sector D_SEC0, then wait for the next SYNC
;           (start of the data block).
; Outputs : Y = 0, V clear, ready to read data bytes.
;           On error goes to Retry (header, A = $20) or DrvError
;           (no sync, A = $21).
; -----------------------------------------------------------------------------
FindHdrSync:
        jsr     FindHeader
        jmp     WaitSync

; FindHeader - drive $0662: build the header, look for it (90 tries)
FindHeader:
        lda     D_DISKID
        sta     D_HDR
        lda     D_DISKID+1
        sta     D_HDR+1
        lda     D_TRK0
        sta     D_HDR+2
        lda     D_SEC0
        sta     D_HDR+3
        lda     #$00
        eor     D_HDR
        eor     D_HDR+1
        eor     D_HDR+2
        eor     D_HDR+3
        sta     D_HDR+4         ; header checksum
        jsr     D_HDRGCR
        ldx     #$5A
@try:   jsr     WaitSync
@cmp:   bvc     @cmp
        clv
        lda     D_DDATA
        cmp     a:D_HDRGCRB,y   ; (absolute,Y form as in the original)
        bne     @no
        iny
        cpy     #$08
        bne     @cmp
        rts
@no:    dex
        bne     @try
        lda     #$20            ; 20, READ ERROR (header not found)
        bne     Retry

; WaitSync - drive $069E: wait for SYNC, with timeout (error 21)
WaitSync:
        lda     #$D0
        sta     D_T1HI          ; start timeout
        lda     #$21            ; 21, READ ERROR (no sync)
@wait:  bit     D_T1HI
        bpl     DrvError        ; timeout
        bit     D_DCTRL
        bmi     @wait
        lda     D_DDATA         ; clear the byte latch
        clv
        ldy     #$00
        rts

        .assert * = $06B6, error, "drive code size changed"

        .res    $06C0 - *, $FF  ; $06B6-$06BF fill

; ---- file name buffer: drive $06C0 = host $16C0 ($A0 = shifted space) ----
DrvFName:
        .res    16, $A0
        .byte   $00             ; $06D0 (TurboLoad fills it with $A0 too)

FNBUF   = DrvFName - DRVORG + DriveCode     ; host address $16C0
        .assert FNBUF = $16C0, error, "FNBUF must be $16C0"
