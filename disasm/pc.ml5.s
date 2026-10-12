; =============================================================================
; pc.ml5.s - PC-Term 128, module PC.ML5: VDC register write / print string
; =============================================================================
; Original file : pc.ml5 (C128 PRG, load address $1600, 122 bytes of code)
; Assembler     : ca65/ld65 (cc65 2.19). Rebuild and compare with
;                 disasm/verify.sh
; Loaded by     : no BLOAD of "pc.ml5" was found in pcterm, pcboot, pcset or
;                 the other ML files of this repository. ; ?
;                 Note that pc.ml4 also uses $1600-$16D0 (its drive code
;                 image), so the two modules cannot be in memory together.
; Called by     : pcterm line 8000
;                   BANK15:ad=2000+y*80+x:POKE250,(adAND255):POKE251,(ad/256)
;                   :a=(t$):SYSDEC("1627"),aAND255,a/256:RETURN
;                 "a=(t$)" is probably a=POINTER(t$) with the keyword lost
;                 by the detokenizer. ; ?
;
; Entry points:
;   $1600 VdcWrite  - write A to VDC register X
;   $160C VdcReset  - clear VDC update address and write $00 (no caller found)
;   $1627 PrintAt   - put a BASIC string on the screen without moving
;                     the cursor (SYS from line 8000)
; =============================================================================

        .setcpu "6502"

; ---- C128 hardware ----------------------------------------------------------
VDCADR  := $D600                ; 8563 VDC address/status register
VDCDAT  := $D601                ; 8563 VDC data register

; ---- C128 ROM ---------------------------------------------------------------
EDPRINT := $C00C                ; screen editor jump table: PRINT char in A ; ?
INDFET  := $FF74                ; A = zp pointer address, X = bank, Y = index

; ---- C128 zero page ---------------------------------------------------------
SCRADR  := $FA                  ; screen address lo (set by BASIC, POKE250)
SCRADRH := $FB                  ; screen address hi (set by BASIC, POKE251)
STRPTR  := $FC                  ; string pointer lo (program use)
STRPTRH := $FD                  ; string pointer hi (program use)
STRLEN  := $FE                  ; characters left (program use)
PNT     := $E0                  ; editor: address of current screen line (2 bytes)
PNTR    := $EC                  ; editor: cursor column

VDC_UPDHI = 18                  ; VDC register: update address hi
VDC_UPDLO = 19                  ; VDC register: update address lo
VDC_DATA  = 31                  ; VDC register: data read/write

        .word   $1600           ; PRG load address
        .org    $1600

; -----------------------------------------------------------------------------
; VdcWrite - $1600
; Purpose : Write one VDC (8563) register.
; Inputs  : X = register number, A = value.
; Outputs : register written. A, X kept.
; -----------------------------------------------------------------------------
VdcWrite:
        stx     VDCADR
@wait:  bit     VDCADR          ; wait for status bit 7 (ready)
        bpl     @wait
        sta     VDCDAT
        rts

; -----------------------------------------------------------------------------
; VdcReset - $160C (no BASIC caller found)
; Purpose : Set the VDC update address to $0000, write one $00 byte
;           through the data register (VDC RAM $0000 = 0), then set the
;           update address high byte to $00 again. ; ? exact purpose unknown
; Inputs  : none.   Outputs: VDC registers 18, 19, 31 written.
; -----------------------------------------------------------------------------
VdcReset:
        ldx     #VDC_UPDHI
        lda     #$00
        jsr     VdcWrite
        inx                     ; register 19
        lda     #$00
        jsr     VdcWrite
        ldx     #VDC_DATA
        lda     #$00
        jsr     VdcWrite
        ldx     #VDC_UPDHI
        lda     #$00
        jmp     VdcWrite

; -----------------------------------------------------------------------------
; PrintAt - $1627 (SYSDEC("1627"),lo,hi from pcterm line 8000)
; Purpose : Put the text of a BASIC string on the screen at a fixed
;           screen address, without moving the cursor. Characters are
;           written last to first; for each one the editor line pointer
;           (PNT) and column (PNTR) are set, then the editor print
;           routine is called.
; Inputs  : A = low byte, X = high byte of the string descriptor address
;           in bank 1 (descriptor = length, address lo, address hi).
;           SCRADR/SCRADRH ($FA/$FB) = screen address of the first
;           character (BASIC: ad=2000+y*80+x). ; ? why the 2000 offset
; Outputs : string displayed. $FA-$FE, PNT and PNTR are changed.
; Note    : An empty string (length 0) would print 256 characters. ; ?
; -----------------------------------------------------------------------------
PrintAt:
        sta     STRPTR          ; STRPTR -> descriptor
        stx     STRPTRH
        ldy     #$00
        ldx     #$01            ; bank 1 (BASIC variables)
        lda     #STRPTR
        jsr     INDFET
        sta     STRLEN          ; descriptor+0 = length
        ldy     #$01
        ldx     #$01
        lda     #STRPTR
        jsr     INDFET
        pha                     ; descriptor+1 = data address lo
        iny
        ldx     #$01
        lda     #STRPTR
        jsr     INDFET
        sta     STRPTRH         ; descriptor+2 = data address hi
        pla
        sta     STRPTR
; STRPTR = STRPTR - 1, so that index 1..len addresses the characters
        lda     STRPTR
        bne     @declo1
        dec     STRPTRH
@declo1:
        dec     STRPTR
; SCRADR = SCRADR - 1, so that PNTR = 1..len gives the right column
        lda     SCRADR
        bne     @declo2
        dec     SCRADRH
@declo2:
        dec     SCRADR
@loop:
        lda     SCRADR          ; PNT = screen address - 1
        sta     PNT
        lda     SCRADRH
        sta     PNT+1
        ldx     #$01
        ldy     STRLEN
        lda     #STRPTR
        jsr     INDFET          ; A = character number STRLEN
        ldy     STRLEN
        sty     PNTR            ; column = index
        jsr     EDPRINT
        dec     STRLEN
        bne     @loop
        rts

        .assert * = $167A, error, "pc.ml5 size changed"
