; =============================================================================
; pc.ml3.s - PC-Term 128, module PC.ML3: file <-> screen / capture buffer
; =============================================================================
; Original file : pc.ml3 (C128 PRG, load address $0E00, 200 bytes of code)
; Assembler     : ca65/ld65 (cc65 2.19). Rebuild and compare with
;                 disasm/verify.sh
; Loaded by     : pcterm line 728  BLOAD"pc.ml3",p3584,b0
;                 (line 728 checks PEEK(3584)=76, the first JMP opcode)
;
; Entry points (all use logical file 1, opened by BASIC before the SYS):
;   $0E00 SYS3584 ShowFile    - type a file on the screen      (line 4510)
;   $0E03 SYS3587 LoadBuffer  - read a file into capture buffer (3935, 4845)
;   $0E29 (none)  ClearLoad   - reset buffer, then LoadBuffer  (no caller found)
;   $0E7B SYS3707 SendBuffer  - write capture buffer to file 1 (3780, 3785, 4860)
;
; Capture buffer: bank 1 RAM from $8000, end pointer (next free byte) in
; zero page $FA/$FB; $0BFE (3070) = $FF when full. These are shared with
; pc.ml2 (see pc.ml2.s).
; =============================================================================

        .setcpu "6502"

; ---- C128 KERNAL jump table -------------------------------------------------
INDFET  := $FF74                ; A = zp pointer address, X = bank, Y = index
INDSTA  := $FF77                ; store A to (STAVEC),Y in bank X
READST  := $FFB7                ; read I/O status byte
CHKIN   := $FFC6                ; open channel for input (X = logical file)
CHKOUT  := $FFC9                ; open channel for output (X = logical file)
CLRCHN  := $FFCC                ; restore default I/O (keyboard/screen)
CHROUT  := $FFD2                ; output character in A
GETIN   := $FFE4                ; get character from input channel

; ---- C128 zero page / system RAM --------------------------------------------
BUFPTR  := $FA                  ; capture buffer end pointer lo (program use)
BUFPTRH := $FB                  ; capture buffer end pointer hi (program use)
RDPTR   := $FC                  ; SendBuffer read pointer lo (program use)
RDPTRH  := $FD                  ; SendBuffer read pointer hi (program use)
STAVEC  := $02B9                ; INDSTA: zero-page address of the pointer

; ---- program data -----------------------------------------------------------
BUFFULL := $0BFE                ; $FF = capture buffer full (from pc.ml2 page)

FILELF  = 1                     ; logical file used by all entry points
KEY_ESC = $1B                   ; ESC key aborts every routine

        .word   $0E00           ; PRG load address
        .org    $0E00

; ---- jump table -------------------------------------------------------------
        jmp     ShowFile        ; $0E00 SYS3584
        jmp     LoadBuffer      ; $0E03 SYS3587

; -----------------------------------------------------------------------------
; ShowFile - $0E06 (SYS3584)
; Purpose : Copy file 1 to the screen until end of file / error or ESC.
; Inputs  : logical file 1 open for read (pcterm 4505 OPEN1,dv,2,en$).
; Outputs : characters printed to the screen.
; BASIC   : line 4510 BANK15:SYS3584:BANK15:DCLOSE#1:DCLEAR ("File to Read")
; Note    : READST is tested after GETIN, so the last byte of the file
;           (the one that sets EOF status) is not printed. ; ?
; -----------------------------------------------------------------------------
ShowFile:
        ldx     #FILELF
        jsr     CHKIN
        jsr     GETIN
        pha
        jsr     READST
        bne     @eof            ; EOF or error -> stop
        pla
        pha
        jsr     CLRCHN
        pla
        jsr     CHROUT          ; to screen
        jsr     GETIN           ; keyboard
        cmp     #KEY_ESC
        beq     @done
        jmp     ShowFile
@eof:
        pla
@done:
        rts

; -----------------------------------------------------------------------------
; ClearLoad - $0E29 (no BASIC caller found)
; Purpose : Set the capture buffer pointer to $8000 (empty buffer), then
;           fall through into LoadBuffer.
; Inputs  : as LoadBuffer.   Outputs: as LoadBuffer.
; -----------------------------------------------------------------------------
ClearLoad:
        lda     #$00
        sta     BUFPTR
        lda     #$80
        sta     BUFPTRH

; -----------------------------------------------------------------------------
; LoadBuffer - $0E31 (SYS3587)
; Purpose : Append the contents of file 1 to the capture buffer (bank 1).
; Inputs  : logical file 1 open for read; BUFPTR/BUFPTRH = next free byte.
; Outputs : bytes stored, BUFPTR advanced. Stops on EOF/error, on ESC,
;           or when the buffer is full (BUFFULL = $FF).
; BASIC   : line 3935 "[ Loading f$ ]" ... BANK15:SYS3587:DCLOSE#1
;           line 4845 BANK15:SYS3587:DCLOSE#1:DCLEAR (after OPEN1,8,2,f$,r)
; Note    : As in ShowFile, the byte read together with EOF is not stored. ; ?
; -----------------------------------------------------------------------------
LoadBuffer:
        ldx     #FILELF
        jsr     CHKIN
        jsr     GETIN
        pha
        jsr     READST
        bne     @eof
        pla
        pha
        jsr     CLRCHN
        pla
        jsr     BufStore
        lda     BUFFULL
        cmp     #$FF
        beq     @done
        jsr     GETIN           ; keyboard
        cmp     #KEY_ESC
        beq     @done
        jmp     LoadBuffer
@eof:
        pla
@done:
        rts

; -----------------------------------------------------------------------------
; BufStore - $0E5B
; Purpose : Append A to the capture buffer in bank 1 (copy of pc.ml2
;           BufStore, but without the "skip $00" test).
; Inputs  : A = byte; BUFPTR/BUFPTRH = next free address.
; Outputs : byte stored and pointer advanced, or BUFFULL = $FF if the
;           pointer high byte is $FF.
; Clobbers: A, X, Y
; Note    : X after INDSTA = previous MMU config ($00 in BANK 15), so the
;           "cpx BUFPTR" tests for a wrap of the low byte. ; ?
; -----------------------------------------------------------------------------
BufStore:
        ldx     BUFPTRH
        cpx     #$FF
        beq     @full
        ldx     #$01            ; bank 1
        ldy     #BUFPTR
        sty     STAVEC
        ldy     #$00
        jsr     INDSTA
        inc     BUFPTR
        cpx     BUFPTR          ; ? X = $00 here
        beq     @inchi
        rts
@inchi:
        inc     BUFPTRH
        rts
@full:
        stx     BUFFULL         ; X = $FF
        rts

; -----------------------------------------------------------------------------
; SendBuffer - $0E7B (SYS3707)
; Purpose : Write the capture buffer ($8000 up to the end pointer) to
;           logical file 1 (printer, screen or disk file).
; Inputs  : logical file 1 open for write; BUFPTR/BUFPTRH = end pointer.
; Outputs : bytes sent to file 1. ESC stops early.
; BASIC   : line 3780 OPEN1,pr%,7:SYS3707 (printer)
;           line 3785 OPEN1,3:SYS3707      (screen)
;           line 4860 BANK15:SYS3707:DCLOSE#1 (save buffer to disk)
; Note    : The end test is RDPTR = BUFPTR+1, so the byte AT the end
;           pointer (one past the last stored byte) is also sent. ; ?
;           If BUFPTR = $FF the low-byte test (BUFPTR+1 = $00) can never
;           match while RDPTRH = BUFPTRH. ; ? possible overrun
; -----------------------------------------------------------------------------
SendBuffer:
        lda     #$00
        sta     RDPTR
        lda     #$80
        sta     RDPTRH          ; read pointer = $8000
        ldx     #$00            ; (these three loads have no effect)
        ldy     #$00
        lda     #$00
SendLoop:
        lda     #RDPTR          ; fetch (RDPTR),0 from bank 1
        ldx     #$01
        ldy     #$00
        jsr     INDFET
        pha
        ldx     #FILELF
        jsr     CHKOUT
        pla
        jsr     CHROUT
        jsr     CLRCHN
        jsr     GETIN           ; keyboard
        cmp     #KEY_ESC
        beq     SendDone
        inc     RDPTR
        lda     RDPTR
        cmp     #$00
        bne     @chk
        jsr     IncRdHi
@chk:
        lda     RDPTRH
        cmp     BUFPTRH
        beq     CheckEnd
        jmp     SendLoop

; IncRdHi - $0EBA: increment read pointer high byte (subroutine of SendBuffer)
IncRdHi:
        inc     RDPTRH
        rts

; CheckEnd - $0EBD: same page as the end pointer; stop when RDPTR = BUFPTR+1
CheckEnd:
        ldx     BUFPTR
        inx
        cpx     RDPTR
        beq     SendDone
        jmp     SendLoop

SendDone:
        rts

        .assert * = $0EC8, error, "pc.ml3 size changed"
