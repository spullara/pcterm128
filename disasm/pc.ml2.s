; =============================================================================
; pc.ml2.s - PC-Term 128, module PC.ML2: terminal (online) loop
; =============================================================================
; Original file : pc.ml2 (C128 PRG, load address $0B00, 165 bytes of code)
; Assembler     : ca65/ld65 (cc65 2.19). Rebuild and compare with
;                 disasm/verify.sh  (or: ca65 pc.ml2.s -o pc.ml2.o &&
;                 ld65 -t none -o pc.ml2.bin pc.ml2.o && cmp pc.ml2.bin ../pc.ml2)
; Loaded by     : pcterm line 727  BLOAD"pc.ml2",p2816,b0
;                 (line 727 checks PEEK(2816)=32, the first JSR opcode)
; Called by     : pcterm line 4600 tr%=1:BANK15:SLOW:SYS2816:FAST ...
;
; The module is ONE routine (TermLoop) plus a helper (BufStore). TermLoop
; copies modem -> screen and keyboard -> modem until the user presses
; ALT or HOME, or until the capture buffer becomes full. It is the
; inner loop of terminal mode. It does NOT do RS-232 bit handling itself;
; it uses the KERNAL RS-232 driver through logical file 5
; (pcterm line 40: OPEN5,2,0,...).
;
; Control bytes in the page after the code (set by BASIC with POKE):
;   $0BFC (3068) DUPLEX  dp: 1 = half duplex (echo typed chars locally)
;   $0BFD (3069) CHRMODE cm: 1 = no translation (Commodore/PETSCII mode)
;   $0BFE (3070) BUFFULL $FF = capture buffer is full
;   $0BFF (3071) BUFOPEN 1 = capture buffer is open (capture is on)
; Capture buffer: bank 1 RAM from $8000; next free byte pointer in
;   zero page $FA/$FB (BASIC: POKE250,0:POKE251,128). Full when the
;   high byte reaches $FF (that is, at $FF00).
; =============================================================================

        .setcpu "6502"

; ---- C128 KERNAL jump table -------------------------------------------------
INDSTA  := $FF77                ; store A to (STAVEC),Y in bank X
READST  := $FFB7                ; read I/O status byte
CHKIN   := $FFC6                ; open channel for input (X = logical file)
CHKOUT  := $FFC9                ; open channel for output (X = logical file)
CLRCHN  := $FFCC                ; restore default I/O (keyboard/screen)
CHROUT  := $FFD2                ; output character in A
GETIN   := $FFE4                ; get character from input channel (0 = none)

; ---- C128 zero page / system RAM --------------------------------------------
SHFLAG  := $D3                  ; modifier keys: 1 Shift 2 C= 4 Ctrl 8 Alt
QTSW    := $F4                  ; screen editor quote-mode flag
BUFPTR  := $FA                  ; capture buffer pointer lo (program use)
BUFPTRH := $FB                  ; capture buffer pointer hi (program use)
STAVEC  := $02B9                ; INDSTA: zero-page address of the pointer

; ---- program data -----------------------------------------------------------
ASCTAB  := $1400                ; pc.ascii translation table (BLOAD p5120)
DUPLEX  := $0BFC
CHRMODE := $0BFD
BUFFULL := $0BFE
BUFOPEN := $0BFF

MODEMLF = 5                     ; logical file number of the modem (OPEN5,2)
KEY_ALT = $08                   ; SHFLAG bit for the ALT key
ST_RXEMPTY = $08                ; RS-232 status bit: receive buffer empty

        .word   $0B00           ; PRG load address
        .org    $0B00

; -----------------------------------------------------------------------------
; TermLoop - $0B00 (SYS2816)
; Purpose : Terminal loop. Each pass: if a byte came from the modem, show
;           it (and capture it); then if a key was pressed, send it to the
;           modem (and echo it in half duplex).
; Inputs  : logical file 5 open to the RS-232 device; DUPLEX, CHRMODE,
;           BUFOPEN, BUFFULL; BUFPTR/BUFPTRH; ASCTAB loaded at $1400.
; Outputs : returns to BASIC when
;             - ALT is held (SHFLAG = 8), or
;             - HOME/CTRL-S ($13) is typed, or
;             - capture is on and the buffer becomes full (BUFFULL = $FF;
;               BASIC line 4600 checks PEEK(3070)=255 AND PEEK(3071)=1).
;           Bytes received are stored in bank 1 at (BUFPTR) when BUFOPEN=1.
; Note    : On the "buffer full" exit the routine returns with the modem
;           still selected as input channel (no CLRCHN). ; ?
; -----------------------------------------------------------------------------
TermLoop:
        jsr     CLRCHN
        lda     #$00
        sta     QTSW            ; never stay in quote mode
        lda     SHFLAG
        cmp     #KEY_ALT        ; ALT held alone -> leave
        beq     Exit
        jsr     READST
        and     #ST_RXEMPTY     ; nothing received?
        bne     CheckKey
; ---- modem -> screen
        ldx     #MODEMLF
        jsr     CHKIN
        jsr     GETIN
        cmp     #$0A            ; ignore line feed
        beq     TermLoop
        cmp     #$8E            ; ignore $8E (C= "upper case/graphics" code)
        beq     TermLoop
        ldy     CHRMODE
        cpy     #$01            ; CHRMODE=1: show the byte as it is
        beq     @noxlat
        tax                     ; else translate through ASCTAB  ; ? ASCII->PETSCII
        lda     ASCTAB,x
@noxlat:
        ldx     BUFOPEN
        cpx     #$01            ; capture on?
        bne     @show
        jsr     BufStore
        ldx     #$FF
        cpx     BUFFULL         ; buffer became full -> back to BASIC
        beq     BufRts
@show:
        jsr     CHROUT          ; output goes to the screen (default)
; ---- keyboard -> modem
CheckKey:
        jsr     CLRCHN
        jsr     GETIN           ; keyboard
        beq     TermLoop        ; no key
        cmp     #$13            ; HOME -> leave
        beq     Exit
        pha
        ldx     #MODEMLF
        jsr     CHKOUT
        pla
        ldy     CHRMODE
        cpy     #$01
        beq     @send           ; Commodore mode: no translation
        ldy     DUPLEX
        cpy     #$01
        beq     @send           ; half duplex: no translation  ; ? odd, but what the code does
        tax
        lda     ASCTAB,x        ; ? same table as for receive
@send:
        jsr     CHROUT          ; to the modem
        pha
        jsr     CLRCHN
        pla
        ldy     DUPLEX
        cpy     #$00
        beq     @next           ; full duplex: remote echoes
        jsr     CHROUT          ; half duplex: local echo to screen
@next:
        jmp     TermLoop

Exit:
        jsr     CLRCHN
        rts

; -----------------------------------------------------------------------------
; BufStore - $0B81
; Purpose : Append one byte to the capture buffer in bank 1.
; Inputs  : A = byte (0 is not stored); BUFPTR/BUFPTRH = next free address.
; Outputs : byte stored at (BUFPTR) in bank 1, pointer advanced.
;           If BUFPTRH = $FF the byte is dropped and BUFFULL is set to $FF.
; Clobbers: A, X, Y
; Note    : After INDSTA, X holds the previous MMU configuration, which is
;           $00 in BANK 15, so "cpx BUFPTR" tests for the low byte
;           wrapping to $00. ; ? relies on KERNAL STASH internals
;           The same routine is in pc.ml3 ($0E5B).
; -----------------------------------------------------------------------------
BufStore:
        cmp     #$00
        beq     BufRts
        ldx     BUFPTRH
        cpx     #$FF
        beq     BufFull
        ldx     #$01            ; bank 1
        ldy     #BUFPTR         ; pointer lives at $FA
        sty     STAVEC
        ldy     #$00
        jsr     INDSTA
        inc     BUFPTR
        cpx     BUFPTR          ; X = $00 here (see note) ; ?
        beq     @inchi
        rts
@inchi:
        inc     BUFPTRH
BufRts:
        rts

BufFull:
        stx     BUFFULL         ; X = $FF
        rts

        .assert * = $0BA5, error, "pc.ml2 size changed"
