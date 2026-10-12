; =============================================================================
; pc.ml6.s - PC-Term 128, module PC.ML6: memory image $2A00-$377F
;            (terminal loop with capture buffer, 1571 no-verify patch,
;            older build of the Punter file-transfer code)
; =============================================================================
; Original file : pc.ml6 (C128 PRG, load address $2A00, 3456 bytes)
; Assembler     : ca65/ld65 (cc65 2.19). Rebuild and compare with
;                 disasm/verify.sh
;
; LOAD ADDRESS: $2A00 IS CORRECT, NOT $2000
;   pcterm line 716:
;     BANK15:IFPEEK(9000)<>6THEN ...:BLOAD"pc.ml6",b0,p8192:u(dv%(dv))
;     :SYSDEC("2f00"):SYSDEC("2000")
;   "p8192" would load the file at $2000. The code shows that it was made
;   for $2A00:
;   - every absolute self-reference fits $2A00 only: STA $2A44 and
;     CMP $2A45,Y (PrintBuf), JMP $2A30, the jump table at $2AF0 (JMP $2AFF,
;     $2C9F, $2BDF, $2EA1, $2E6A), JMP $2AC0, LDA $2D20,X ..., JSR $2F86,
;     LDA $2F99,Y, the Punter jump table at $3000 (JMP $301B, $35A1, $3695),
;     the self-modified JMP built from #$33/#$30 = $3033, and the BSOUT
;     hook vector #$BA/#$36 = $36BA.
;   - the SYS $2F00 of line 716 hits "JSR CLALL" at $2F00, the start of a
;     complete routine (DiskPatch), only when the file is at $2A00. At
;     $2000 the file ends at $2D7F, so $2F00 would be in pc.ml.
;   - at $2000 the file would overwrite the pc.ml jump table ($2093-$20F4)
;     that BASIC calls with SYS $209F ... $20BA and SYSxc (xc=8429).
;   Line 716 never runs in practice: line 715 loads pc.ml, and pc.ml has
;   the value 6 at $2328 (= 9000), so PEEK(9000)<>6 is false at line 716.
;   (Also, ":u(dv%(dv))" after "p8192" is a separate statement, which is a
;   ?SYNTAX ERROR; the "u" was meant as a BLOAD parameter.)
;   The SYS $2000 of line 716 has no target in this file. ; ?
;
; WHAT THIS FILE IS
;   The file is a BSAVE of memory $2A00-$377F, not one assembled module.
;   It holds live routines, a copy of older Punter code, and stale bytes:
;     $2A00-$2A81  PrintBuf + its control-code table
;     $2A82-$2AEF  stale bytes (old code, partly overwritten), except
;     $2AC0-$2ACB  CapStore (live, called from CaptureByte)
;     $2AF0-$2D1F  jump table, terminal loop, ESC commands, capture buffer
;     $2D20-$2E69  status texts, ASCII/PETSCII tables, hot-key table
;     $2E6A-$2EDC  load / send the capture buffer, background colour
;     $2EDD-$2EFF  RAM fill pattern ($00/$FF), not used
;     $2F00-$2FC0  DiskPatch: 1571 "no verify" patch (37 bytes drive code)
;     $2FC1-$2FEF  RAM fill pattern, not used
;     $2FF0-$2FF5  terminal variables
;     $2FF6-$2FFF  stale bytes
;     $3000-$3736  Punter C1 file transfer + RS-232 BSOUT hook. This is
;                  another build of pc.ml $20A2-$2814, assembled for $3000
;                  with work area $3800-$381E, buffers $3900/$3A00 and
;                  vectors $3B00-$3B03 (all outside this file).
;                  Differences to pc.ml (besides the addresses): only 7
;                  dispatcher entries (pc.ml has 11), WaitCode timeout
;                  #$14 (pc.ml #$30), abort test SHFLAG=2 / C= key
;                  (pc.ml: LSTX $D5 = $48), buffers at $3900/$3A00
;                  (pc.ml: $0500/$0600). Which build is older is unknown.
;     $3737-$377F  fill bytes ($07, then $1A, then $00 $FF), not used
;
; Loaded by     : pcterm line 716 (dead code, see above). No other BLOAD,
;                 LOAD or SYS for this module was found.
; Called by     : SYS $2F00 (line 716, never reached). No BASIC caller for
;                 the other entry points. ; ?
;
; Entry points:
;   $2A00 PrintBuf    - print a $00-ended text from any bank to file 4
;   $2AF0 Terminal    - terminal loop (via jump table $2AF0-$2AFE)
;   $2AF3 Cursor      - cursor on/off
;   $2AF6 CaptureZero - clear the capture buffer
;   $2AF9 SendBuf     - send the capture buffer to file 8
;   $2AFC LoadBuf     - load file 8 into the capture buffer
;   $2F00 DiskPatch   - install the 1571 no-verify patch
;   $3000/$3003/$3006/$3009/$300C/$300F - Punter functions 0/3/6/9/12/15
;   $3015 WaitTx      - wait until the RS-232 output is done
;   $3018 HookBsout   - install the RS-232 BSOUT (CHROUT) hook
; =============================================================================

        .setcpu "6502"

; ---- C128 KERNAL jump table -------------------------------------------------
INDFET  := $FF74                ; LDA (A-zp),Y from bank X
INDSTA  := $FF77                ; STA (STAVEC-zp),Y in bank X
PRIMM   := $FF7D                ; print the zero-ended string after the JSR
READST  := $FFB7                ; read I/O status
SETLFS  := $FFBA                ; set logical file, device, secondary address
SETNAM  := $FFBD                ; set file name
OPEN    := $FFC0
CLOSE   := $FFC3
CHKIN   := $FFC6                ; input from logical file X
CHKOUT  := $FFC9                ; output to logical file X
CLRCHN  := $FFCC                ; back to keyboard / screen
CHRIN   := $FFCF
CHROUT  := $FFD2
STOP    := $FFE1                ; Z=1 if STOP key is down
GETIN   := $FFE4
CLALL   := $FFE7                ; close all files

; ---- C128 KERNAL / editor internals (no jump table entry) -------------------
K_RSWAIT  := $E6C2              ; RS-232 helper called while waiting for output ; ?
K_RSNMI   := $E67F              ; RS-232: write A to the CIA2 ICR / ENABL ; ?
K_RSSTART := $E64A              ; RS-232: start-bit / transmit set-up ; ?
K_TAPEBUF := $E9BE              ; cassette: check buffer (copied BSOUT path) ; ?
K_TAPEWR  := $EA15              ; cassette: write buffer (copied BSOUT path) ; ?
COLKEYS   := $CE4C              ; editor table of the 16 PETSCII colour codes ; ?

; ---- C128 hardware ----------------------------------------------------------
VIC_SCREEN := $0400             ; 40-column VIC screen (line 0 = status line)
ST_STATE   := $0403             ; status line: capture state (OPEN/CLOS/FULL/ZEROED)
ST_MODE    := $040A             ; status line: ASCII / GRAPHIC
ST_FREE    := $041A             ; status line: free buffer bytes (5 digits)
VIC_BORDER := $D020             ; VIC border colour
VIC_BG0    := $D021             ; VIC background colour
CIA2_TALO  := $DD04             ; CIA2 timer A lo (RS-232 baud timer)
CIA2_TAHI  := $DD05             ; CIA2 timer A hi
CIA2_CRA   := $DD0E             ; CIA2 control register A

; ---- C128 zero page ---------------------------------------------------------
ZTMP    := $64                  ; scratch (BASIC FAC area, free during SYS)
PTPTR   := $66                  ; Punter: pointer to a block buffer (2 bytes)
CHAR    := $77                  ; terminal: current character (program use)
STATUS  := $90                  ; KERNAL I/O status (ST)
PTSTAT  := $96                  ; Punter: result code of the last wait (program use)
DFLTO   := $9A                  ; KERNAL: current output device
OUTCHR  := $9E                  ; KERNAL BSOUT: character being output
BUFPT   := $A6                  ; KERNAL: cassette buffer index
TAPE1   := $B2                  ; KERNAL: cassette buffer pointer (2 bytes)
FA      := $BA                  ; KERNAL: current device number
RIBUF   := $C8                  ; KERNAL: RS-232 input buffer pointer (2 bytes)
ROBUF   := $CA                  ; KERNAL: RS-232 output buffer pointer (2 bytes)
SHFLAG  := $D3                  ; keyboard: 1=SHIFT 2=C= 4=CTRL
PNT     := $E0                  ; editor: address of cursor line in screen RAM
USER    := $E2                  ; editor: address of cursor line in colour RAM
PNTR    := $EC                  ; editor: cursor column
COLOR   := $F1                  ; editor: current character colour
QTSW    := $F4                  ; editor: quote mode flag
INSRT   := $F5                  ; editor: insert count
BUFPTR  := $FA                  ; capture buffer pointer, bank 1 (2 bytes)
SRCPTR  := $FC                  ; source pointer for print / send (2 bytes)
LOADBANK := $FE                 ; bank for LoadBuf (set by the caller) ; ?

; ---- C128 system RAM --------------------------------------------------------
BUF     := $0200                ; BASIC input buffer; byte 0 = result for BASIC
BUF89   := $0289                ; inside BUF - see CaptureEnd ; ?
STAVEC  := $02B9                ; zp address used by INDSTA
IBSOUT  := $0326                ; CHROUT (BSOUT) RAM vector
ENABL   := $0A0F                ; RS-232 NMI enable / active flags
RIDBE   := $0A18                ; RS-232 input buffer: end index
RIDBS   := $0A19                ; RS-232 input buffer: start index
RODBS   := $0A1A                ; RS-232 output buffer: start index
RODBE   := $0A1B                ; RS-232 output buffer: end index
SERIAL  := $0A1C                ; bit 6 = fast serial (1571) drive found

; ---- Punter work area (outside this file, not initialised by it) ------------
PT_WIN    := $3800              ; last 3 characters received (3 bytes)
PT_BIT    := $3803              ; code-search: current mask bit
PT_IDX    := $3804              ; code-search: index of the code found (0,3,6,9,12)
PT_MASK   := $3805              ; code-search: codes that are accepted
PT_TIMER  := $3806              ; wait counter (2 bytes)
PT_CODE   := $3808              ; code to answer with (0=GOO, 3=BAD)
PT_LEN    := $3809              ; block length / loop counter
PT_SENDER := $380B              ; 1 = this side transmits, 0 = receives
PT_TRIES  := $380C              ; retry counter
PT_LAST   := $380D              ; 1 = last block done
PT_RXSUM  := $380E              ; checksum received in the block (4 bytes)
PT_SUM    := $3812              ; checksum computed here (4 bytes)
PT_BUFSEL := $3816              ; 0/1: which buffer is "current"
PT_NXTLEN := $3817              ; length of the next block
PT_BLKSIZ := $3818              ; data block size (pc.ml: POKE $201B from BASIC)
PT_BLKNO  := $3819              ; block number (2 bytes)
PT_FTYPE  := $381B              ; file type (pc.ml: POKE/PEEK $201E from BASIC)
PT_SAVESP := $381C              ; stack pointer at entry (for the C= abort)
PT_TYPEBL := $381D              ; 1 = sending the file-type block (no progress marks)
PT_SENDGO := $381E              ; 1 = send "GOO" before the first wait
PT_BUF0   := $3900              ; block buffer 0 (256 bytes)
PT_BUF1   := $3A00              ; block buffer 1 (256 bytes)
RS_BAUD   := $3B00              ; CIA2 timer value for the baud rate (2 bytes) ; ?
OLDBSOUT  := $3B02              ; old IBSOUT vector saved by HookBsout (2 bytes)

; ---- 1571 drive (code that runs in the disk drive) -------------------------
DRV_JOBS  := $00                ; drive job queue, jobs 0-5
DRV_VECLO := $02A9              ; drive RAM vector lo (patched) ; ?
DRV_VECHI := $02AA              ; drive RAM vector hi (patched) ; ?
DRV_ROM   := $9DDF              ; 1571 ROM: continue the normal routine ; ?
JOB_VERIFY = $A0                ; job code: verify a written sector
JOB_SEEK   = $B0                ; job code: seek only

BUFSTART := $1000                ; capture buffer start (bank 1)
BUFEND   := $FE00                ; capture buffer end (bank 1), $EE00 = 60928 bytes

        .word   $2A00           ; PRG load address (see the note above)
        .org    $2A00

; -----------------------------------------------------------------------------
; PrintBuf - $2A00 (no BASIC caller found)
; Purpose : Print a text that ends with $00 from any memory bank to logical
;           file 4 (printer). CLR/HOME ($93) is not printed. Stops on STOP
;           or on any key.
; Inputs  : A = bank, X/Y = address lo/hi of the text. File 4 must be open.
; Outputs : SRCPTR points to the $00 byte (or where it stopped). Output
;           channel stays on file 4 (no CLRCHN).
; Note    : The JMP at $2A23 skips the control-code filter at PrintFilter
;           (it would drop every code in CtrlCodes). Probably a patch. ; ?
; -----------------------------------------------------------------------------
PrintBuf:
        sta     PrintBank       ; remember the bank
        stx     SRCPTR          ; SRCPTR = start address
        sty     SRCPTR+1
        ldx     #$04            ; output to logical file 4 (printer, opened by BASIC) ; ?
        jsr     CHKOUT
PrintBufLoop:
        jsr     STOP            ; STOP key down?
        bne     PrintBufKey     ; no: go on
PrintBufDone:
        rts                     ; yes: stop
PrintBufKey:
        jsr     GETIN           ; any key stops the print
        bne     PrintBufDone
        lda     #<SRCPTR        ; LDA (SRCPTR),Y ...
        ldx     PrintBank       ; ... from bank PrintBank
        ldy     #$00
        jsr     INDFET
        beq     PrintBufDone    ; byte $00 = end of text
        jmp     PrintChar       ; PATCH: skips the control-code filter below ; ?
PrintFilter:
        cmp     CtrlCodes,y     ; not reached (see JMP above)
        beq     PrintNext
        iny
        cpy     #CtrlCodesEnd-CtrlCodes
        bne     PrintFilter
PrintChar:
        cmp     #$93            ; never print CLR/HOME
        beq     PrintNext
        jsr     CHROUT
        lda     #$00            ; quote mode off
        sta     QTSW
PrintNext:
        inc     SRCPTR          ; next address
        bne     PrintBufLoop
        inc     SRCPTR+1
        jmp     PrintBufLoop

; -----------------------------------------------------------------------------
; Bank for PrintBuf (written at the entry).
; -----------------------------------------------------------------------------
PrintBank:
        .byte   $01

; -----------------------------------------------------------------------------
; CtrlCodes - control codes that PrintFilter would not print
; ($01-$1F without $0D, and $81-$9F). Not used because of the JMP at $2A23.
; -----------------------------------------------------------------------------
CtrlCodes:
        .byte   $01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0E,$0F,$10,$11 ; $2A45
        .byte   $12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F,$81,$82 ; $2A55
        .byte   $83,$84,$85,$86,$87,$88,$89,$8A,$8B,$8C,$8D,$8E,$8F,$90,$91,$92 ; $2A65
        .byte   $93,$94,$95,$96,$97,$98,$99,$9A,$9B,$9C,$9D,$9E,$9F ; $2A75
CtrlCodesEnd:

; -----------------------------------------------------------------------------
; Stale1 - $2A82-$2ABF: not executed.
; Old code from another program (it calls $3540, $3551, $3597, $35E1 and
; reads $3CDB-$3D1F, which do not fit the code in this file). Bytes are
; kept as data; the comments show how they disassemble.
; -----------------------------------------------------------------------------
Stale1: .byte   $3C             ; 2A82  ?
        .byte   $4C,$88,$2A     ; 2A83  jmp $2A88
        .byte   $A9,$3E         ; 2A86  lda #$3E
        .byte   $20,$D2,$FF     ; 2A88  jsr $FFD2
        .byte   $20,$E1,$35     ; 2A8B  jsr $35E1
        .byte   $AD,$09,$3D     ; 2A8E  lda $3D09
        .byte   $F0,$13         ; 2A91  beq $2AA6
        .byte   $20,$51,$35     ; 2A93  jsr $3551
        .byte   $A9,$3B         ; 2A96  lda #$3B
        .byte   $20,$D2,$FF     ; 2A98  jsr $FFD2
        .byte   $A9,$00         ; 2A9B  lda #$00
        .byte   $85,$87         ; 2A9D  sta $87
        .byte   $A9,$02         ; 2A9F  lda #$02
        .byte   $85,$88         ; 2AA1  sta $88
        .byte   $20,$40,$35     ; 2AA3  jsr $3540
        .byte   $20,$97,$35     ; 2AA6  jsr $3597
        .byte   $AD,$DF,$3C     ; 2AA9  lda $3CDF
        .byte   $D0,$03         ; 2AAC  bne $2AB1
        .byte   $4C,$91,$27     ; 2AAE  jmp $2791
        .byte   $AD,$F4,$3C     ; 2AB1  lda $3CF4
        .byte   $D0,$10         ; 2AB4  bne $2AC6
        .byte   $EE,$F4,$3C     ; 2AB6  inc $3CF4
        .byte   $AD,$DB,$3C     ; 2AB9  lda $3CDB
        .byte   $85,$FA         ; 2ABC  sta $FA
        .byte   $AD             ; 2ABE  ?
        .byte   $DC             ; 2ABF  ?

; -----------------------------------------------------------------------------
; CapStore - $2AC0 (live; jumped to from CaptureByte)
; Purpose : Store the received character in the capture buffer (bank 1).
;           A $00 byte is stored as $01, because $00 marks the end of the text.
; Inputs  : A = character, X = 1 (bank), Y = 0, STAVEC = BUFPTR.
; Outputs : byte stored; continues at CaptureEnd.
; -----------------------------------------------------------------------------
CapStore:
        cmp     #$00            ; a $00 byte would end the text,
        bne     L2AC6
        lda     #$01            ; so store $01 instead
L2AC6:  jsr     INDSTA          ; STA (BUFPTR),Y in bank 1
        jmp     CaptureEnd      ; then write the $00 end mark

; -----------------------------------------------------------------------------
; Stale2 - $2ACC-$2AEF: not executed. More old code (same source as
; Stale1). The last byte ($20 at $2AEF) is followed by the live jump table.
; -----------------------------------------------------------------------------
Stale2: .byte   $87             ; 2ACC  ?
        .byte   $A9,$3D         ; 2ACD  lda #$3D
        .byte   $85,$88         ; 2ACF  sta $88
        .byte   $20,$97,$35     ; 2AD1  jsr $3597
        .byte   $20,$51,$35     ; 2AD4  jsr $3551
        .byte   $20,$51,$35     ; 2AD7  jsr $3551
        .byte   $AE,$1F,$3D     ; 2ADA  ldx $3D1F
        .byte   $A9,$00         ; 2ADD  lda #$00
        .byte   $20,$5A,$35     ; 2ADF  jsr $355A
        .byte   $20,$40,$35     ; 2AE2  jsr $3540
        .byte   $AD,$02,$3D     ; 2AE5  lda $3D02
        .byte   $F0,$15         ; 2AE8  beq $2AFF
        .byte   $20,$CC,$FF     ; 2AEA  jsr $FFCC
        .byte   $A2,$04         ; 2AED  ldx #$04
        .byte   $20             ; 2AEF  ?

; -----------------------------------------------------------------------------
; JumpTable - $2AF0
; Entry points of the terminal part. No caller in pcterm. ; ?
; -----------------------------------------------------------------------------
JumpTable:
        jmp     Terminal        ; $2AF0 terminal loop
        jmp     Cursor          ; $2AF3 cursor on/off
        jmp     CaptureZero     ; $2AF6 clear the capture buffer
        jmp     SendBuf         ; $2AF9 send buffer to file 8
        jmp     LoadBuf         ; $2AFC load file 8 into the buffer

; -----------------------------------------------------------------------------
; Terminal - $2AFF (via $2AF0)
; Purpose : Terminal loop. Characters from the modem (file 5) go to the
;           screen; keys go to the modem. In ASCII mode both directions are
;           translated (XlatAscPet / XlatPetAsc). Received line feeds and $00
;           are dropped. CTRL-B + colour code sets the background colour.
;           Received characters can be captured in the bank 1 buffer.
;           ESC starts a command (see EscCommand).
; Inputs  : file 5 = RS-232 open; XlatMode, CaptureOn set up.
; Outputs : returns to the caller only through a hot key (EscCommand).
; Uses    : RIDBE/RIDBS (KERNAL RS-232 input buffer), CHAR, LastChar.
; -----------------------------------------------------------------------------
Terminal:
        lda     RIDBE           ; RS-232 input buffer empty?
        cmp     RIDBS
        beq     TermKey         ; yes: look at the keyboard
        ldx     #$05            ; input from file 5 (modem)
        jsr     CHKIN
        jsr     GETIN
        nop                     ; two NOPs (patched-out call?) ; ?
        nop
        sta     CHAR
        ldx     XlatMode        ; XlatMode: $00 = ASCII, $7F = graphics
        bne     TermNotNull
        jsr     AscToPet        ; ASCII mode: translate
        cmp     #$00            ; ignore $00
        beq     TermKey
TermNotNull:
        cmp     #$0A            ; ignore line feed
        beq     TermKey
        ldx     LastChar        ; was the last character CTRL-B?
        cpx     #$02
        bne     TermNoColour
        jsr     SetBgColour     ; yes: this character sets the background colour
TermNoColour:
        lda     CaptureOn       ; capture on?
        beq     TermShow
        jsr     CaptureByte     ; yes: store the character
TermShow:
        ldx     #$00            ; cursor off
        jsr     Cursor
        jsr     CLRCHN
        lda     CHAR            ; HOME after HOME is ignored
        cmp     #$13
        bne     TermPrint
        cmp     LastChar
        beq     Terminal
TermPrint:
        sta     LastChar        ; remember it
        jsr     CHROUT          ; print it
        lda     #$00            ; quote mode and insert mode off
        sta     QTSW
        sta     INSRT
        ldx     #$FF            ; cursor on
        jsr     Cursor
TermKey:
        jsr     CLRCHN          ; keyboard
        jsr     GETIN
        beq     Terminal        ; no key: loop
        sta     CHAR
        cmp     #$1B            ; ESC = command key
        beq     TermEsc
        ldx     #$05            ; output to file 5 (modem)
        jsr     CHKOUT
        lda     CHAR
        ldx     XlatMode
        bne     TermSend
        jsr     PetToAsc        ; ASCII mode: translate
TermSend:
        jsr     CHROUT
        jmp     Terminal
TermEsc:
        lda     #$07            ; bell
        jsr     CHROUT
        jsr     EscCommand      ; read and run the command
        jmp     Terminal

; -----------------------------------------------------------------------------
; EscCommand - $2B87
; Purpose : Read one command key after ESC:
;             O = open capture   C = close capture   Z = clear buffer
;             A = ASCII mode     G = graphics mode   CLR/HOME = clear screen
;           A key from HotKeys ends the terminal loop: the two PLA remove
;           the return address, so RTS returns from Terminal to its caller
;           with A = the key. Other keys: back to the terminal loop.
; Inputs  : none.   Outputs: A = key.
; -----------------------------------------------------------------------------
EscCommand:
        jsr     GETIN           ; wait for a key
        beq     EscCommand
        cmp     #'O'
        bne     L2B93
        jmp     CaptureOpen
L2B93:  cmp     #'C'
        bne     L2B9A
        jmp     CaptureClose
L2B9A:  cmp     #'Z'
        bne     L2BA1
        jmp     CaptureZero
L2BA1:  cmp     #'A'
        bne     L2BA8
        jmp     ModeAscii
L2BA8:  cmp     #'G'
        bne     L2BAF
        jmp     ModeGraphic
L2BAF:  cmp     #$93            ; CLR/HOME: clear the screen and return
        bne     EscHotKey
        jmp     CHROUT
EscHotKey:
        ldx     #$01            ; search the hot-key table
EscHotLoop:
        cmp     HotKeys-1,x
        beq     EscReturn
        inx
        cpx     #HotKeysEnd-HotKeys+1
        bcc     EscHotLoop
        rts
EscReturn:
        pla                     ; drop our return address:
        pla
        rts                     ; RTS goes back to BASIC, A = key ; ?

; -----------------------------------------------------------------------------
; CaptureOpen - $2BC6 (ESC O)
; Purpose : Start capture (if the buffer is not full): border dark grey,
;           "OPEN" in the status line.
; -----------------------------------------------------------------------------
CaptureOpen:
        lda     BufFull         ; buffer full: cannot open
        bne     L2BDE
        lda     #$0B            ; dark grey
        sta     CaptureOn       ; flag: capture on
        sta     VIC_BORDER      ; border shows "capture on"
        ldx     #$03
L2BD5:  lda     TxtOpen,x       ; "OPEN" in the status line
        sta     ST_STATE,x
        dex
        bpl     L2BD5
L2BDE:  rts

; -----------------------------------------------------------------------------
; CaptureZero - $2BDF (ESC Z, and via $2AF6)
; Purpose : Empty the capture buffer: BUFPTR = $0FFF, byte $1000 in bank 1
;           = $00, "ZEROED" and "60928" (free bytes) in the status line,
;           capture off, all flags cleared.
; Inputs  : none.   Outputs: X = 0.
; -----------------------------------------------------------------------------
CaptureZero:
        lda     #<(BUFSTART-1)
        sta     BUFPTR
        lda     #>(BUFSTART-1)
        sta     BUFPTR+1
        ldx     #$05
L2BE9:  lda     TxtZeroed,x
        sta     ST_STATE,x
        lda     TxtFree,x
        sta     ST_FREE,x
        dex
        bpl     L2BE9
        lda     #<BUFPTR        ; INDSTA uses BUFPTR
        sta     STAVEC
        lda     #$00
        ldx     #$01
        ldy     #$01            ; Y=1: byte $1000 in bank 1 ...
        jsr     INDSTA          ; ... = $00 (empty text)
        ldx     #$00            ; reset all flags
        stx     CaptureOn
        stx     VIC_BORDER
        stx     BufFull
        stx     ZeroDigits
        rts

; -----------------------------------------------------------------------------
; CaptureClose - $2C15 (ESC C)
; Purpose : Stop capture: border black, "CLOS" in the status line.
; -----------------------------------------------------------------------------
CaptureClose:
        lda     #$00
        sta     VIC_BORDER
        sta     CaptureOn
        ldx     #$03
L2C1F:  lda     TxtClos,x
        sta     ST_STATE,x
        dex
        bpl     L2C1F
        rts

; -----------------------------------------------------------------------------
; CaptureByte - $2C29 (from Terminal when capture is on)
; Purpose : Add CHAR to the capture buffer in bank 1 and keep a $00 after
;           it. When the buffer reaches $FE00, go to CaptureFull.
; Inputs  : CHAR = character, BUFPTR = last used address.
; Outputs : BUFPTR + 1; free-byte count on the status line - 1.
; -----------------------------------------------------------------------------
CaptureByte:
        inc     BUFPTR          ; next buffer address
        bne     CaptureByte2
        inc     BUFPTR+1
        lda     BUFPTR+1
        cmp     #>BUFEND        ; end of the buffer reached?
        beq     CaptureFull
CaptureByte2:
        jsr     CountDown       ; one free byte less on the status line
        lda     #<BUFPTR
        sta     STAVEC
        lda     CHAR            ; the character
        ldx     #$01            ; bank 1, Y=0
        ldy     #$00
        jmp     CapStore        ; store it (see CapStore)

; -----------------------------------------------------------------------------
; CaptureEnd - $2C46 (from CapStore)
; Purpose : Write the $00 end mark after the stored character.
; Inputs  : Y = 0.
; -----------------------------------------------------------------------------
CaptureEnd:
        lda     #<BUFPTR
        sta     BUF89           ; BUG? STAVEC is $02B9; harmless, STAVEC is already BUFPTR ; ?
        lda     #$00            ; $00 end mark ...
        ldx     #$01            ; ... in bank 1 ...
        iny                     ; ... at BUFPTR+1
        jsr     INDSTA
        rts

; -----------------------------------------------------------------------------
; CaptureFull - $2C54
; Purpose : Buffer full: send CTRL-S (XOFF) to the modem, show "FULL !",
;           set BufFull, stop capture and print a message.
; -----------------------------------------------------------------------------
CaptureFull:
        ldx     #$05            ; send CTRL-S (XOFF) to the modem
        jsr     CHKOUT
        lda     #$13
        jsr     CHROUT
        jsr     CLRCHN
        ldx     #$05
L2C63:  lda     TxtFull,x       ; "FULL !" in the status line
        sta     ST_STATE,x
        dex
        bpl     L2C63
        stx     BufFull         ; X = $FF: BufFull set
        lda     #$00
        sta     CaptureOn       ; capture off
        sta     VIC_BORDER
        jsr     PRIMM           ; print the text that follows
        .byte   $0D,$07,$12,"BUFFER FULL-PRESS CONTROL Q...",$0D,$07,$00 ; text for PRIMM, $00 = end
        rts

; -----------------------------------------------------------------------------
; Cursor - $2C9F (via $2AF3)
; Purpose : Show or hide the cursor in the terminal loop by reversing the
;           character under the cursor and setting its colour.
; Inputs  : X = 0: cursor off (restore colour); X <> 0: cursor on.
; Outputs : CursorCol = saved colour (cursor on).
; -----------------------------------------------------------------------------
Cursor: ldy     PNTR            ; reverse the character under the cursor
        lda     (PNT),y
        eor     #$80
        sta     (PNT),y
        txa                     ; X = 0: cursor off
        beq     CursorOff
        lda     (USER),y        ; cursor on: save the colour
        sta     CursorCol
        lda     COLOR           ; and use the current colour
        sta     (USER),y
        rts
CursorOff:
        lda     CursorCol       ; cursor off: restore the colour
        sta     (USER),y
        rts

; -----------------------------------------------------------------------------
; CountDown - $2CBA
; Purpose : Decrement the 5-digit free-byte count at ST_FREE (reverse screen
;           codes). Leading zeros are changed to blanks; ZeroDigits counts
;           them. ; ? (the leading-zero logic was not checked in detail)
; -----------------------------------------------------------------------------
CountDown:
        ldx     #$04            ; 5 digits at VIC_SCREEN+$1A..$1E
CountLoop:
        lda     ST_FREE,x
        cmp     #$B0            ; reverse "0"?
        bne     CountDec        ; no: decrement this digit
        txa                     ; position = ZeroDigits?
        cmp     ZeroDigits
        bne     CountBorrow     ; no: borrow
        inc     ZeroDigits
        cmp     #$05            ; ; ? A is 0-4 here, so never equal
        beq     CountDone
        lda     #$A0            ; reverse space: blank a leading zero
        bne     CountStore
CountBorrow:
        lda     #$B9            ; reverse "9" (borrow)
CountStore:
        sta     ST_FREE,x
        dex
        bpl     CountLoop
        rts
CountDec:
        tay                     ; digit minus 1
        dey
        tya
        sta     ST_FREE,x
CountDone:
        rts

; -----------------------------------------------------------------------------
; ModeAscii - $2CE4 (ESC A)
; Purpose : ASCII mode: XlatMode = 0, "ASCII" in the status line,
;           character colour 5.
; -----------------------------------------------------------------------------
ModeAscii:
        lda     #$00            ; ASCII mode
        sta     XlatMode
        ldx     #$06
L2CEB:  lda     TxtAscii,x      ; "ASCII  " in the status line
        sta     ST_MODE,x
        dex
        bpl     L2CEB
        lda     #$05            ; colour 5 (green)
        sta     COLOR
        rts

; -----------------------------------------------------------------------------
; ModeGraphic - $2CF9 (ESC G)
; Purpose : Graphics (PETSCII) mode: XlatMode = $7F, "GRAPHIC" in the
;           status line.
; -----------------------------------------------------------------------------
ModeGraphic:
        lda     #$7F            ; graphics (PETSCII) mode
        sta     XlatMode
        ldx     #$06
L2D00:  lda     TxtGraphic,x    ; "GRAPHIC" in the status line
        sta     ST_MODE,x
        dex
        bpl     L2D00
        rts

; -----------------------------------------------------------------------------
; AscToPet - $2D0A
; Purpose : Translate ASCII to PETSCII with XlatAscPet (bit 7 ignored).
; Inputs  : A = ASCII.   Outputs: A = CHAR = PETSCII, X = index.
; -----------------------------------------------------------------------------
AscToPet:
        and     #$7F            ; ignore bit 7
        tax
        lda     XlatAscPet,x
        sta     CHAR
        rts

; -----------------------------------------------------------------------------
; PetToAsc - $2D13
; Purpose : Translate PETSCII to ASCII with XlatPetAsc. Codes $80-$FF are
;           looked up at index A-$60.
; Inputs  : A = PETSCII.   Outputs: A = CHAR = ASCII, X = index.
; -----------------------------------------------------------------------------
PetToAsc:
        cmp     #$80            ; PETSCII $80-$FF ...
        bcc     L2D19
        sbc     #$60            ; ... use index A-$60 (C=1 here)
L2D19:  tax
        lda     XlatPetAsc,x
        sta     CHAR
        rts

; -----------------------------------------------------------------------------
; Status-line texts (reverse screen codes) for ST_STATE, ST_MODE and
; ST_FREE. TxtFree "60928" = $FE00-$1000 bytes.
; -----------------------------------------------------------------------------
TxtOpen:
        .byte   $8F,$90,$85,$8E ; reverse "OPEN"
TxtZeroed:
        .byte   $9A,$85,$92,$8F,$85,$84 ; reverse "ZEROED"
TxtClos:
        .byte   $83,$8C,$8F,$93 ; reverse "CLOS"
TxtFull:
        .byte   $86,$95,$8C,$8C,$A0,$A1 ; reverse "FULL !"
TxtAscii:
        .byte   $81,$93,$83,$89,$89,$A0,$A0 ; reverse "ASCII  "
TxtGraphic:
        .byte   $87,$92,$81,$90,$88,$89,$83 ; reverse "GRAPHIC"
TxtFree:
        .byte   $B6,$B0,$B9,$B2,$B8,$A0 ; reverse "60928 "

; -----------------------------------------------------------------------------
; XlatAscPet - 128 bytes: ASCII -> PETSCII (index = ASCII and $7F).
; $0A (line feed) and $60 give $01; BS ($08) and DEL ($7F) give $14.
; -----------------------------------------------------------------------------
XlatAscPet:
        .byte   $01,$01,$02,$03,$04,$05,$06,$07,$14,$09,$01,$0B,$0C,$0D,$0E,$0F ; $2D48
        .byte   $10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F ; $2D58
        .byte   $20,$21,$27,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F ; $2D68
        .byte   $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F ; $2D78
        .byte   $40,$C1,$C2,$C3,$C4,$C5,$C6,$C7,$C8,$C9,$CA,$CB,$CC,$CD,$CE,$CF ; $2D88
        .byte   $D0,$D1,$D2,$D3,$D4,$D5,$D6,$D7,$D8,$D9,$DA,$5B,$5C,$5D,$5E,$5F ; $2D98
        .byte   $01,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F ; $2DA8
        .byte   $50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$B3,$7D,$AB,$B2,$14 ; $2DB8

; -----------------------------------------------------------------------------
; XlatPetAsc - 128 bytes: PETSCII -> ASCII (index = PETSCII, or
; PETSCII-$60 for $80-$FF). The last byte ($1B at $2E47) is also read as
; "HotKeys-1", which EscCommand never compares (X starts at 1). ; ?
; -----------------------------------------------------------------------------
XlatPetAsc:
        .byte   $01,$01,$02,$03,$04,$05,$06,$07,$08,$09,$01,$0B,$0C,$0D,$0E,$0F ; $2DC8
        .byte   $10,$11,$12,$13,$08,$15,$16,$17,$18,$19,$1A,$1B,$1C,$1D,$1E,$1F ; $2DD8
        .byte   $20,$21,$22,$23,$24,$25,$26,$27,$28,$29,$2A,$2B,$2C,$2D,$2E,$2F ; $2DE8
        .byte   $30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$3A,$3B,$3C,$3D,$3E,$3F ; $2DF8
        .byte   $40,$61,$62,$63,$64,$65,$66,$67,$68,$69,$6A,$6B,$6C,$6D,$6E,$6F ; $2E08
        .byte   $70,$71,$72,$73,$74,$75,$76,$77,$78,$79,$7A,$5B,$5C,$5D,$5E,$01 ; $2E18
        .byte   $5F,$41,$42,$43,$44,$45,$46,$47,$48,$49,$4A,$4B,$4C,$4D,$4E,$4F ; $2E28
        .byte   $50,$51,$52,$53,$54,$55,$56,$57,$58,$59,$5A,$01,$01,$01,$01,$1B ; $2E38

; -----------------------------------------------------------------------------
; HotKeys - 34 keys that end the terminal loop (see EscCommand):
; J T R \ ^ * @ S L D V P U X H O Q E N - + $A2 $AF K 1-9 M
; (PETSCII: \ = pound sign, ^ = up arrow). Their BASIC use is unknown. ; ?
; -----------------------------------------------------------------------------
HotKeys:
        .byte   $4A,$54,$52,$5C,$5E,$2A,$40,$53,$4C,$44,$56,$50,$55,$58,$48,$4F,$51 ; $2E48
        .byte   $45,$4E,$2D,$2B,$A2,$AF,$4B,$31,$32,$33,$34,$35,$36,$37,$38,$39,$4D ; $2E59
HotKeysEnd:

; -----------------------------------------------------------------------------
; LoadBuf - $2E6A (via $2AFC)
; Purpose : Read logical file 8 into memory at BUFPTR+1 ... in bank
;           LOADBANK, without line feeds. The JMP at $2E82 skips the ASCII
;           translation (patch). ; ?
; Inputs  : file 8 open for reading, BUFPTR = address - 1, LOADBANK = bank.
; Outputs : BUFPTR = last address written. CLRCHN.
; -----------------------------------------------------------------------------
LoadBuf:
        ldx     #$08            ; input from file 8
        jsr     CHKIN
LoadBufLoop:
        inc     BUFPTR          ; next buffer address
        bne     LoadBufGet
        inc     BUFPTR+1
LoadBufGet:
        jsr     GETIN
        beq     LoadBufEnd
        ldy     STATUS          ; end of file or error?
        bne     LoadBufEnd
        cmp     #$0A            ; skip line feeds
        beq     LoadBufGet
        jmp     LoadBufStore    ; PATCH: no translation ; ?
        jsr     AscToPet        ; not reached
LoadBufStore:
        ldx     #<BUFPTR        ; INDSTA uses BUFPTR
        stx     STAVEC
        ldx     LOADBANK        ; bank from LOADBANK ; ?
        jsr     INDSTA          ; STA (BUFPTR),Y
        jmp     LoadBufLoop
LoadBufEnd:
        lda     BUFPTR          ; step back one address
        bne     L2E9B
        dec     BUFPTR+1
L2E9B:  dec     BUFPTR
        jsr     CLRCHN
        rts

; -----------------------------------------------------------------------------
; SendBuf - $2EA1 (via $2AF9)
; Purpose : Send a $00-ended text from bank 1 to logical file 8. The JMP
;           at $2EBB skips the ASCII translation (patch). ; ?
; Inputs  : A/X = address lo/hi MINUS 1 (first byte sent is A/X + 1).
;           File 8 open for writing.
; Outputs : the $00 end byte is also sent. CLRCHN.
; -----------------------------------------------------------------------------
SendBuf:
        sta     SRCPTR          ; SRCPTR = start - 1
        stx     SRCPTR+1
        ldx     #$08            ; output to file 8
        jsr     CHKOUT
SendBufLoop:
        inc     SRCPTR          ; next address
        bne     L2EB0
        inc     SRCPTR+1
L2EB0:  lda     #<SRCPTR
        ldx     #$01
        ldy     #$00
        jsr     INDFET          ; LDA (SRCPTR),Y from bank 1
        beq     SendBufEnd      ; $00 = end
        jmp     SendBufOut      ; PATCH: no translation ; ?
        jsr     PetToAsc        ; not reached
SendBufOut:
        jsr     CHROUT
        jmp     SendBufLoop
SendBufEnd:
        jsr     CHROUT          ; the $00 byte is also sent ; ?
        jsr     CLRCHN
        rts

; -----------------------------------------------------------------------------
; SetBgColour - $2ECE (from Terminal after CTRL-B)
; Purpose : If A is a PETSCII colour code, set the background to it.
; Inputs  : A = character.   Outputs: VIC_BG0 changed if A is a colour code.
; -----------------------------------------------------------------------------
SetBgColour:
        ldx     #$0F
L2ED0:  cmp     COLKEYS,x       ; is A a colour code?
        beq     SetBgFound
        dex
        bpl     L2ED0
        rts
SetBgFound:
        stx     VIC_BG0         ; yes: X = colour number
        rts

; -----------------------------------------------------------------------------
; Fill1 - $2EDD-$2EFF: C128 RAM power-on pattern ($00/$FF). Not used.
; -----------------------------------------------------------------------------
Fill1:  .byte   $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF ; $2EDD
        .byte   $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF ; $2EED
        .byte   $00,$FF,$00     ; $2EFD

; -----------------------------------------------------------------------------
; DiskPatch - $2F00 (SYS $2F00 in pcterm line 716)
; Purpose : Make a 1571 drive skip the verify after each sector write
;           (faster saves). Only for a fast serial drive (SERIAL bit 6).
;           1. close all files, send "UJ" (drive reset), reopen 15
;           2. copy DrvImage (37 bytes) into drive RAM $0103-$0127 with one
;              "M-W" command per byte
;           3. "M-E" $011C runs DrvInstall in the drive.
; Inputs  : none.   Outputs: all files closed; file 15 closed at the end.
; Note    : README.md says PC.ML4 also makes the disk faster. ; ?
; -----------------------------------------------------------------------------
DiskPatch:
        jsr     CLALL           ; close all files
        bit     SERIAL          ; bit 6: fast (1571) drive?
        bvs     DiskPatch2      ; yes
        rts                     ; no: nothing to do
DiskPatch2:
        jsr     OpenCmd         ; OPEN 15,8,15 and CHKOUT 15
        lda     #'U'            ; "UJ": reset the drive
        jsr     CHROUT
        lda     #'J'
        jsr     CHROUT
        lda     #$0F            ; CLOSE 15
        jsr     CLOSE
        jsr     OpenCmd         ; open the command channel again
        jsr     CLRCHN
        lda     #<(DrvVerifyOff) ; drive address lo of the first byte
        sta     MwAddr+1
MwLoop: ldx     #$0F
        jsr     CHKOUT
        ldy     MwAddr+1
        cpy     #Fill2-DrvImage+3 ; all bytes sent?
        beq     MwDone
        lda     DrvImage-3,y    ; byte for the drive
        sta     MwData+1        ; ... goes into the LDA below
        lda     #'M'            ; "M-W" lo hi count data
        jsr     CHROUT
        lda     #'-'
        jsr     CHROUT
        lda     #'W'
        jsr     CHROUT
MwAddr: lda     #$28            ; address lo (counter, self-modified)
        jsr     CHROUT
        lda     #>DrvVerifyOff  ; address hi = $01
        jsr     CHROUT
        lda     #$01            ; 1 byte
        jsr     CHROUT
MwData: lda     #$60            ; the data byte (self-modified)
        jsr     CHROUT
        jsr     CLRCHN
        inc     MwAddr+1        ; next byte
        jmp     MwLoop
MwDone: lda     #'M'            ; "M-E" $011C: run DrvInstall
        jsr     CHROUT
        lda     #'-'
        jsr     CHROUT
        lda     #'E'
        jsr     CHROUT
        lda     #<DrvInstall    ; lo
        jsr     CHROUT
        lda     #>DrvInstall    ; hi
        jsr     CHROUT
        jsr     CLRCHN
        lda     #$0F            ; CLOSE 15
        jsr     CLOSE
        rts

; -----------------------------------------------------------------------------
; OpenCmd - $2F86
; Purpose : OPEN 15,8,15,"" and CHKOUT 15.
; -----------------------------------------------------------------------------
OpenCmd:
        lda     #$00            ; no file name
        jsr     SETNAM
        lda     #$0F            ; logical file 15, secondary 15
        tay
        ldx     #$08            ; device 8
        jsr     SETLFS
        jsr     OPEN
        ldx     #$0F
        jsr     CHKOUT          ; output to the command channel
        rts

; -----------------------------------------------------------------------------
; DrvImage - $2F9C-$2FC0: code that runs in the 1571 at $0103-$0127.
; DrvInstall ($011C) points the drive RAM vector at $02A9/$02AA to
; DrvVerifyOff. DrvVerifyOff ($0103) changes every VERIFY job ($A0) in the
; job queue into a SEEK job ($B0), then goes on in the drive ROM at $9DDF.
; The vector and ROM address were not checked against a 1571 ROM. ; ?
; -----------------------------------------------------------------------------
DrvImage:

        .org    $0103           ; drive RAM address of this code
DrvVerifyOff:
        pha
        tya
        pha
        ldy     #$05
DrvJobLoop:
        lda     a:DRV_JOBS,y
        cmp     #JOB_VERIFY
        bne     DrvJobNext
        ora     #JOB_SEEK-JOB_VERIFY
        sta     a:DRV_JOBS,y
DrvJobNext:
        dey
        bpl     DrvJobLoop
        pla
        tay
        jmp     DRV_ROM
DrvInstall:
        sei
        lda     #<DrvVerifyOff
        sta     DRV_VECLO
        lda     #>DrvVerifyOff
        sta     DRV_VECHI
        rts
        .org    $2FC1           ; back to host addresses

; -----------------------------------------------------------------------------
; Fill2 - $2FC1-$2FEF: not used (RAM pattern).
; -----------------------------------------------------------------------------
Fill2:  .byte   $00,$00,$00,$05,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF ; $2FC1
        .byte   $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF ; $2FD1
        .byte   $00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00,$FF,$00 ; $2FE1

; -----------------------------------------------------------------------------
; Terminal variables (values as saved in the file).
; LastChar  : last character printed by Terminal
; CursorCol : colour under the cursor (saved by Cursor)
; CaptureOn : <>0 = capture on
; XlatMode  : $00 = ASCII mode, $7F = graphics mode
; BufFull   : <>0 = capture buffer full
; ZeroDigits: leading zero count for CountDown
; -----------------------------------------------------------------------------
LastChar:
        .byte   $0D
CursorCol:
        .byte   $27
CaptureOn:
        .byte   $00
XlatMode:
        .byte   $7F
BufFull:
        .byte   $00
ZeroDigits:
        .byte   $00

; -----------------------------------------------------------------------------
; Stale3 - $2FF6-$2FFF: not executed (old copy of the CapStore bytes
; and other old code).
; -----------------------------------------------------------------------------
Stale3: .byte   $F7             ; 2FF6  ?
        .byte   $C9,$00         ; 2FF7  cmp #$00
        .byte   $D0,$02         ; 2FF9  bne $2FFD
        .byte   $A9,$01         ; 2FFB  lda #$01
        .byte   $B1,$87         ; 2FFD  lda ($87),y
        .byte   $F0             ; 2FFF  ?

; -----------------------------------------------------------------------------
; Punter entry points - $3000 (pc.ml has the same table at $20A2)
; Each entry loads A with a function offset; the "BIT abs" opcode ($2C)
; hides the next LDA. Functions:
;   $3000  0  WaitCode  (internal)
;   $3003  3  RecvFile  (pc.ml: SYS $20A5)
;   $3006  6  SendFile  (pc.ml: SYS $20A8)
;   $3009  9  RecvType  (pc.ml: SYS $20AB)
;   $300C 12  SendType  (pc.ml: SYS $20AE)
;   $300F 15  DumbTerm
;   $3015     WaitTx    (pc.ml: SYS $20B7)
;   $3018     HookBsout (pc.ml: SYS $20BA)
; Results for BASIC: BUF ($0200) = 0 done, 1 = aborted with the C= key.
; -----------------------------------------------------------------------------
PtEntry0:
        lda     #$00            ; A = 0: WaitCode
        .byte   $2C             ; BIT abs: hides the next LDA
PtEntry3:
        lda     #$03            ; A = 3: RecvFile
        .byte   $2C             ; BIT abs
PtEntry6:
        lda     #$06            ; A = 6: SendFile
        .byte   $2C             ; BIT abs
PtEntry9:
        lda     #$09            ; A = 9: RecvType
        .byte   $2C             ; BIT abs
PtEntry12:
        lda     #$0C            ; A = 12: SendType
        .byte   $2C             ; BIT abs
PtEntry15:
        lda     #$0F            ; A = 15: DumbTerm
        nop
        jmp     PtDispatch
PtWaitTx:
        jmp     WaitTx
PtHookBsout:
        jmp     HookBsout

; -----------------------------------------------------------------------------
; PtDispatch - $301B
; Purpose : Save SP in PT_SAVESP (for CheckAbort), then JMP PtDispTab+A by
;           writing the JMP operand at PtDispJmp.
; Inputs  : A = 0, 3, 6, 9, 12 or 15.
; -----------------------------------------------------------------------------
PtDispatch:
        sta     ZTMP            ; A = offset into PtDispTab
        tsx                     ; save SP for the C= abort
        stx     PT_SAVESP
        lda     #<PtDispTab
        clc
        adc     ZTMP
        sta     PtDispJmp+1
        lda     #>PtDispTab
        adc     #$00
        sta     PtDispJmp+2
PtDispJmp:
        jmp     PtDispTab+6     ; JMP PtDispTab+A (operand self-modified; file has +6)

; -----------------------------------------------------------------------------
; PtDispTab - $3033: one JMP per function (offset = A).
; The last entry (A = 18) is not loaded by any entry point.
; -----------------------------------------------------------------------------
PtDispTab:
        jmp     WaitCode
        jmp     RecvFile
        jmp     SendFile
        jmp     RecvType
        jmp     SendType
        jmp     DumbTerm
        jmp     HookBsout       ; A = 18: no entry point uses it

; -----------------------------------------------------------------------------
; PtCodes - the five 3-letter Punter codes at offsets 0, 3, 6, 9, 12.
; -----------------------------------------------------------------------------
PtCodes:
        .byte   "GOOBADACKS/BSYN"

; -----------------------------------------------------------------------------
; WaitCode - $3057 (function 0)
; Purpose : Read RS-232 bytes until one of the accepted codes arrives and
;           the line is then quiet, or until a timeout.
; Inputs  : A = mask of accepted codes (bit 0 GOO, 1 BAD, 2 ACK, 3 S/B, 4 SYN).
; Outputs : PTSTAT = 0 code found (PT_IDX = its offset), 1 timeout (then
;           Retry). PT_WIN = last 3 bytes.
; -----------------------------------------------------------------------------
WaitCode:
        sta     PT_MASK         ; A = mask: bit0 GOO, 1 BAD, 2 ACK, 3 S/B, 4 SYN
        lda     #$00
        sta     PT_WIN
        sta     PT_WIN+1
        sta     PT_WIN+2
WaitCodeReset:
        lda     #$00
        sta     PT_TIMER
        sta     PT_TIMER+1
WaitCodeLoop:
        jsr     CheckAbort      ; C= key aborts
        jsr     GetRs2          ; next RS-232 byte, if any
        lda     PTSTAT
        bne     WaitCodeIdle    ; no byte
        lda     PT_WIN+1        ; shift the 3-byte window
        sta     PT_WIN
        lda     PT_WIN+2
        sta     PT_WIN+1
        lda     BUF
        sta     PT_WIN+2
        lda     #$00
        sta     PT_IDX
        lda     #$01
        sta     PT_BIT
WaitCodeTry:
        lda     PT_MASK         ; is this code accepted?
        bit     PT_BIT
        beq     WaitCodeNext
        ldy     PT_IDX
        ldx     #$00
WaitCodeCmp:
        lda     PT_WIN,x
        cmp     PtCodes,y
        bne     WaitCodeNext
        iny
        inx
        cpx     #$03
        bne     WaitCodeCmp
        jmp     WaitCodeHit
WaitCodeNext:
        asl     PT_BIT
        lda     PT_IDX
        clc
        adc     #$03
        sta     PT_IDX
        cmp     #$0F
        bne     WaitCodeTry
        jmp     WaitCodeReset
WaitCodeHit:
        lda     #$FF            ; code found: wait until the line is quiet
        sta     PT_TIMER
        sta     PT_TIMER+1
        jmp     WaitCodeLoop
WaitCodeIdle:
        inc     PT_TIMER
        bne     WaitCodeTime
        inc     PT_TIMER+1
WaitCodeTime:
        lda     PT_TIMER+1
        ora     PT_TIMER
        beq     WaitCodeOk
        lda     PT_TIMER
        cmp     #$07            ; result of this CMP is lost (next LDA) ; ?
        lda     PT_TIMER+1
        cmp     #$14
        bcc     WaitCodeLoop
        lda     #$01            ; timeout: PTSTAT = 1
        sta     PTSTAT
        jmp     Retry
WaitCodeOk:
        lda     #$00            ; success
        sta     PTSTAT
        rts

; -----------------------------------------------------------------------------
; GetRs - $30F7 / $30F8
; Purpose : Take one byte from the KERNAL RS-232 input buffer directly.
; Inputs  : none.
; Outputs : PTSTAT = 0 and BUF = byte, or PTSTAT = 2 and BUF = 0 (empty).
;           Y kept. FA = 3. ; ?
; -----------------------------------------------------------------------------
GetRs:  nop                     ; entry used by DumbTerm
GetRs2: tya
        pha
        lda     RIDBE
        cmp     RIDBS           ; buffer empty?
        beq     GetRsEmpty
        ldy     RIDBS
        lda     (RIBUF),y       ; LDA (RIBUF),RIDBS
        pha
        inc     RIDBS           ; remove the byte from the buffer
        lda     #$00
        sta     PTSTAT
        pla
        sta     BUF
        pla
        tay
        jmp     GetRsDone
GetRsEmpty:
        lda     #$02            ; no byte: PTSTAT = 2
        sta     PTSTAT
        lda     #$00
        sta     BUF
        pla
        tay
GetRsDone:
        pha                     ; FA = 3 ; ? why
        lda     #$03
        sta     FA
        pla
        rts

; -----------------------------------------------------------------------------
; SendCode - $312A
; Purpose : Send the 3-letter code at PtCodes+Y to file 5 (modem).
; Inputs  : Y = 0, 3, 6, 9 or 12.   Outputs: CLRCHN.
; -----------------------------------------------------------------------------
SendCode:
        ldx     #$05            ; output to file 5 (modem)
        jsr     CHKOUT
        ldx     #$00
SendCodeLoop:
        lda     PtCodes,y       ; Y = code offset in PtCodes
        jsr     CHROUT
        iny
        inx
        cpx     #$03
        bne     SendCodeLoop
        jmp     CLRCHN

; -----------------------------------------------------------------------------
; RecvBlock - $3140 (receiver)
; Purpose : Answer GOO or BAD, wait for ACK, send S/B and read the next
;           block into PT_BUF0. After the last block, do the end handshake
;           (wait for SYN, send SYN until S/B comes).
; Inputs  : A = PT_CODE = 0 (GOO) or 3 (BAD); PT_BUF0+4 = expected length.
; Outputs : PTSTAT from ReadBlock (1 = full block).
; -----------------------------------------------------------------------------
RecvBlock:
        sta     PT_CODE         ; A = code to send first (0 GOO, 3 BAD)
        lda     #$00
        sta     PT_SENDER
RecvSendCode:
        lda     #$02
        sta     ZTMP
        ldy     PT_CODE
        jsr     SendCode
RecvWaitAck:
        lda     #$04            ; wait for ACK
        jsr     WaitCode
        lda     PTSTAT
        beq     RecvSendSB
        dec     ZTMP
        bne     RecvWaitAck
        jmp     RecvSendCode
RecvSendSB:
        ldy     #$09            ; send S/B
        jsr     SendCode
        lda     PT_LAST
        beq     RecvData
        lda     PT_CODE
        beq     RecvEnd
RecvData:
        lda     PT_BUF0+4       ; expected length of this block
        sta     PT_LEN
        sta     PT_NXTLEN
        jsr     ReadBlock       ; read it
        lda     PTSTAT
        cmp     #$01
        beq     RecvDone
        cmp     #$02
        beq     RecvSendSB
        cmp     #$04
        beq     RecvDone
        cmp     #$08
        beq     RecvSendSB
RecvDone:
        rts
RecvEnd:
        lda     #$10            ; last block: wait for SYN
        jsr     WaitCode
        lda     PTSTAT
        bne     RecvSendSB
        lda     #$0A
        sta     PT_LEN
RecvEndLoop:
        ldy     #$0C            ; send SYN
        jsr     SendCode
        lda     #$08            ; wait for S/B
        jsr     WaitCode
        lda     PTSTAT
        beq     RecvEndDone
        dec     PT_LEN
        bne     RecvEndLoop
RecvEndDone:
        rts

; -----------------------------------------------------------------------------
; SendBlock - $31B2 (transmitter)
; Purpose : Wait for GOO/BAD/S/B. On GOO, prepare the next block (FillBlock)
;           or end the transfer; on BAD, send the same block again. Then send
;           ACK, wait for S/B and send the block from the other buffer.
;           Prints progress marks "-" (good), ":" (repeat), "*" (end).
; Outputs : A = 0 more blocks, A = 1 transfer done.
; -----------------------------------------------------------------------------
SendBlock:
        lda     #$01            ; this side transmits
        sta     PT_SENDER
SendWait:
        lda     PT_SENDGO       ; type block: send GOO first
        beq     SendWait2
        ldy     #$00
        jsr     SendCode
SendWait2:
        lda     #$0B            ; wait for GOO, BAD or S/B
        jsr     WaitCode
        lda     PTSTAT
        bne     SendWait
        lda     #$00
        sta     PT_SENDGO
        lda     PT_IDX          ; not GOO: send the block again
        cmp     #$00
        bne     SendAgain
        lda     PT_LAST         ; GOO after the last block: end
        bne     SendEnd
        inc     PT_BLKNO        ; block number + 1
        bne     SendNext
        inc     PT_BLKNO+1
SendNext:
        jsr     CurBuf
        ldy     #$05
        iny
        lda     (PTPTR),y       ; block number hi = $FF: last block?
        cmp     #$FF
        bne     SendRead
        lda     #$01
        sta     PT_LAST
        lda     PT_BUFSEL
        eor     #$01
        sta     PT_BUFSEL
        jsr     CurBuf
        jsr     FinishBlock
        jmp     SendGood
SendRead:
        jsr     FillBlock       ; read the next block from the file
SendGood:
        lda     #'-'
        .byte   $2C             ; BIT abs: hides LDA #':'
SendAgain:
        lda     #':'
        jsr     Progress        ; progress mark
        ldy     #$06
        jsr     SendCode        ; send ACK
        lda     #$08
        jsr     WaitCode        ; wait for S/B
        lda     PTSTAT
        bne     SendGood
        jsr     CurBuf
        ldy     #$04
        lda     (PTPTR),y
        sta     PT_LEN
        jsr     OtherBuf
        ldx     #$05            ; send the block
        jsr     CHKOUT
        ldy     #$00
SendBytes:
        lda     (PTPTR),y
        jsr     CHROUT
        iny
        cpy     PT_LEN
        bne     SendBytes
        jsr     CLRCHN
        lda     #$00
        rts
SendEnd:
        lda     #'*'            ; end: progress mark "*"
        jsr     Progress
        ldy     #$06
        jsr     SendCode
        lda     #$08
        jsr     WaitCode
        lda     PTSTAT
        bne     SendEnd
        lda     #$0A
        sta     PT_LEN
SendEndSyn:
        ldy     #$0C
        jsr     SendCode
        lda     #$10
        jsr     WaitCode
        lda     PTSTAT
        beq     SendEndSB
        dec     PT_LEN
        bne     SendEndSyn
SendEndSB:
        lda     #$03
        sta     PT_LEN
SendEndSBLoop:
        ldy     #$09
        jsr     SendCode
        lda     #$00
        jsr     WaitCode
        dec     PT_LEN
        bne     SendEndSBLoop
        lda     #$01
        rts

; -----------------------------------------------------------------------------
; ReadBlock - $3285
; Purpose : Read PT_LEN bytes from RS-232 into PT_BUF0. If the first three
;           bytes are "ACK", keep waiting (the sender has not seen S/B yet).
; Outputs : PTSTAT = 1 block read, 2 timeout (no bytes), 4 timeout (some
;           bytes), 8 ACK and then quiet.
; -----------------------------------------------------------------------------
ReadBlock:
        ldy     #$00            ; Y = byte count
ReadBlockByte:
        lda     #$00
        sta     PT_TIMER
        sta     PT_TIMER+1
ReadBlockLoop:
        jsr     CheckAbort
        jsr     GetRs2
        lda     PTSTAT
        bne     ReadBlockIdle
        lda     BUF
        sta     PT_BUF0,y       ; store in PT_BUF0
        cpy     #$03            ; first 3 bytes: look for "ACK"
        bcs     ReadBlockNext
        sta     PT_WIN,y
        cpy     #$02
        bne     ReadBlockNext
        lda     PT_WIN
        cmp     #'A'
        bne     ReadBlockNext
        lda     PT_WIN+1
        cmp     #'C'
        bne     ReadBlockNext
        lda     PT_WIN+2
        cmp     #'K'
        beq     ReadBlockAck
ReadBlockNext:
        iny
        cpy     PT_LEN
        bne     ReadBlockByte
        lda     #$01            ; whole block read
        sta     PTSTAT
        rts
ReadBlockAck:
        lda     #$FF
        sta     PT_TIMER
        sta     PT_TIMER+1
        jmp     ReadBlockLoop
ReadBlockIdle:
        inc     PT_TIMER
        bne     ReadBlockTime
        inc     PT_TIMER+1
ReadBlockTime:
        lda     PT_TIMER
        ora     PT_TIMER+1
        beq     ReadBlockQuiet
        lda     PT_TIMER
        cmp     #$06            ; result of this CMP is lost (next LDA) ; ?
        lda     PT_TIMER+1
        cmp     #$10
        bne     ReadBlockLoop
        lda     #$02            ; timeout, no bytes: PTSTAT = 2
        sta     PTSTAT
        cpy     #$00
        beq     ReadBlockTO
        lda     #$04            ; timeout after some bytes: PTSTAT = 4
        sta     PTSTAT
ReadBlockTO:
        jmp     Retry
ReadBlockQuiet:
        lda     #$08            ; ACK then quiet: PTSTAT = 8
        sta     PTSTAT
        rts

; -----------------------------------------------------------------------------
; FillBlock - $3305
; Purpose : Swap buffers, write the next block number into bytes 5-6 and
;           read up to PT_BLKSIZ-7 data bytes from file 2 into bytes 7...
;           At end of file, byte 6 = $FF (last block).
; Outputs : continues in FinishBlock.
; -----------------------------------------------------------------------------
FillBlock:
        lda     PT_BUFSEL       ; swap the buffers
        eor     #$01
        sta     PT_BUFSEL
        jsr     CurBuf
        ldy     #$05            ; block number + 1 into bytes 5-6
        lda     PT_BLKNO
        clc
        adc     #$01
        sta     (PTPTR),y
        iny
        lda     PT_BLKNO+1
        adc     #$00
        sta     (PTPTR),y
        ldx     #$02            ; input from file 2 (the disk file)
        jsr     CHKIN
        ldy     #$07
FillBlockLoop:
        jsr     CHRIN
        sta     (PTPTR),y
        iny
        jsr     READST          ; end of file?
        bne     FillBlockEof
        cpy     PT_BLKSIZ
        bne     FillBlockLoop
        tya
        pha
        jmp     FinishBlock2
FillBlockEof:
        tya
        pha
        ldy     #$05
        iny
        lda     #$FF            ; mark: last block (byte 6 = $FF)
        sta     (PTPTR),y
        jmp     FinishBlock2

; -----------------------------------------------------------------------------
; FinishBlock - $334A / $334B
; Purpose : Wait for the modem output, wait a short time, store the length
;           of the new block (Y on the stack) in byte 4 of the other buffer
;           and compute its checksum.
; -----------------------------------------------------------------------------
FinishBlock:
        pha
FinishBlock2:
        jsr     CLRCHN
        jsr     WaitTx          ; let the modem output finish
        jsr     Delay           ; short delay
        jsr     WaitTx
        ldy     #$04
        lda     (PTPTR),y
        sta     PT_LEN
        jsr     OtherBuf
        pla                     ; Y (bytes read) = size of the next block
        ldy     #$04
        sta     (PTPTR),y
        jsr     Checksum        ; compute the checksum
        rts

; -----------------------------------------------------------------------------
; CurBuf - $336A: PTPTR = PT_BUF0 + PT_BUFSEL * 256.
; -----------------------------------------------------------------------------
CurBuf: lda     #$00            ; PTPTR = PT_BUF0 + PT_BUFSEL*256
        sta     PTPTR
        lda     PT_BUFSEL
        clc
        adc     #>PT_BUF0
        sta     PTPTR+1
        rts

; -----------------------------------------------------------------------------
; OtherBuf - $3377: PTPTR = PT_BUF0 + (PT_BUFSEL xor 1) * 256.
; -----------------------------------------------------------------------------
OtherBuf:
        lda     #$00            ; PTPTR = the other buffer
        sta     PTPTR
        lda     PT_BUFSEL
        eor     #$01
        clc
        adc     #>PT_BUF0
        sta     PTPTR+1
        rts

; -----------------------------------------------------------------------------
; Checksum - $3386
; Purpose : Compute the Punter checksums over bytes 4 .. PT_LEN-1 of the
;           block at PTPTR: a 16-bit add sum and a 16-bit "CLC" sum (XOR,
;           then rotate left). Store them in bytes 0-3 and in PT_SUM.
; -----------------------------------------------------------------------------
Checksum:
        lda     #$00            ; clear the 4 checksum bytes
        sta     PT_SUM
        sta     PT_SUM+1
        sta     PT_SUM+2
        sta     PT_SUM+3
        ldy     #$04
ChecksumLoop:
        lda     PT_SUM          ; additive sum (16 bit)
        clc
        adc     (PTPTR),y
        sta     PT_SUM
        bcc     ChecksumNc
        inc     PT_SUM+1
ChecksumNc:
        lda     PT_SUM+2        ; cyclic sum: XOR then rotate
        eor     (PTPTR),y
        sta     PT_SUM+2
        lda     PT_SUM+3
        rol     a
        rol     PT_SUM+2
        rol     PT_SUM+3
        iny
        cpy     PT_LEN
        bne     ChecksumLoop
        ldy     #$00            ; store the sums in bytes 0-3
        lda     PT_SUM
        sta     (PTPTR),y
        iny
        lda     PT_SUM+1
        sta     (PTPTR),y
        iny
        lda     PT_SUM+2
        sta     (PTPTR),y
        iny
        lda     PT_SUM+3
        sta     (PTPTR),y
        rts

; -----------------------------------------------------------------------------
; SendFile - $33D6 (function 6, pc.ml SYS $20A8)
; Purpose : Send the file open as logical file 2 with the Punter protocol.
; Inputs  : file 2 open for reading, file 5 = modem, PT_BLKSIZ set.
; Outputs : BUF = 0 (or 1 if aborted with C=).
; -----------------------------------------------------------------------------
SendFile:
        lda     #$00
        sta     PT_LAST
        sta     PT_TRIES
        sta     PT_TYPEBL
        lda     #$01
        sta     PT_BUFSEL
        lda     #$FF
        sta     PT_BLKNO        ; first block has 7 bytes (header only)
        sta     PT_BLKNO+1
        jsr     OtherBuf
        ldy     #$04
        lda     #$07
        sta     (PTPTR),y
        jsr     CurBuf
        ldy     #$05
        lda     #$00
        sta     (PTPTR),y
        iny
        sta     (PTPTR),y
SendFileLoop:
        jsr     SendBlock       ; until SendBlock says "end"
        beq     SendFileLoop
RecvFileDone:
        lda     #$00
        sta     BUF
        rts

; -----------------------------------------------------------------------------
; RecvFile - $340E (function 3, pc.ml SYS $20A5)
; Purpose : Receive a file with the Punter protocol and write the data
;           to logical file 2. Prints "-" per good block, ":" per bad block
;           and "*" at the end.
; Inputs  : file 2 open for writing, file 5 = modem.
; Outputs : BUF = 0 (or 1 if aborted with C=).
; -----------------------------------------------------------------------------
RecvFile:
        lda     #$01
        sta     PT_BLKNO        ; start at block 1
        lda     #$00
        sta     PT_BLKNO+1
        sta     PT_LAST
        sta     PT_BUFSEL
        sta     PT_BUF0+5
        sta     PT_BUF0+6
        sta     PT_TRIES
        lda     #$07            ; first block length 7
        sta     PT_BUF0+4
        lda     #$00            ; answer GOO
RecvFileLoop:
        jsr     RecvBlock
        lda     PT_LAST         ; end of transfer?
        bne     RecvFileDone
        jsr     CheckBlock      ; checksum good?
        bne     RecvFileBad
        jsr     CLRCHN
        lda     PT_LEN          ; header only: nothing to write
        cmp     #$07
        beq     RecvFileMark
        ldx     #$02            ; output to file 2 (disk file)
        jsr     CHKOUT
        ldy     #$07
RecvFileWrite:
        lda     PT_BUF0,y
        jsr     CHROUT
        iny
        cpy     PT_LEN
        bne     RecvFileWrite
        jsr     CLRCHN
RecvFileMark:
        lda     PT_BUF0+6       ; last block?
        cmp     #$FF
        bne     RecvFileDash
        lda     #$01
        sta     PT_LAST
        lda     #'*'
        .byte   $2C             ; BIT abs: hides LDA #'-'
RecvFileDash:
        lda     #'-'
RecvFileOut:
        jsr     CHROUT
        jsr     WaitTx          ; wait for modem output
        lda     #$00            ; answer GOO
        jmp     RecvFileLoop
RecvFileBad:
        jsr     CLRCHN
        lda     #':'
        jsr     CHROUT
        lda     PT_NXTLEN       ; expect the same length again
        sta     PT_BUF0+4
        lda     #$03            ; answer BAD
        jmp     RecvFileLoop

; -----------------------------------------------------------------------------
; CheckBlock - $348A
; Purpose : Check the checksum of the block in PT_BUF0.
; Outputs : A = 0 and Z=1 good, A = 1 and Z=0 bad.
; -----------------------------------------------------------------------------
CheckBlock:
        lda     PT_BUF0         ; keep the 4 checksum bytes of the block
        sta     PT_RXSUM
        lda     PT_BUF0+1
        sta     PT_RXSUM+1
        lda     PT_BUF0+2
        sta     PT_RXSUM+2
        lda     PT_BUF0+3
        sta     PT_RXSUM+3
        jsr     CurBuf
        lda     PT_NXTLEN
        sta     PT_LEN
        jsr     Checksum        ; compute them again
        lda     PT_BUF0
        cmp     PT_RXSUM
        bne     CheckBlockBad
        lda     PT_BUF0+1
        cmp     PT_RXSUM+1
        bne     CheckBlockBad
        lda     PT_BUF0+2
        cmp     PT_RXSUM+2
        bne     CheckBlockBad
        lda     PT_BUF0+3
        cmp     PT_RXSUM+3
        bne     CheckBlockBad
        lda     #$00
        rts
CheckBlockBad:
        lda     #$01
        rts

; -----------------------------------------------------------------------------
; RecvType - $34D4 (function 9, pc.ml SYS $20AB)
; Purpose : Receive the 8-byte file-type block. The type goes to PT_FTYPE.
; Outputs : BUF = 0.
; -----------------------------------------------------------------------------
RecvType:
        lda     #$00
        sta     PT_BLKNO
        sta     PT_BLKNO+1
        sta     PT_LAST
        sta     PT_BUFSEL
        sta     PT_TRIES
        lda     #$07            ; type block is 8 bytes
        clc
        adc     #$01
        sta     PT_BUF0+4
        lda     #$00
RecvTypeLoop:
        jsr     RecvBlock
        lda     PT_LAST
        bne     RecvTypeDone
        jsr     CheckBlock
        bne     RecvTypeBad
        lda     PT_BUF0+7       ; byte 7 = file type
        sta     PT_FTYPE
        lda     #$01
        sta     PT_LAST
        lda     #$00
        jmp     RecvTypeLoop
RecvTypeBad:
        lda     PT_NXTLEN
        sta     PT_BUF0+4
        lda     #$03
        jmp     RecvTypeLoop
RecvTypeDone:
        lda     #$00
        sta     BUF
        rts

; -----------------------------------------------------------------------------
; SendType - $351D (function 12, pc.ml SYS $20AE)
; Purpose : Send the 8-byte file-type block with PT_FTYPE (no progress marks).
; Inputs  : PT_FTYPE.   Outputs: BUF = 0.
; -----------------------------------------------------------------------------
SendType:
        lda     #$00
        sta     PT_LAST
        sta     PT_TRIES
        lda     #$01
        sta     PT_BUFSEL
        sta     PT_TYPEBL
        lda     #$FF
        sta     PT_BLKNO
        sta     PT_BLKNO+1
        jsr     OtherBuf
        ldy     #$04
        lda     #$07            ; type block is 8 bytes
        clc
        adc     #$01
        sta     (PTPTR),y
        jsr     CurBuf
        ldy     #$05
        lda     #$FF            ; block number $FFFF: last block
        sta     (PTPTR),y
        iny
        sta     (PTPTR),y
        ldy     #$07
        lda     PT_FTYPE        ; byte 7 = file type
        sta     (PTPTR),y
        lda     #$01            ; send GOO first
        sta     PT_SENDGO
SendTypeLoop:
        jsr     SendBlock
        beq     SendTypeLoop
        lda     #$00
        sta     BUF
        rts

; -----------------------------------------------------------------------------
; Retry - $3564
; Purpose : Count a retry in PT_TRIES and wait a little (Delay) depending on
;           the side (sender or receiver) and on the count. ; ?
; -----------------------------------------------------------------------------
Retry:  inc     PT_TRIES        ; one more retry
        lda     PT_TRIES
        cmp     #$03
        bcc     RetryFew
        lda     #$00
        sta     PT_TRIES
        lda     PT_SENDER
        beq     Delay
        bne     RetryDone
RetryFew:
        lda     PT_SENDER
        beq     RetryDone

; -----------------------------------------------------------------------------
; Delay - $357F: busy loop, 120 x 256 passes.
; -----------------------------------------------------------------------------
Delay:  ldx     #$00            ; about 0.15 s at 1 MHz ; ?
DelayOuter:
        ldy     #$00
DelayInner:
        iny
        bne     DelayInner
        inx
        cpx     #$78
        bne     DelayOuter
RetryDone:
        rts

; -----------------------------------------------------------------------------
; Progress - $358C
; Purpose : Print the progress mark in A, but not for block 0 and not
;           while the type block is sent.   A kept.
; -----------------------------------------------------------------------------
Progress:
        pha                     ; A = character, kept
        lda     PT_BLKNO
        ora     PT_BLKNO+1
        beq     ProgressDone    ; block 0: no mark
        lda     PT_TYPEBL
        bne     ProgressDone    ; type block: no mark
        pla
        jsr     CHROUT
        pha
ProgressDone:
        pla
        rts

; -----------------------------------------------------------------------------
; WaitTx - $35A1 (via $3015, pc.ml SYS $20B7)
; Purpose : Wait until the RS-232 output is idle: loop while ENABL is
;           $80 or $92. ; ? (meaning of these values not checked)
; -----------------------------------------------------------------------------
WaitTx: jsr     K_RSWAIT        ; KERNAL RS-232 helper ; ?
        lda     ENABL           ; RS-232 still busy?
        cmp     #$80
        beq     WaitTx
        cmp     #$92
        beq     WaitTx
        rts

; -----------------------------------------------------------------------------
; DumbTerm - $35B0 (function 15)
; Purpose : Simple ASCII terminal with a block cursor. RS-232 input is
;           translated ASCII -> PETSCII and printed; keys are translated
;           PETSCII -> ASCII and sent to file 5. HOME returns.
; Outputs : BUF = last key.
; -----------------------------------------------------------------------------
DumbTerm:
        jsr     ShowCursor      ; show the cursor
DumbTermLoop:
        jsr     GetRs           ; RS-232 byte?
        lda     PTSTAT
        bne     DumbTermKey0
        lda     BUF
        and     #$7F            ; strip bit 7
        sta     BUF
        cmp     #$08
        beq     DumbTermRx
        cmp     #$0D
        beq     DumbTermRx
        cmp     #$20
        bpl     DumbTermRx
DumbTermKey0:
        jmp     DumbTermKey
DumbTermRx:
        cmp     #$61            ; ASCII a-z -> PETSCII $41-$5A
        bcc     DumbTermUc
        cmp     #$7B
        bcs     DumbTermUc
        sec
        sbc     #$20
        sta     BUF
        jmp     DumbTermBs
DumbTermUc:
        cmp     #$41            ; ASCII A-Z -> PETSCII $C1-$DA
        bcc     DumbTermBs
        cmp     #$5B
        bcs     DumbTermBs
        clc
        adc     #$80
        sta     BUF
DumbTermBs:
        cmp     #$08            ; BS -> DEL
        bne     DumbTermQuote
        lda     #$14
        sta     BUF
DumbTermQuote:
        cmp     #$22            ; quote: print it, then DEL, so quote mode ends ; ?
        bne     DumbTermCr
        jsr     CHROUT
        lda     #$14
        jsr     CHROUT
        lda     #$22
DumbTermCr:
        lda     BUF
        cmp     #$0D            ; CR: print a space first (erase cursor)
        bne     DumbTermOut
        lda     #$20
        jsr     CHROUT
        lda     #$0D
DumbTermOut:
        jsr     CHROUT
        jsr     ShowCursor
DumbTermKey:
        jsr     GETIN           ; keyboard
        beq     DumbTermLoop
        sta     BUF
        cmp     #$13            ; HOME: back to BASIC
        beq     DumbTermExit
        cmp     #$41            ; PETSCII $41-$5A -> ASCII a-z
        bcc     DumbTermKeyUc
        cmp     #$5B
        bcs     DumbTermKeyUc
        clc
        adc     #$20
        sta     BUF
        jmp     DumbTermKeyDel
DumbTermKeyUc:
        lda     BUF
        cmp     #$C1            ; PETSCII $C1-$DA -> ASCII A-Z
        bcc     DumbTermKeyDel
        cmp     #$DB
        bcs     DumbTermKeyDel
        sec
        sbc     #$80
        sta     BUF
DumbTermKeyDel:
        cmp     #$14            ; DEL -> BS
        bne     DumbTermKeyRun
        lda     #$08
        sta     BUF
DumbTermKeyRun:
        cmp     #$83            ; RUN/STOP+SHIFT ($83) -> CTRL-P ; ?
        bne     DumbTermSend
        lda     #$10
        sta     BUF
DumbTermSend:
        ldx     #$05            ; output to file 5 (modem)
        jsr     CHKOUT
        lda     BUF
        jsr     CHROUT
        jsr     CLRCHN
        jmp     DumbTerm
DumbTermExit:
        rts

; -----------------------------------------------------------------------------
; ShowCursor - $366D
; Purpose : Print RVS ON, a block character, CRSR LEFT, RVS OFF, then
;           continue in CheckAbort.
; -----------------------------------------------------------------------------
ShowCursor:
        lda     #$12            ; RVS ON
        jsr     CHROUT
        lda     #$B8            ; cursor block character ; ?
        jsr     CHROUT
        lda     #$9D            ; CRSR LEFT
        jsr     CHROUT
        lda     #$92            ; RVS OFF
        jsr     CHROUT

; -----------------------------------------------------------------------------
; CheckAbort - $3681
; Purpose : If the C= key is down, pull bytes from the stack until SP =
;           PT_SAVESP, so the RTS returns directly to BASIC (abort).
; Outputs : BUF = 1 (in both cases; callers overwrite it).
; -----------------------------------------------------------------------------
CheckAbort:
        lda     SHFLAG          ; C= key down?
        nop
        cmp     #$02
        bne     CheckAbortSet
CheckAbortPop:
        pla                     ; yes: pull bytes until SP is back at ...
        tsx
        cpx     PT_SAVESP       ; ... the value saved by PtDispatch
        bne     CheckAbortPop
CheckAbortSet:
        lda     #$01            ; BUF = 1 (abort flag for BASIC)
        sta     BUF
        rts

; -----------------------------------------------------------------------------
; HookBsout - $3695 (via $3018, pc.ml SYS $20BA)
; Purpose : Point the BSOUT vector IBSOUT at NewBsout (once). The old
;           vector is saved in OLDBSOUT.
; -----------------------------------------------------------------------------
HookBsout:
        lda     IBSOUT          ; already hooked?
        cmp     #<NewBsout
        bne     HookBsoutSet
        lda     IBSOUT+1
        cmp     #>NewBsout
        beq     HookBsoutDone
HookBsoutSet:
        lda     IBSOUT          ; save the old vector
        sta     OLDBSOUT
        lda     IBSOUT+1
        sta     OLDBSOUT+1
        lda     #<NewBsout      ; IBSOUT -> NewBsout
        sta     IBSOUT
        lda     #>NewBsout
        sta     IBSOUT+1
HookBsoutDone:
        rts

; -----------------------------------------------------------------------------
; NewBsout - $36BA (CHROUT through IBSOUT)
; Purpose : Faster CHROUT for RS-232: devices 0 and 2 put the byte into the
;           KERNAL RS-232 output buffer (RsPut); device 1 uses the cassette
;           path copied from the KERNAL; device 3 and up use the old routine.
; Inputs  : A = character.   Outputs: A = character, C = 0 (A = 0 on error).
; -----------------------------------------------------------------------------
NewBsout:
        pha
        lda     DFLTO           ; device 3 (screen)?
        cmp     #$03
        bne     NewBsoutDev
        pla
        jmp     (OLDBSOUT)      ; yes: old routine
NewBsoutDev:
        bcc     NewBsoutMine    ; device 0-2: handled here
        pla                     ; device > 3: old routine
        jmp     (OLDBSOUT)
NewBsoutMine:
        lsr     a               ; device 0..2: C=1 for 1 (cassette)
        pla
        sta     OUTCHR
        txa
        pha
        tya
        pha
        bcc     NewBsoutRs      ; device 0 or 2: RS-232 path
        jsr     K_TAPEBUF       ; cassette (copied from the KERNAL) ; ?
        bne     NewBsoutTape
        jsr     K_TAPEWR
        bcs     NewBsoutExit
        lda     #$02
        ldy     #$00
        sta     (TAPE1),y
        iny
        sty     BUFPT
NewBsoutTape:
        lda     OUTCHR
        sta     (TAPE1),y
NewBsoutOk:
        clc
NewBsoutExit:
        pla
        tay
        pla
        tax
        lda     OUTCHR
        bcc     NewBsoutRts
        lda     #$00            ; error: A = 0
NewBsoutRts:
        rts
NewBsoutRs:
        jsr     RsPut
        jmp     NewBsoutOk

; -----------------------------------------------------------------------------
; RsPut - $3701 (entry $36FE: start the output first)
; Purpose : Put OUTCHR into the RS-232 output buffer at ROBUF; wait while
;           the buffer is full. Then start the transmitter (RsStart).
; -----------------------------------------------------------------------------
RsPutWait:
        jsr     RsStart         ; buffer full: start output and try again
RsPut:  ldy     RODBE           ; end index + 1
        iny
        cpy     RODBS           ; = start index: buffer full
        beq     RsPutWait
        sty     RODBE
        dey
        lda     OUTCHR
        sta     (ROBUF),y       ; STA (ROBUF),old end index

; -----------------------------------------------------------------------------
; RsStart - $3712
; Purpose : If the transmitter is not running (ENABL bit 0 = 0), load CIA2
;           timer A with RS_BAUD and start it with the NMI enabled.
; -----------------------------------------------------------------------------
RsStart:
        lda     ENABL           ; transmitter already running?
        lsr     a
        bcs     RsStartDone
        lda     #$10            ; stop timer A, force load
        sta     CIA2_CRA
        lda     RS_BAUD         ; baud rate value
        sta     CIA2_TALO
        lda     RS_BAUD+1
        sta     CIA2_TAHI
        lda     #$81            ; enable the timer A NMI ; ?
        jsr     K_RSNMI
        jsr     K_RSSTART
        lda     #$11            ; start timer A (continuous)
        sta     CIA2_CRA
RsStartDone:
        rts

; -----------------------------------------------------------------------------
; Fill3 - $3737-$377F: not used ($07, $1A fill, $00 $FF).
; -----------------------------------------------------------------------------
Fill3:  .byte   $07,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A ; $3737
        .byte   $1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A ; $3747
        .byte   $1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A ; $3757
        .byte   $1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A,$1A ; $3767
        .byte   $1A,$1A,$1A,$1A,$1A,$1A,$1A,$00,$FF ; $3777

; end of pc.ml6 ($2A00-$377F, 3456 bytes)
