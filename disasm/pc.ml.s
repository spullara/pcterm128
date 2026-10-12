
; =============================================================================
; pc.ml  --  PC-Term 128 main machine-language module
; -----------------------------------------------------------------------------
; Target   : Commodore 128 (8502 CPU), 80-column (VDC) mode, bank 0
; File     : PRG, load address $2000, 5872 bytes ($2000-$36EF)
; Loaded by: BASIC line 715  BLOAD"pc.ml",B0,U(dv%(dv))
;            (only if PEEK(9000)<>6; 9000 = $2328 is the operand byte of the
;             LDY #CODE_ACK at $2327, so PEEK(9000)=6 means "pc.ml in memory")
; Syntax   : ca65 / ld65 (cc65 suite).  Build and check:
;              ca65 pc.ml.s -o pc.ml.o
;              ld65 -t none pc.ml.o -o pc.ml.bin
;              cmp pc.ml.bin ../pc.ml
;            (or: sh disasm/verify.sh pc.ml.s)
;
; Contents (see the routine headers for details):
;   $2000-$2035  variables (Punter state, terminal state)
;   $2036-$2092  three 31-byte macro slots (C= 1 / C= 2 / C= 3 keys)
;   $2093-$20A1  jump table A: terminal / buffer routines
;   $20A2-$20BC  Punter entry points (A = function number), misc vectors
;   $20BD-$20F4  Punter dispatcher, dispatch table, XMODEM vectors
;   $20F5-$2120  variables (XMODEM state, VDC buffer editor state)
;   $2121-$2126  jump table B: buffer editor / load-to-buffer
;   $2127-$2135  Punter handshake codes "GOO","BAD","ACK","S/B","SYN"
;   $2136-$2680  Punter (C1) protocol: receive file, send file, file type
;   $268F-$2772  "chat" ASCII terminal (Punter function $0F)
;   $2773-$2814  CHROUT (IBSOUT) hook with own RS-232 transmit start
;   $2815-$2B71  simple terminal with capture buffer, buffer send/print,
;                directory-to-A$ reader, file view, load file to buffer
;   $2BAB-$2F45  XMODEM (checksum, 128-byte blocks) send and receive
;   $2F46-$36EE  VDC full-screen capture buffer viewer / editor
;   $36EF        1 pad byte ($1A)
;
; Memory used outside the module:
;   bank 1 $0400-$DFFF : capture buffer (read/written via FETCH/STASH, MMU
;                        config $7F)
;   bank 0 $0450-$04D4 : XMODEM block buffer (40-column screen RAM, unused
;                        in 80-column mode)
;   bank 0 $0500-$06FF : two 256-byte Punter block buffers (40-col screen RAM)
;   $0200              : result byte returned to BASIC (PEEK(512))
;   zero page $64,$66/$67,$72/$73,$96,$FA-$FE (see symbol list)
;
; Conventions:  "; ?" marks a comment that is a guess and is not verified.
; =============================================================================

.setcpu "6502"

; --- Constants ---------------------------------------------------------------
MMU_BANK1       = $7F           ; MMU config value: RAM bank 1, no ROM, no I/O
LFN_MODEM       = 5             ; BASIC: OPEN5,2,0,... (RS-232 user port)
LFN_FILE        = 2             ; BASIC: OPEN2,dv,... (disk file / directory)
CAP_START       = $0400         ; capture buffer start (bank 1)
CAP_LIMIT       = $E000         ; capture buffer limit (bank 1)

; Punter code offsets into pn_codes (3 ASCII chars each)
CODE_GOO        = 0
CODE_BAD        = 3
CODE_ACK        = 6
CODE_SB         = 9
CODE_SYN        = 12
; Punter "accept" masks for pn_wait_code (bit n = code n/3)
M_GOO           = $01
M_BAD           = $02
M_ACK           = $04
M_SB            = $08
M_SYN           = $10

; XMODEM control bytes
XM_SOH          = $01
XM_EOT          = $04
XM_ACK          = $06
XM_NAK          = $15
XM_CAN          = $18

; C128 keyboard matrix codes as found in LSTX ($D4) / SFDX ($D5)
KEY_DEL         = $00
KEY_RETURN      = $01
KEY_F7          = $03
KEY_F1          = $04
KEY_F3          = $05
KEY_F5          = $06
KEY_SPACE       = $3C
KEY_STOP        = $3F
KEY_ESC         = $48
KEY_UP          = $53
KEY_DOWN        = $54
KEY_LEFT        = $55
KEY_RIGHT       = $56

; --- Zero page (C128). zp_* = locations reused as scratch by this module ---
zp_temp         = $64
zp_bufptr       = $66
zp_capptr       = $72
zp_status       = $96
DFLTO           = $9A
PTR1            = $9E
BUFPT           = $A6
TAPE1           = $B2
FA              = $BA
RIBUF           = $C8
ROBUF           = $CA
LSTX            = $D4
SFDX            = $D5
zp_fa           = $FA
zp_fb           = $FB
zp_fc           = $FC
zp_fd           = $FD
zp_fe           = $FE

; --- C128 system RAM (BUF=BASIC input buffer, FETCH/STASH=RAM bank routines, RS-232 buffer indexes) ---
BUF             = $0200
FETCH           = $02A2
FETVEC          = $02AA
STASH           = $02AF
STAVEC          = $02B9
IBSOUT          = $0326
ENABL           = $0A0F
RIDBE           = $0A18
RIDBS           = $0A19
RODBS           = $0A1A
RODBE           = $0A1B

; --- Work buffers in 40-column screen RAM (unused in 80-column mode) ---
XM_BUF          = $044F
PUNT_BUF0       = $0500

; --- I/O: VDC (8563) and CIA2 timer A (RS-232 baud timer) ---
VDC_ADDR        = $D600
VDC_DATA        = $D601
CIA2_TALO       = $DD04
CIA2_TAHI       = $DD05
CIA2_CRA        = $DD0E

; --- C128 KERNAL internal routines  ; ? addresses from the code, names by analogy with the C64 KERNAL ---
K_RSTRAB        = $E64A
K_ORIOEN        = $E67F
K_E6C2          = $E6C2
K_JTP20         = $E9BE
K_WBLK          = $EA15

; --- KERNAL jump table ---
PRIMM           = $FF7D
READST          = $FFB7
CHKIN           = $FFC6
CHKOUT          = $FFC9
CLRCHN          = $FFCC
CHRIN           = $FFCF
CHROUT          = $FFD2
SETTIM          = $FFDB
RDTIM           = $FFDE
GETIN           = $FFE4

; --- Outside this file  ; ? jump target of the default macro slots (not in pc.ml) ---
MACRO_EXIT      = $3743


; -----------------------------------------------------------------------------
; PRG load address (first two bytes of the file), then the image at $2000
; -----------------------------------------------------------------------------
                .word   $2000
                .org    $2000


; =============================================================================
; Variables $2000-$2035
; =============================================================================
echo_cnt_mid:   .byte   $00                 ; send_buffer echo wait: poll counter, middle byte
echo_sent:      .byte   $00                 ; send_buffer echo wait: sent char AND $5F
echo_cnt_lo:    .byte   $00                 ; send_buffer echo wait: poll counter, low byte
echo_got:       .byte   $00                 ; send_buffer echo wait: received char
pn_window:      .byte   $00,$00,$00         ; Punter: last 3 received bytes (sliding window)
pn_bit:         .byte   $00                 ; Punter: current mask bit while matching codes
pn_code_idx:    .byte   $00                 ; Punter: offset of matched code (0,3,6,9,12)
pn_mask:        .byte   $00                 ; Punter: mask of codes accepted by pn_wait_code
pn_timer:       .byte   $00,$00             ; Punter: 16-bit idle/timeout counter (lo,hi)
pn_send_code:   .byte   $00                 ; Punter: code sent by pn_recv_block (GOO/BAD)
pn_count:       .byte   $00                 ; Punter: byte count / retry count (scratch)
pn_sender:      .byte   $00                 ; Punter: 1 = we are the sender, 0 = receiver
pn_tmo_count:   .byte   $00                 ; Punter: number of timeouts (mod 3)
pn_last:        .byte   $00                 ; Punter: last-block / transfer-done flag
pn_rx_sum:      .byte   $00,$00,$00,$00     ; Punter: received 4-byte checksum (copy)
pn_sum:         .byte   $00,$00,$00,$00     ; Punter: computed checksum: add lo,hi, cyclic lo,hi
pn_bufsel:      .byte   $00                 ; Punter: current buffer, 0 = $0500, 1 = $0600
pn_next_size:   .byte   $00                 ; Punter: size of the block being received
pn_blksize:     .byte   $00                 ; Punter: block size for sending.  BASIC: POKE DEC("201b"),bs
pn_blknum:      .byte   $00,$00             ; Punter: 16-bit block number (lo,hi)
pn_ftype:       .byte   $00                 ; Punter: file type (1=PRG 2=SEQ 3=USR ?).  BASIC POKE/PEEK DEC("201e")
pn_saved_sp:    .byte   $00                 ; stack pointer saved by pn_dispatch (ESC abort)
pn_quiet:       .byte   $00                 ; Punter: 1 = do not print progress characters
pn_send_goo:    .byte   $00                 ; Punter: 1 = send GOO before waiting (file type send)
unused_2022:    .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; not referenced by code  ; ?
baud_timer:     .byte   $00,$00             ; RS-232 baud timer for CIA2 TA.  BASIC line 1905 POKE
old_ibsout:     .byte   $00,$00             ; previous IBSOUT vector (set by install_hook)
cap_end:        .byte   $00,$04             ; capture buffer end pointer, bank 1 (default $0400)
term_exit:      .byte   $00                 ; terminal exit code: 0=ESC 1-8=F1-F8 9=TAB $FF=full
term_echo:      .byte   $00                 ; terminal: <>0 = local echo of typed keys
cap_off:        .byte   $01                 ; terminal: <>0 = capture off (default 1)
bs_char:        .byte   $00                 ; send_buffer: current character
bs_mode:        .byte   $00                 ; send_buffer mode: 1=screen+file 2=send 3=file only
bs_noecho:      .byte   $00                 ; send_buffer: <>0 = do not wait for echo in mode 2

; =============================================================================
; Macro slots 1-3 ($2036, $2055, $2074), 31 bytes each
; -----------------------------------------------------------------------------
; Purpose : text macros sent to the modem from the terminal (C= 1, C= 2, C= 3
;           keys; PETSCII $81/$95/$96).  The terminal has CHKOUT LFN_MODEM
;           active, so PRIMM sends the text to the modem.
; Format  : JSR PRIMM / text / $00 / JMP back.  The default text is one CR.
;           The default JMP goes to $3743, which is outside pc.ml (; ? the
;           slots are probably rewritten at run time; no writer found in the
;           BASIC program or in pc.ml).
; =============================================================================
macro1:         jsr     PRIMM               ; macro 1 (C= 1)
macro1_text:    .byte   $0D,$00             ; text: CR, end
macro1_jmp:     jmp     MACRO_EXIT          ; ?  target outside pc.ml
macro1_free:    .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; free space for longer macro text
                .byte   $00,$00,$00,$00,$00,$00,$00,$00
                .byte   $00,$00,$00,$00,$00,$00,$00
macro2:         jsr     PRIMM               ; macro 2 (C= 2)
macro2_text:    .byte   $0D,$00             ; text: CR, end
macro2_jmp:     jmp     MACRO_EXIT          ; ?  target outside pc.ml
macro2_free:    .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; free space for longer macro text
                .byte   $00,$00,$00,$00,$00,$00,$00,$00
                .byte   $00,$00,$00,$00,$00,$00,$00
macro3:         jsr     PRIMM               ; macro 3 (C= 3)
macro3_text:    .byte   $0D,$00             ; text: CR, end
macro3_jmp:     jmp     MACRO_EXIT          ; ?  target outside pc.ml
macro3_free:    .byte   $00,$00,$00,$00,$00,$00,$00,$00 ; free space for longer macro text
                .byte   $00,$00,$00,$00,$00,$00,$00,$00
                .byte   $00,$00,$00,$00,$00,$00,$00

; =============================================================================
; Jump table A ($2093-$20A1)
; -----------------------------------------------------------------------------
; No SYS to these addresses was found in pcterm.source.  ; ? possibly older
; entry points, or used by another module.
; =============================================================================
jt_terminal:    jmp     terminal            ; $2093 dumb terminal with capture buffer
jt_type_file:   jmp     type_file           ; $2096 print file #2 to the screen
jt_send_buffer: jmp     send_buffer         ; $2099 output capture buffer (mode bs_mode)
jt_load_buffer: jmp     load_buffer         ; $209C append file #2 to capture buffer
jt_read_dir:    jmp     read_dir            ; $209F BASIC: SYSDEC("209f") read dir entry

; =============================================================================
; Punter entry points ($20A2-$20B6)
; -----------------------------------------------------------------------------
; Each entry loads A with a function number (a multiple of 3) and falls
; through to pn_dispatch.  The $2C bytes are BIT abs opcodes that skip the
; next LDA #.
;   $20A2  A=$00  pn_wait_code   (no BASIC caller)
;   $20A5  A=$03  receive file   BASIC: SYSDEC("20a5") lines 2050, 2214
;   $20A8  A=$06  send file      BASIC: SYSDEC("20a8") lines 2024, 2176
;   $20AB  A=$09  receive type   BASIC: SYSDEC("20ab") lines 2046, 2212
;   $20AE  A=$0C  send type      BASIC: SYSDEC("20ae") lines 2022, 2172
;   $20B1  A=$0F  chat terminal  (no BASIC caller)
; Return  : BUF ($0200) = 1 if the user pressed ESC, else 0 (BASIC tests
;           PEEK(512)=1).  pn_ftype ($201E) holds the file type.
; =============================================================================
pn_fn_wait:     lda     #$00                ; function $00
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_fn_recv_file:
                lda     #$03                ; function $03 receive file
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_fn_send_file:
                lda     #$06                ; function $06 send file
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_fn_recv_type:
                lda     #$09                ; function $09 receive file type
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_fn_send_type:
                lda     #$0C                ; function $0C send file type
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_fn_chat:     lda     #$0F                ; function $0F chat terminal
                nop
pn_fn_go:       jmp     pn_dispatch

; -----------------------------------------------------------------------------
; $20B7  BASIC: SYSDEC("20b7") before each Punter call - wait until the
;        RS-232 transmitter is idle.
; $20BA  BASIC: SYSDEC("20ba") line 40 - install the CHROUT hook.
; -----------------------------------------------------------------------------
jt_wait_tx:     jmp     rs_wait_tx
jt_install_hook:
                jmp     install_hook

; =============================================================================
; pn_dispatch ($20BD)
; -----------------------------------------------------------------------------
; Purpose : save SP for the ESC abort (check_esc), then jump to
;           pn_dispatch_tab + A by self-modifying the JMP at $20D2.
; Input   : A = function number 0,3,6,...  Output: see the called routine.
; =============================================================================
pn_dispatch:    sta     zp_temp
                tsx                         ; SP at entry: check_esc unwinds to this level
                stx     pn_saved_sp
                lda     #<pn_dispatch_tab
                clc
                adc     zp_temp
                sta     pn_dispatch_jmp+1
                lda     #>pn_dispatch_tab
                adc     #$00
                sta     pn_dispatch_jmp+2
pn_dispatch_jmp:
                jmp     pn_dispatch_tab     ; operand is patched above
pn_dispatch_tab:
                jmp     pn_wait_code        ; A=$00
                jmp     pn_recv_file        ; A=$03
                jmp     pn_send_file        ; A=$06
                jmp     pn_recv_type        ; A=$09
                jmp     pn_send_type        ; A=$0C
                jmp     chat                ; A=$0F
                jmp     install_hook        ; A=$12  (no entry point uses this)
                jmp     term_loop_j         ; A=$15  (no entry point uses this)

; =============================================================================
; XMODEM entry points
; -----------------------------------------------------------------------------
; $20ED  BASIC: xc=8429 ($20ED), SYS xc     line 2224  XMODEM send (upload)
; $20F1  BASIC: SYS xc+4                    line 2264  XMODEM receive
; Status: xm_status = xc+8 ($20F5), BASIC PEEK(xc+8) / mg=xc+8:
;         0 = OK (EOT), 1 = sync lost, 2 = (preset by BASIC, "Aborted"),
;         3 = cancelled (CAN or ESC), 4 = more than 10 tries for a block.
; =============================================================================
xm_send_entry:  nop
                jmp     xm_send
xm_recv_entry:  nop
                jmp     xm_recv

; =============================================================================
; Variables $20F5-$2120
; =============================================================================
xm_status:      .byte   $00                 ; XMODEM result (xc+8), see above
xm_index:       .byte   $00                 ; XMODEM: send index / receive junk-byte count
xm_block:       .byte   $08                 ; XMODEM: block number expected or sent
xm_sum:         .byte   $11                 ; XMODEM: checksum accumulator
xm_retry:       .byte   $00                 ; XMODEM: retry count (max 10)
xm_good_char:   .byte   $2D                 ; '-' printed for a good block
xm_bad_char:    .byte   $3A                 ; ':' printed for a bad block / NAK
xm_pos:         .byte   $00                 ; XMODEM: index into XM_BUF while filling
xm_char:        .byte   $00                 ; XMODEM: last byte read from the file
xm_saved_sp:    .byte   $00                 ; XMODEM: SP saved for ESC abort
vdc_wr_addr:    .byte   $00,$00             ; vdc_poke: VDC RAM address lo,hi
vdc_wr_data:    .byte   $00                 ; vdc_poke: byte to write (screen code or attribute)
ed_vaddr:       .byte   $00,$00             ; editor: VDC address lo,hi (screen or attribute RAM)
ed_delay:       .byte   $00,$00             ; editor: key delay counters lo,hi
unused_2106:    .byte   $00,$00             ; not referenced by code  ; ?
ed_char:        .byte   $00                 ; editor: current buffer character
ed_mode:        .byte   $00                 ; editor output mode, 0=view 1=+file 2=+conv 3=file  ; ?
ld_raw:         .byte   $00                 ; load_conv: 0 = convert ASCII to PETSCII, else raw
ld_char:        .byte   $00                 ; load_conv: byte read
ed_next_page:   .byte   $00,$00             ; editor: buffer address after the last shown char
ed_top:         .byte   $00,$00             ; editor: buffer address of the first char on screen
unused_2110:    .byte   $00                 ; not referenced by code  ; ?
ed_curbuf:      .byte   $00,$00             ; editor: buffer address of cursor + $08F0
ed_cursor_hi:   .byte   $00                 ; editor: saved cursor attribute address, high byte
ed_cursor_lo:   .byte   $00                 ; editor: saved cursor attribute address, low byte
ed_tmp1:        .byte   $00,$00             ; editor: scratch
ed_tmp2:        .byte   $00,$00             ; editor: scratch
ed_tmp3:        .byte   $00,$00             ; editor: scratch
ed_tmp4:        .byte   $00                 ; editor: scratch
unused_211C:    .byte   $00                 ; not referenced by code  ; ?
ed_mark_top:    .byte   $00,$00             ; editor: ed_top when the block mark was set
ed_mark:        .byte   $00,$00             ; editor: block mark, buffer address + $08F0

; =============================================================================
; Jump table B ($2121-$2126).  No BASIC caller found.  ; ?
; =============================================================================
jt_editor:      jmp     editor              ; $2121 capture buffer viewer/editor (VDC)
jt_load_conv:   jmp     load_conv           ; $2124 append file #2 to buffer, ASCII->PETSCII

; =============================================================================
; Punter handshake codes, 3 ASCII bytes each (offsets CODE_GOO ... CODE_SYN)
; =============================================================================
pn_codes:       .byte   "GOOBADACKS/BSYN"

; =============================================================================
; pn_wait_code ($2136)   Punter function $00
; -----------------------------------------------------------------------------
; Purpose : read the modem until one of the accepted 3-byte codes arrives,
;           followed by a short quiet time; or time out.
; Input   : A = mask of accepted codes (M_GOO, M_BAD, M_ACK, M_SB, M_SYN)
; Output  : zp_status = 0 code received (pn_code_idx = its offset),
;                       1 time-out (after pn_timeout)
;           ESC aborts back to BASIC (check_esc).
; =============================================================================
pn_wait_code:   sta     pn_mask
                lda     #$00
                sta     pn_window
                sta     pn_window+1
                sta     pn_window+2
pn_wait_reset:  lda     #$00
                sta     pn_timer
                sta     pn_timer+1
pn_wait_loop:   jsr     check_esc
                jsr     rs_get
                lda     zp_status           ; 0 = byte received
                bne     pn_wait_none
                lda     pn_window+1         ; shift the byte into the 3-byte window
                sta     pn_window
                lda     pn_window+2
                sta     pn_window+1
                lda     BUF
                sta     pn_window+2
                lda     #$00
                sta     pn_code_idx
                lda     #$01
                sta     pn_bit
pn_wait_try:    lda     pn_mask             ; is this code accepted?
                bit     pn_bit
                beq     pn_wait_next
                ldy     pn_code_idx
                ldx     #$00
pn_wait_cmp:    lda     pn_window,x
                cmp     pn_codes,y
                bne     pn_wait_next
                iny
                inx
                cpx     #$03
                bne     pn_wait_cmp
                jmp     pn_wait_hit
pn_wait_next:   asl     pn_bit
                lda     pn_code_idx
                clc
                adc     #$03
                sta     pn_code_idx
                cmp     #$0F
                bne     pn_wait_try
                jmp     pn_wait_reset
pn_wait_hit:    lda     #$FF                ; match: counter = $FFFF, so the next idle
                sta     pn_timer            ; poll makes it 0 = success
                sta     pn_timer+1
                jmp     pn_wait_loop
pn_wait_none:   inc     pn_timer
                bne     pn_wait_chk
                inc     pn_timer+1
pn_wait_chk:    lda     pn_timer+1
                ora     pn_timer
                beq     pn_wait_ok
                lda     pn_timer            ; no effect (result overwritten)
                cmp     #$07
                lda     pn_timer+1          ; time-out when counter hi >= $30
                cmp     #$30
                bcc     pn_wait_loop
                lda     #$01
                sta     zp_status
                jmp     pn_timeout
pn_wait_ok:     lda     #$00
                sta     zp_status
                rts

; =============================================================================
; rs_get ($21D7)  (rs_get_nop at $21D6 is a NOP in front of it)
; -----------------------------------------------------------------------------
; Purpose : take one byte from the KERNAL RS-232 input buffer, no wait.
; Output  : BUF = byte (0 if none), zp_status = 0 got byte / 2 empty,
;           FA = 3, Y preserved, A destroyed.
; =============================================================================
rs_get_nop:     nop
rs_get:         tya
                pha
                lda     RIDBE               ; write index (NMI) = read index ?
                cmp     RIDBS
                beq     rs_get_empty
                ldy     RIDBS
                lda     (RIBUF),y
                pha
                inc     RIDBS
                lda     #$00
                sta     zp_status
                pla
                sta     BUF
                pla
                tay
                jmp     rs_get_exit
rs_get_empty:   lda     #$02
                sta     zp_status
                lda     #$00
                sta     BUF
                pla
                tay
rs_get_exit:    pha
                lda     #$03                ; FA = 3 (screen)  ; ? purpose unknown
                sta     FA
                pla
                rts

; =============================================================================
; pn_send_code_y ($2209)
; -----------------------------------------------------------------------------
; Purpose : send one Punter code to the modem.
; Input   : Y = code offset (CODE_GOO ... CODE_SYN).   Output: channels cleared.
; =============================================================================
pn_send_code_y: ldx     #LFN_MODEM
                jsr     CHKOUT
                ldx     #$00
pn_send_code_lp:
                lda     pn_codes,y
                jsr     CHROUT
                iny
                inx
                cpx     #$03
                bne     pn_send_code_lp
                jmp     CLRCHN

; =============================================================================
; pn_recv_block ($221F)
; -----------------------------------------------------------------------------
; Purpose : receiver side of one Punter block exchange:
;           send GOO/BAD, wait for ACK, send S/B, receive the block into
;           PUNT_BUF0 ($0500).  After the last block it does the end
;           handshake (SYN / S/B) instead.
; Input   : A = CODE_GOO (last block good) or CODE_BAD (ask for resend)
;           PUNT_BUF0+4 = size of the block that is expected now
; Output  : pn_count = pn_next_size = expected size; zp_status from
;           pn_recv_bytes (1 = full block)
; =============================================================================
pn_recv_block:  sta     pn_send_code
                lda     #$00
                sta     pn_sender
pn_rb_send:     lda     #$02                ; 2 waits for ACK per code sent
                sta     zp_temp
                ldy     pn_send_code
                jsr     pn_send_code_y
pn_rb_ack:      lda     #M_ACK
                jsr     pn_wait_code
                lda     zp_status
                beq     pn_rb_sb
                dec     zp_temp
                bne     pn_rb_ack
                jmp     pn_rb_send
pn_rb_sb:       ldy     #CODE_SB            ; ACK seen: send S/B
                jsr     pn_send_code_y
                lda     pn_last             ; last block done and we sent GOO:
                beq     pn_rb_data
                lda     pn_send_code        ;   do the end handshake
                beq     pn_rb_end
pn_rb_data:     lda     PUNT_BUF0+4         ; size announced in the previous block
                sta     pn_count
                sta     pn_next_size
                jsr     pn_recv_bytes
                lda     zp_status
                cmp     #$01                ; 1 = full block received
                beq     pn_rb_exit
                cmp     #$02                ; 2 = nothing received: send S/B again
                beq     pn_rb_sb
                cmp     #$04                ; 4 = part of a block: return (bad block)
                beq     pn_rb_exit
                cmp     #$08                ; 8 = quiet line: send S/B again
                beq     pn_rb_sb
pn_rb_exit:     rts
pn_rb_end:      lda     #M_SYN              ; end handshake: wait for SYN
                jsr     pn_wait_code
                lda     zp_status
                bne     pn_rb_sb
                lda     #$0A
                sta     pn_count
pn_rb_end_lp:   ldy     #CODE_SYN           ; up to 10 times: send SYN, wait for S/B
                jsr     pn_send_code_y
                lda     #M_SB
                jsr     pn_wait_code
                lda     zp_status
                beq     pn_rb_end_x
                dec     pn_count
                bne     pn_rb_end_lp
pn_rb_end_x:    rts

; =============================================================================
; pn_send_step ($2291)
; -----------------------------------------------------------------------------
; Purpose : sender side of one Punter block exchange.  Wait for GOO/BAD (or
;           S/B), read the next block from file #2 (on GOO), send ACK, wait
;           for S/B, then send the block.  Two buffers are used: the block
;           that is sent is in the "other" buffer, the next one is read into
;           the "current" buffer.
; Output  : A = 0 (Z=1) more blocks to go, A = 1 transfer finished.
; Prints  : '-' good block, ':' resend, '*' end (see pn_progress)
; =============================================================================
pn_send_step:   lda     #$01
                sta     pn_sender
pn_ss_wait:     lda     pn_send_goo         ; file type send: send GOO first
                beq     pn_ss_get
                ldy     #CODE_GOO
                jsr     pn_send_code_y
pn_ss_get:      lda     #M_GOO|M_BAD|M_SB
                jsr     pn_wait_code
                lda     zp_status
                bne     pn_ss_wait
                lda     #$00
                sta     pn_send_goo
                lda     pn_code_idx         ; matched code: 0 = GOO, else BAD/S/B
                cmp     #$00
                bne     pn_ss_bad
                lda     pn_last             ; GOO after the last block: finish
                bne     pn_ss_end
                inc     pn_blknum           ; next block number
                bne     pn_ss_next
                inc     pn_blknum+1
pn_ss_next:     jsr     pn_cur_buf
                ldy     #$05
                iny                         ; block number hi = $FF: EOF marker
                lda     (zp_bufptr),y
                cmp     #$FF
                bne     pn_ss_read
                lda     #$01
                sta     pn_last
                lda     pn_bufsel
                eor     #$01
                sta     pn_bufsel
                jsr     pn_cur_buf
                jsr     pn_finish_eof
                jmp     pn_ss_good
pn_ss_read:     jsr     pn_read_block       ; read next block from the file
pn_ss_good:     lda     #'-'                ; progress: good block
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_ss_bad:      lda     #':'                ; progress: block sent again
                jsr     pn_progress
                ldy     #CODE_ACK           ; send ACK, wait for S/B
                jsr     pn_send_code_y
                lda     #M_SB
                jsr     pn_wait_code
                lda     zp_status
                bne     pn_ss_good
                jsr     pn_cur_buf
                ldy     #$04                ; size of the block to send
                lda     (zp_bufptr),y
                sta     pn_count
                jsr     pn_other_buf
                ldx     #LFN_MODEM          ; send the other buffer
                jsr     CHKOUT
                ldy     #$00
pn_ss_out:      lda     (zp_bufptr),y
                jsr     CHROUT
                iny
                cpy     pn_count
                bne     pn_ss_out
                jsr     CLRCHN
                lda     #$00
                rts
pn_ss_end:      lda     #'*'                ; progress: end of transfer
                jsr     pn_progress
                ldy     #CODE_ACK
                jsr     pn_send_code_y
                lda     #M_SB
                jsr     pn_wait_code
                lda     zp_status
                bne     pn_ss_end
                lda     #$0A
                sta     pn_count
pn_ss_syn:      ldy     #CODE_SYN           ; up to 10 times: send SYN, wait for SYN
                jsr     pn_send_code_y
                lda     #M_SYN
                jsr     pn_wait_code
                lda     zp_status
                beq     pn_ss_fin
                dec     pn_count
                bne     pn_ss_syn
pn_ss_fin:      lda     #$03                ; then send S/B 3 times (with a time-out
                sta     pn_count
pn_ss_fin_lp:   ldy     #CODE_SB
                jsr     pn_send_code_y
                lda     #0                  ;   wait between)
                jsr     pn_wait_code
                dec     pn_count
                bne     pn_ss_fin_lp
                lda     #$01
                rts

; =============================================================================
; pn_recv_bytes ($2364)
; -----------------------------------------------------------------------------
; Purpose : receive pn_count bytes from the modem into PUNT_BUF0.  If the
;           first 3 bytes are "ACK" (the sender repeated its ACK), the
;           counter is set to $FFFF and the next idle poll returns status 8
;           (the caller then sends S/B again).
; Output  : zp_status = 1 all bytes received
;                       2 time-out, nothing received
;                       4 time-out, part of the block received
;                       8 "ACK" seen at the block start
; =============================================================================
pn_recv_bytes:  ldy     #$00
pn_rx_reset:    lda     #$00
                sta     pn_timer
                sta     pn_timer+1
pn_rx_loop:     jsr     check_esc
                jsr     rs_get
                lda     zp_status
                bne     pn_rx_none
                lda     BUF
                sta     PUNT_BUF0,y
                cpy     #$03
                bcs     pn_rx_next
                sta     pn_window,y
                cpy     #$02
                bne     pn_rx_next
                lda     pn_window
                cmp     #'A'
                bne     pn_rx_next
                lda     pn_window+1
                cmp     #'C'
                bne     pn_rx_next
                lda     pn_window+2
                cmp     #'K'
                beq     pn_rx_ack
pn_rx_next:     iny
                cpy     pn_count
                bne     pn_rx_reset
                lda     #$01
                sta     zp_status
                rts
pn_rx_ack:      lda     #$FF
                sta     pn_timer
                sta     pn_timer+1
                jmp     pn_rx_loop
pn_rx_none:     inc     pn_timer
                bne     pn_rx_tmo
                inc     pn_timer+1
pn_rx_tmo:      lda     pn_timer
                ora     pn_timer+1
                beq     pn_rx_quiet
                lda     pn_timer            ; no effect (result overwritten)
                cmp     #$06
                lda     pn_timer+1
                cmp     #$10
                bne     pn_rx_loop
                lda     #$02
                sta     zp_status
                cpy     #$00
                beq     pn_rx_tmo_x
                lda     #$04
                sta     zp_status
pn_rx_tmo_x:    jmp     pn_timeout
pn_rx_quiet:    lda     #$08
                sta     zp_status
                rts

; =============================================================================
; pn_read_block ($23E4)
; -----------------------------------------------------------------------------
; Purpose : switch buffers and read the next block from file #2 into the new
;           current buffer, from offset 7, up to pn_blksize bytes.  Header
;           offset 5/6 = block number + 1; offset 6 = $FF marks the last block.
;           Then (pn_finish) wait for the transmitter, put the new size into
;           the outgoing block header and compute its checksum.
; pn_finish_eof ($2429): enter here when the EOF block is already known.
; =============================================================================
pn_read_block:  lda     pn_bufsel
                eor     #$01
                sta     pn_bufsel
                jsr     pn_cur_buf
                ldy     #$05
                lda     pn_blknum
                clc
                adc     #$01
                sta     (zp_bufptr),y
                iny
                lda     pn_blknum+1
                adc     #$00
                sta     (zp_bufptr),y
                ldx     #LFN_FILE
                jsr     CHKIN
                ldy     #$07
pn_rd_loop:     jsr     CHRIN
                sta     (zp_bufptr),y
                iny
                jsr     READST
                bne     pn_rd_eof           ; stop on EOF / error
                cpy     pn_blksize
                bne     pn_rd_loop
                tya
                pha
                jmp     pn_finish
pn_rd_eof:      tya                         ; EOF: mark this block as the last
                pha
                ldy     #$05
                iny
                lda     #$FF
                sta     (zp_bufptr),y
                jmp     pn_finish
pn_finish_eof:  pha
pn_finish:      jsr     CLRCHN
                jsr     rs_wait_tx
                jsr     delay               ; short delay between blocks
                jsr     rs_wait_tx
                ldy     #$04
                lda     (zp_bufptr),y
                sta     pn_count
                jsr     pn_other_buf
                pla
                ldy     #$04
                sta     (zp_bufptr),y
                jsr     pn_checksum
                rts

; =============================================================================
; pn_cur_buf ($2449) / pn_other_buf ($2456)
; -----------------------------------------------------------------------------
; Output  : zp_bufptr = $0500 + pn_bufsel * $100 (current buffer)
;           zp_bufptr = $0500 + (pn_bufsel EOR 1) * $100 (other buffer)
; =============================================================================
pn_cur_buf:     lda     #$00
                sta     zp_bufptr
                lda     pn_bufsel
                clc
                adc     #$05
                sta     zp_bufptr+1
                rts
pn_other_buf:   lda     #$00
                sta     zp_bufptr
                lda     pn_bufsel
                eor     #$01
                clc
                adc     #$05
                sta     zp_bufptr+1
                rts

; =============================================================================
; pn_checksum ($2465)
; -----------------------------------------------------------------------------
; Purpose : Punter checksum of (zp_bufptr) offsets 4 .. pn_count-1.
;           Bytes 0,1 = 16-bit sum; bytes 2,3 = 16-bit "cyclic" value
;           (EOR byte into low, then rotate the 16 bits left).
; Output  : 4 checksum bytes stored at offsets 0-3; also in pn_sum.
; =============================================================================
pn_checksum:    lda     #$00
                sta     pn_sum
                sta     pn_sum+1
                sta     pn_sum+2
                sta     pn_sum+3
                ldy     #$04
pn_cs_loop:     lda     pn_sum
                clc
                adc     (zp_bufptr),y
                sta     pn_sum
                bcc     pn_cs_cyc
                inc     pn_sum+1
pn_cs_cyc:      lda     pn_sum+2
                eor     (zp_bufptr),y
                sta     pn_sum+2
                lda     pn_sum+3            ; carry = bit 15, rotate 16 bits left
                rol     a
                rol     pn_sum+2
                rol     pn_sum+3
                iny
                cpy     pn_count
                bne     pn_cs_loop
                ldy     #$00
                lda     pn_sum
                sta     (zp_bufptr),y
                iny
                lda     pn_sum+1
                sta     (zp_bufptr),y
                iny
                lda     pn_sum+2
                sta     (zp_bufptr),y
                iny
                lda     pn_sum+3
                sta     (zp_bufptr),y
                rts

; =============================================================================
; pn_send_file ($24B5)   Punter function $06
; -----------------------------------------------------------------------------
; BASIC   : SYSDEC("20b7"):POKEDEC("201b"),bs:SYSDEC("20a8")  (lines 2024,2176)
; Purpose : send the file open as #2 with Punter.  pn_blksize = block size.
; Output  : BUF = 0 (finished) or 1 (ESC pressed)
; =============================================================================
pn_send_file:   lda     #$00
                sta     pn_last
                sta     pn_tmo_count
                sta     pn_quiet
                lda     #$01
                sta     pn_bufsel
                lda     #$FF
                sta     pn_blknum           ; block number $FFFF: first GOO makes it 0
                sta     pn_blknum+1
                jsr     pn_other_buf
                ldy     #$04
                lda     #$07                ; first block: header only (7 bytes)
                sta     (zp_bufptr),y
                jsr     pn_cur_buf
                ldy     #$05
                lda     #$00
                sta     (zp_bufptr),y
                iny
                sta     (zp_bufptr),y
pn_sf_loop:     jsr     pn_send_step
                beq     pn_sf_loop
pn_done:        lda     #$00                ; BUF = 0: not aborted
                sta     BUF
                rts

; =============================================================================
; pn_recv_file ($24ED)   Punter function $03
; -----------------------------------------------------------------------------
; BASIC   : SYSDEC("20b7"):SYSDEC("20a5")  (lines 2050, 2214)
; Purpose : receive a file with Punter and write it to file #2.
; Output  : BUF = 0 (finished) or 1 (ESC pressed)
; =============================================================================
pn_recv_file:   lda     #$01
                sta     pn_blknum
                lda     #$00
                sta     pn_blknum+1
                sta     pn_last
                sta     pn_bufsel
                sta     PUNT_BUF0+5
                sta     PUNT_BUF0+6
                sta     pn_tmo_count
                lda     #$07                ; first block is 7 bytes (header only)
                sta     PUNT_BUF0+4
                lda     #CODE_GOO           ; start with GOO
pn_rf_loop:     jsr     pn_recv_block
                lda     pn_last
                bne     pn_done
                jsr     pn_verify           ; checksum bad?
                bne     pn_rf_bad
                jsr     CLRCHN
                lda     pn_count
                cmp     #$07                ; header-only block: nothing to write
                beq     pn_rf_chk_last
                ldx     #LFN_FILE
                jsr     CHKOUT
                ldy     #$07
pn_rf_write:    lda     PUNT_BUF0,y
                jsr     CHROUT
                iny
                cpy     pn_count
                bne     pn_rf_write
                jsr     CLRCHN
pn_rf_chk_last: lda     PUNT_BUF0+6         ; block number hi = $FF: last block
                cmp     #$FF
                bne     pn_rf_dash
                lda     #$01
                sta     pn_last
                lda     #'*'                ; progress: last block
                .byte   $2C                 ; BIT abs opcode: skips the next 2-byte instruction
pn_rf_dash:     lda     #'-'                ; progress: good block
                jsr     CHROUT
                jsr     rs_wait_tx
                lda     #CODE_GOO
                jmp     pn_rf_loop
pn_rf_bad:      jsr     CLRCHN
                lda     #':'                ; progress: bad block
                jsr     CHROUT
                lda     pn_next_size        ; expect the same size again
                sta     PUNT_BUF0+4
                lda     #CODE_BAD           ; send BAD
                jmp     pn_rf_loop

; =============================================================================
; pn_verify ($2569)
; -----------------------------------------------------------------------------
; Purpose : check the checksum of the block in PUNT_BUF0 (size pn_next_size).
; Output  : A = 0 (Z=1) good, A = 1 bad.
; =============================================================================
pn_verify:      lda     PUNT_BUF0
                sta     pn_rx_sum
                lda     PUNT_BUF0+1
                sta     pn_rx_sum+1
                lda     PUNT_BUF0+2
                sta     pn_rx_sum+2
                lda     PUNT_BUF0+3
                sta     pn_rx_sum+3
                jsr     pn_cur_buf
                lda     pn_next_size
                sta     pn_count
                jsr     pn_checksum
                lda     PUNT_BUF0
                cmp     pn_rx_sum
                bne     pn_verify_bad
                lda     PUNT_BUF0+1
                cmp     pn_rx_sum+1
                bne     pn_verify_bad
                lda     PUNT_BUF0+2
                cmp     pn_rx_sum+2
                bne     pn_verify_bad
                lda     PUNT_BUF0+3
                cmp     pn_rx_sum+3
                bne     pn_verify_bad
                lda     #$00
                rts
pn_verify_bad:  lda     #$01
                rts

; =============================================================================
; pn_recv_type ($25B3)   Punter function $09
; -----------------------------------------------------------------------------
; BASIC   : SYSDEC("20b7"):SYSDEC("20ab")  then PEEK(DEC("201e")) (lines
;           2046-2048, 2212)
; Purpose : receive the one-block "file type" transfer (8-byte block).
; Output  : pn_ftype = file type byte (offset 7), BUF = 0 or 1 (ESC)
; =============================================================================
pn_recv_type:   lda     #$00
                sta     pn_blknum
                sta     pn_blknum+1
                sta     pn_last
                sta     pn_bufsel
                sta     pn_tmo_count
                lda     #$07
                clc                         ; block size 8 = header + type byte
                adc     #$01
                sta     PUNT_BUF0+4
                lda     #CODE_GOO
pn_rt_loop:     jsr     pn_recv_block
                lda     pn_last
                bne     pn_rt_done
                jsr     pn_verify
                bne     pn_rt_bad
                lda     PUNT_BUF0+7
                sta     pn_ftype
                lda     #$01
                sta     pn_last
                lda     #CODE_GOO
                jmp     pn_rt_loop
pn_rt_bad:      lda     pn_next_size
                sta     PUNT_BUF0+4
                lda     #CODE_BAD
                jmp     pn_rt_loop
pn_rt_done:     lda     #$00
                sta     BUF
                rts

; =============================================================================
; pn_send_type ($25FC)   Punter function $0C
; -----------------------------------------------------------------------------
; BASIC   : SYSDEC("20b7"):POKEDEC("201e"),t:SYSDEC("20ae")  (lines 2022,2172)
; Purpose : send the file type pn_ftype as a one-block transfer.  No
;           progress characters (pn_quiet = 1).
; Output  : BUF = 0 or 1 (ESC)
; =============================================================================
pn_send_type:   lda     #$00
                sta     pn_last
                sta     pn_tmo_count
                lda     #$01
                sta     pn_bufsel
                sta     pn_quiet
                lda     #$FF
                sta     pn_blknum
                sta     pn_blknum+1
                jsr     pn_other_buf
                ldy     #$04
                lda     #$07
                clc
                adc     #$01
                sta     (zp_bufptr),y
                jsr     pn_cur_buf
                ldy     #$05
                lda     #$FF                ; block number $FFFF = last block
                sta     (zp_bufptr),y
                iny
                sta     (zp_bufptr),y
                ldy     #$07
                lda     pn_ftype            ; type byte at offset 7
                sta     (zp_bufptr),y
                lda     #$01
                sta     pn_send_goo
pn_st_loop:     jsr     pn_send_step
                beq     pn_st_loop
                lda     #$00
                sta     BUF
                rts

; =============================================================================
; pn_timeout ($2643)
; -----------------------------------------------------------------------------
; Purpose : called on each time-out.  The sender waits (delay) on the first
;           two of every three time-outs; the receiver on every third.
; -----------------------------------------------------------------------------
; delay ($265E): busy loop, 120 * 256 iterations.  X,Y destroyed.
; =============================================================================
pn_timeout:     inc     pn_tmo_count
                lda     pn_tmo_count
                cmp     #$03
                bcc     pn_tmo_rx
                lda     #$00
                sta     pn_tmo_count
                lda     pn_sender
                beq     delay
                bne     pn_tmo_x
pn_tmo_rx:      lda     pn_sender
                beq     pn_tmo_x
delay:          ldx     #$00
delay_x:        ldy     #$00
delay_y:        iny
                bne     delay_y
                inx
                cpx     #$78
                bne     delay_x
pn_tmo_x:       rts

; =============================================================================
; pn_progress ($266B)
; -----------------------------------------------------------------------------
; Purpose : print A on the screen, but not for block 0 and not when
;           pn_quiet is set.  A preserved.
; =============================================================================
pn_progress:    pha
                lda     pn_blknum
                ora     pn_blknum+1
                beq     pn_progress_x
                lda     pn_quiet
                bne     pn_progress_x
                pla
                jsr     CHROUT
                pha
pn_progress_x:  pla
                rts

; =============================================================================
; rs_wait_tx ($2680)    also BASIC SYSDEC("20b7") via $20B7
; -----------------------------------------------------------------------------
; Purpose : wait until the RS-232 transmitter is idle (ENABL not $80/$92).
;           ; ? K_E6C2 is a C128 KERNAL RS-232 routine, not identified.
; =============================================================================
rs_wait_tx:     jsr     K_E6C2
                lda     ENABL
                cmp     #$80
                beq     rs_wait_tx
                cmp     #$92
                beq     rs_wait_tx
                rts

; =============================================================================
; chat ($268F)   Punter function $0F (no BASIC caller found)
; -----------------------------------------------------------------------------
; Purpose : simple ASCII terminal.  Modem bytes (bit 7 cleared) are changed
;           from ASCII to PETSCII and printed; keys are changed from PETSCII
;           to ASCII and sent.  A block cursor is drawn.  HOME exits.
;           ESC exits too: draw_cursor falls into check_esc.
; =============================================================================
chat:           jsr     draw_cursor
chat_loop:      jsr     rs_get_nop          ; NOP, then rs_get
                lda     zp_status
                bne     chat_key_j
                lda     BUF
                and     #$7F
                sta     BUF
                cmp     #$08                ; keep BS, CR and printable chars
                beq     chat_conv
                cmp     #$0D
                beq     chat_conv
                cmp     #$20
                bpl     chat_conv
chat_key_j:     jmp     chat_key
chat_conv:      cmp     #$61                ; a-z -> PETSCII lower case
                bcc     chat_upper
                cmp     #$7B
                bcs     chat_upper
                sec
                sbc     #$20
                sta     BUF
                jmp     chat_bs
chat_upper:     cmp     #$41                ; A-Z -> PETSCII upper case
                bcc     chat_bs
                cmp     #$5B
                bcs     chat_bs
                clc
                adc     #$80
                sta     BUF
chat_bs:        cmp     #$08                ; BS -> DEL
                bne     chat_quote
                lda     #$14
                sta     BUF
chat_quote:     cmp     #$22                ; '"': print '"', DEL, '"' (quote mode ends off)
                bne     chat_cr
                jsr     CHROUT
                lda     #$14
                jsr     CHROUT
                lda     #$22
chat_cr:        lda     BUF
                cmp     #$0D                ; CR: print a space first (erase cursor)
                bne     chat_print
                lda     #$20
                jsr     CHROUT
                lda     #$0D
chat_print:     jsr     CHROUT
                jsr     draw_cursor
chat_key:       jsr     GETIN
                beq     chat_loop
                sta     BUF
                cmp     #$13                ; $13 HOME: exit
                beq     chat_exit
                cmp     #$41                ; PETSCII A-Z ($41-$5A) -> ASCII a-z
                bcc     chat_shifted
                cmp     #$5B
                bcs     chat_shifted
                clc
                adc     #$20
                sta     BUF
                jmp     chat_del
chat_shifted:   lda     BUF                 ; PETSCII $C1-$DA -> ASCII A-Z
                cmp     #$C1
                bcc     chat_del
                cmp     #$DB
                bcs     chat_del
                sec
                sbc     #$80
                sta     BUF
chat_del:       cmp     #$14                ; DEL -> BS
                bne     chat_rvs
                lda     #$08
                sta     BUF
chat_rvs:       cmp     #$83                ; $83 (shift RUN/STOP) -> $10  ; ?
                bne     chat_send
                lda     #$10
                sta     BUF
chat_send:      ldx     #LFN_MODEM
                jsr     CHKOUT
                lda     BUF
                jsr     CHROUT
                jsr     CLRCHN
                jmp     chat
chat_exit:      rts

; =============================================================================
; draw_cursor ($274C) / check_esc ($2760)
; -----------------------------------------------------------------------------
; draw_cursor: print RVS ON, $B8, CRSR LEFT, RVS OFF (block cursor), then
;           fall into check_esc.
; check_esc: if ESC is held (SFDX = KEY_ESC), pull stack bytes until SP =
;           pn_saved_sp, so the next RTS returns to BASIC (ends the SYS).
;           Always sets BUF = 1 (overwritten later on a normal exit).
; =============================================================================
draw_cursor:    lda     #$12
                jsr     CHROUT
                lda     #$B8
                jsr     CHROUT
                lda     #$9D
                jsr     CHROUT
                lda     #$92
                jsr     CHROUT
check_esc:      lda     SFDX
                cmp     #KEY_ESC
                bne     check_esc_x
check_esc_pop:  pla
                tsx
                cpx     pn_saved_sp
                bne     check_esc_pop
check_esc_x:    lda     #$01
                sta     BUF
                rts

; =============================================================================
; install_hook ($2773)    BASIC: SYSDEC("20ba") line 40 (via $20BA)
; -----------------------------------------------------------------------------
; Purpose : point the CHROUT vector IBSOUT ($0326) at new_bsout, keep the
;           old vector in old_ibsout.  Does nothing if already installed.
; =============================================================================
install_hook:   lda     IBSOUT
                cmp     #<new_bsout
                bne     install_hook_set
                lda     IBSOUT+1
                cmp     #>new_bsout
                beq     install_hook_x
install_hook_set:
                lda     IBSOUT
                sta     old_ibsout
                lda     IBSOUT+1
                sta     old_ibsout+1
                lda     #<new_bsout
                sta     IBSOUT
                lda     #>new_bsout
                sta     IBSOUT+1
install_hook_x: rts

; =============================================================================
; new_bsout ($2798)  CHROUT replacement (via IBSOUT)
; -----------------------------------------------------------------------------
; Purpose : output devices >= 3 go to the old vector.  Devices 0-2 are
;           handled here with a copy of the KERNAL code; for RS-232
;           (device 2) the transmitter is started with the baud timer value
;           in baud_timer ($202A/$202B, set by BASIC line 1905).
;           Device 1 (tape) code is the KERNAL tape-buffer write.
;           ; ? device 0 also takes the RS-232 path (LSR -> carry clear)
; Input   : A = character.  Output: A preserved, carry clear (OK).
; rs_out_byte ($27DF): put PTR1 into the RS-232 output buffer (wait if full).
; rs_start_tx ($27F0): start the transmitter if it is not running.
; =============================================================================
new_bsout:      pha
                lda     DFLTO
                cmp     #$03
                bne     nb_not3
                pla
                jmp     (old_ibsout)
nb_not3:        bcc     nb_dev01
                pla
                jmp     (old_ibsout)
nb_dev01:       lsr     a                   ; carry = bit 0 of device: 1 = tape
                pla
                sta     PTR1
                txa
                pha
                tya
                pha
                bcc     nb_rs232
                jsr     K_JTP20             ; tape: buffer full?
                bne     nb_tape_store
                jsr     K_WBLK              ; write tape block
                bcs     nb_exit
                lda     #$02
                ldy     #$00
                sta     (TAPE1),y
                iny
                sty     BUFPT
nb_tape_store:  lda     PTR1
                sta     (TAPE1),y
nb_ok:          clc
nb_exit:        pla
                tay
                pla
                tax
                lda     PTR1
                bcc     nb_rts
                lda     #$00
nb_rts:         rts
nb_rs232:       jsr     rs_out_byte
                jmp     nb_ok
rs_out_wait:    jsr     rs_start_tx         ; buffer full: start/keep transmitting
rs_out_byte:    ldy     RODBE               ; RODBE + 1 = RODBS -> output buffer full
                iny
                cpy     RODBS
                beq     rs_out_wait
                sty     RODBE
                dey
                lda     PTR1
                sta     (ROBUF),y
rs_start_tx:    lda     ENABL               ; transmitter already running?
                lsr     a
                bcs     rs_start_tx_x
                lda     #$10                ; CIA2 TA: stop, force load
                sta     CIA2_CRA
                lda     baud_timer
                sta     CIA2_TALO
                lda     baud_timer+1
                sta     CIA2_TAHI
                lda     #$81
                jsr     K_ORIOEN            ; enable TA NMI  ; ?
                jsr     K_RSTRAB            ; start bit / first byte  ; ?
                lda     #$11                ; CIA2 TA: start, continuous
                sta     CIA2_CRA
rs_start_tx_x:  rts

; =============================================================================
; terminal ($2815)   jump table entry $2093
; -----------------------------------------------------------------------------
; Purpose : simple terminal.  Modem bytes are case-swapped (ASCII ->
;           PETSCII), shown with an underline cursor and stored in the
;           capture buffer (bank 1, cap_end) unless cap_off is set.
;           Keys are case-swapped and sent to the modem.
; Exit    : term_exit = 0 ESC, 1-8 F1-F8 (keys $85-$8C), 9 TAB,
;           $FF capture buffer full ($E000).  cap_end updated (not for TAB).
;           C= 1/2/3 run the macro slots.  $0C (form feed) clears the screen.
; =============================================================================
terminal:       lda     cap_end
                sta     zp_capptr
                lda     cap_end+1
                sta     zp_capptr+1
term_loop:      jsr     CLRCHN
                ldx     #LFN_MODEM
                jsr     CHKIN
                jsr     GETIN               ; byte from the modem
                cmp     #$0C                ; $0C form feed: clear screen
                bne     term_rx
                jsr     CLRCHN
                ldx     #LFN_FILE
                jsr     CHKIN               ; ?  CHKIN of file #2 before CLR
                lda     #$93                ; {clear}
                jsr     CHROUT
                jmp     term_loop
term_rx:        cmp     #$00
                bne     term_rx_conv
                jmp     term_kbd
term_rx_conv:   and     #$7F                ; swap case: $40-$5A -> +$20
                cmp     #$40
                bmi     term_rx_lower
                cmp     #$5B
                bpl     term_rx_lower
                ora     #$20
                jmp     term_rx_out
term_rx_lower:  cmp     #$60                ; $60-$7A -> -$20
                bmi     term_rx_out
                cmp     #$7B
                bpl     term_rx_out
                and     #$DF
term_rx_out:    jsr     term_show
term_kbd:       jsr     CLRCHN
                ldx     #LFN_MODEM
                jsr     CHKOUT
                jsr     GETIN               ; key from the keyboard (input = keyboard)
                bne     term_key
                jmp     term_loop

; -----------------------------------------------------------------------------
; term_show ($2871): show a received character, store it in the capture
; buffer.  LF is ignored, BS shown as DEL.
; -----------------------------------------------------------------------------
term_show:      cmp     #$0A
                bne     term_show_bs
                rts
term_show_bs:   cmp     #$08
                bne     term_show_cap
                lda     #$14
                jmp     term_put_cursor
term_show_nocap:
                jmp     term_show_char
term_show_cap:  pha                         ; capture on?
                lda     cap_off
                bne     term_show_nocap
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     STAVEC
                pla
                pha
                jsr     STASH               ; STASH A to bank 1 at (zp_capptr)
                inc     zp_capptr
                bne     term_show_chk
                inc     zp_capptr+1
term_show_chk:  lda     zp_capptr+1         ; buffer full at $E000:
                cmp     #>CAP_LIMIT
                bne     term_show_char
                pla                         ; drop char + return address, exit
                pla
                pla
                lda     #$FF
                sta     term_exit
                jmp     term_save_exit
term_show_char: pla                         ; quote: print '"', DEL, '"'
                cmp     #$22
                bne     term_put_cursor
                jsr     CHROUT
                lda     #$14
                jsr     CHROUT
                lda     #$22
                jsr     CHROUT
                rts
term_put_cursor:
                pha                         ; print space, left, char, '_', left
                lda     #$20
                jsr     CHROUT
                lda     #$9D
                jsr     CHROUT
                pla
                jsr     CHROUT
                lda     #$A4
                jsr     CHROUT
                lda     #$9D
                jsr     CHROUT
                rts

; -----------------------------------------------------------------------------
; term_key ($28DA): handle a key.  Output channel is the modem.
; -----------------------------------------------------------------------------
term_key:       pha
                lda     term_echo           ; local echo?
                beq     term_key_conv
                jsr     CLRCHN
                pla
                pha
                jsr     term_show
                ldx     #LFN_MODEM
                jsr     CHKOUT
term_key_conv:  pla
                cmp     #$40
                bmi     term_key_lower
                cmp     #$5B
                bpl     term_key_lower
                ora     #$20
                jmp     term_key_del
term_key_lower: cmp     #$60
                bmi     term_key_del
                cmp     #$7B
                bpl     term_key_del
                and     #$DF
term_key_del:   cmp     #$14                ; DEL -> BS
                bne     term_key_esc
                lda     #$08
term_key_esc:   cmp     #$1B                ; ESC: exit code 0
                bne     term_key_fkey
                lda     #$00
                sta     term_exit
                jmp     term_save_exit
term_key_fkey:  cmp     #$85                ; F1-F8 ($85-$8C): exit code 1-8
                bmi     term_key_m1
                cmp     #$8D
                bpl     term_key_m1
                sec
                sbc     #$84
                sta     term_exit
                jmp     term_save_exit
term_key_m1:    cmp     #$81                ; C= 1
                bne     term_key_m2
                jmp     macro1
term_key_m2:    cmp     #$95                ; C= 2
                bne     term_key_m3
                jmp     macro2
term_key_m3:    cmp     #$96                ; C= 3
                bne     term_key_tab
                jmp     macro3
term_key_tab:   cmp     #$09                ; TAB: exit code 9 (cap_end not saved)
                bne     term_key_send
                jsr     CLRCHN
                lda     #$09
                sta     term_exit
                rts
term_key_send:  jsr     CHROUT              ; send key to modem
term_loop_j:    jmp     term_loop
term_save_exit: lda     zp_capptr
                sta     cap_end
                lda     zp_capptr+1
                sta     cap_end+1
clrchn_exit:    jsr     CLRCHN
                rts

; =============================================================================
; send_buffer ($295E)   jump table entry $2099
; -----------------------------------------------------------------------------
; Purpose : go through the capture buffer from $0400 to cap_end.
;           bs_mode 1 = screen and file #2, 3 = file #2 only,
;           2 = screen and file #2 with case swap and (if bs_noecho = 0) wait
;           for the echo from the modem (#5) before the next char,
;           other = screen only.
;           ; ? in mode 2, file #2 must be an RS-232 channel opened by BASIC.
; Stop    : at cap_end or when ESC is pressed.
; =============================================================================
send_buffer:    ldx     #LFN_FILE
                jsr     CHKOUT
                lda     #<CAP_START
                sta     zp_capptr
                lda     #>CAP_START
                sta     zp_capptr+1
sb_loop:        ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     FETVEC
                jsr     FETCH               ; FETCH from bank 1
                sta     bs_char
                lda     bs_mode
                cmp     #$03
                bne     sb_screen
                jmp     sb_to_file
sb_mode1:       lda     bs_mode
                cmp     #$01
                bne     sb_next
sb_to_file:     ldx     #LFN_FILE
                jsr     CHKOUT
                lda     bs_char
                jsr     CHROUT
sb_next:        inc     zp_capptr
                bne     sb_chk_end
                inc     zp_capptr+1
sb_chk_end:     lda     zp_capptr+1
                cmp     cap_end+1
                bne     sb_chk_esc
                lda     zp_capptr
                cmp     cap_end
                bne     sb_chk_esc
                rts
sb_chk_esc:     lda     LSTX
                cmp     #KEY_ESC
                bne     sb_loop_j
                rts
sb_loop_j:      jmp     sb_loop
sb_mode1_j:     jmp     sb_mode1
sb_screen:      jsr     CLRCHN
                lda     bs_char
                jsr     CHROUT
                lda     bs_mode
                cmp     #$02
                bne     sb_mode1_j
                lda     bs_char
                cmp     #$40
                bmi     sb_m2_del
                cmp     #$60
                bpl     sb_m2_lower
                ora     #$20
                jmp     sb_m2_store
sb_m2_lower:    cmp     #$60
                bmi     sb_m2_store
                cmp     #$80
                bpl     sb_m2_store
                and     #$DF
                jmp     sb_m2_store
sb_m2_del:      cmp     #$14
                bne     sb_m2_store
                lda     #$08
sb_m2_store:    sta     bs_char
                lda     bs_noecho
                cmp     #$00
                bne     sb_to_file
                lda     zp_capptr+1
                cmp     cap_end+1
                bne     sb_m2_esc
                lda     zp_capptr
                adc     #$01                ; ?  ADC without CLC
                cmp     cap_end
                bne     sb_m2_esc
                rts
sb_m2_esc:      lda     SFDX
                cmp     #KEY_ESC
                bne     sb_echo_send
                rts
sb_echo_send:   ldx     #LFN_FILE           ; send the char, then wait for its echo
                jsr     CHKOUT
                ldx     #LFN_MODEM
                jsr     CHKIN
                lda     bs_char
                jsr     CHROUT
                lda     #$00
                sta     echo_cnt_lo
                sta     echo_sent
                sta     echo_got
                sta     echo_cnt_mid
                sta     echo_cnt_hi
                jsr     CHRIN
                cmp     #$00
                beq     sb_echo_wait
sb_echo_cmp:    sta     echo_got            ; compare ignoring case (AND $5F)
                lda     bs_char
                and     #$5F
                sta     echo_sent
                lda     echo_got
                and     #$5F
                cmp     echo_sent
                bne     sb_echo_wait
                jmp     sb_next
sb_echo_wait:   inc     echo_cnt_lo
                jsr     CHRIN
                cmp     #$00
                bne     sb_echo_cmp
                lda     SFDX
                cmp     #KEY_ESC
                bne     sb_echo_count
                rts
sb_echo_count:  lda     echo_cnt_lo         ; about 255*255*5 polls, then send again
                cmp     #$FF
                bne     sb_echo_wait
                lda     #$00
                sta     echo_cnt_lo
                inc     echo_cnt_mid
                lda     echo_cnt_mid
                cmp     #$FF
                bne     sb_echo_wait
                lda     #$00
                sta     echo_cnt_mid
                inc     echo_cnt_hi
                lda     echo_cnt_hi
                cmp     #$05
                bne     sb_echo_wait
                jsr     CLRCHN
                lda     bs_char
                jsr     CHROUT
                jmp     sb_echo_send
echo_cnt_hi:    .byte   $00

; =============================================================================
; read_dir ($2A90)   BASIC: SYSDEC("209f") line 2058, via $209F
; -----------------------------------------------------------------------------
; Purpose : read one directory line from file #2 (OPEN2,dv,0,"$:*") and put
;           "name,T" padded with spaces to 18 chars into the BASIC string A$.
;           BASIC sets a$ to 18 chars first (line 2054) and then copies it:
;           a$(t)=a$.  T = first 'P' or 'S' after the name.
; Method  : search bank 1 from $E000 upward (wrapping at $FFFF) for the
;           variable-table entry "A",$80 (string A$), then use its pointer.
;           ; ? starting at $E000 and wrapping looks odd but works if A$ is
;           found before any false match.
; Output  : ST <> 0 (READST) at end of the directory; BASIC tests st.
; =============================================================================
read_dir:       ldx     #LFN_FILE
                jsr     CHKIN
                lda     #<CAP_LIMIT
                sta     zp_capptr
                lda     #>CAP_LIMIT
                sta     zp_capptr+1
rd_find_var:    jsr     set_fetch_ptr
                jsr     FETCH
                jsr     inc_capptr
                cmp     #$41
                bne     rd_find_var
                jsr     set_fetch_ptr
                jsr     FETCH
                jsr     inc_capptr
                cmp     #$80
                bne     rd_find_var
                jsr     inc_capptr          ; skip the length byte
                jsr     set_fetch_ptr
                jsr     FETCH               ; string pointer lo
                jsr     inc_capptr
                pha
                jsr     set_fetch_ptr
                jsr     FETCH               ; string pointer hi
                sta     zp_capptr+1
                pla
                sta     zp_capptr
rd_find_quote:  jsr     GETIN
                cmp     #$22                ; skip to the opening quote
                beq     rd_name
                jsr     READST
                beq     rd_find_quote
                jmp     clrchn_exit
rd_name:        ldx     #$00
                stx     zp_fa
rd_name_lp:     jsr     GETIN
                cmp     #$22                ; copy name until the closing quote
                beq     rd_name_end
                inc     zp_fa
                jsr     set_stash_ptr
                jsr     STASH
                jsr     inc_capptr
                jmp     rd_name_lp
rd_name_end:    lda     #$2C
                jsr     set_stash_ptr
                jsr     STASH
                jsr     inc_capptr
                inc     zp_fa
rd_type:        jsr     GETIN
                cmp     #$50                ; file type letter P or S  ; ? other types loop
                beq     rd_type_store
                cmp     #$53
                beq     rd_type_store
                jmp     rd_type
rd_type_store:  jsr     set_stash_ptr
                jsr     STASH
                jsr     inc_capptr
                inc     zp_fa
rd_pad:         lda     zp_fa
                cmp     #$12                ; pad to 18 chars
                beq     rd_exit
                lda     #$20
                jsr     set_stash_ptr
                jsr     STASH
                jsr     inc_capptr
                inc     zp_fa
                jmp     rd_pad
rd_exit:        jmp     clrchn_exit

; -----------------------------------------------------------------------------
; set_fetch_ptr ($2B36): X = MMU_BANK1, Y = 0, FETVEC = zp_capptr.
; inc_capptr ($2B40):    zp_capptr = zp_capptr + 1.
; set_stash_ptr ($2B47): X = MMU_BANK1, Y = 0, STAVEC = zp_capptr, A kept.
; -----------------------------------------------------------------------------
set_fetch_ptr:  ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     FETVEC
                rts
inc_capptr:     inc     zp_capptr
                bne     inc_capptr_x
                inc     zp_capptr+1
inc_capptr_x:   rts
set_stash_ptr:  pha
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     STAVEC
                pla
                rts

; =============================================================================
; type_file ($2B53)   jump table entry $2096
; -----------------------------------------------------------------------------
; Purpose : print file #2 on the screen until EOF or RUN/STOP.
; =============================================================================
type_file:      jsr     CLRCHN
                ldx     #LFN_FILE
                jsr     CHKIN
tf_loop:        jsr     CHRIN
                jsr     CHROUT
                lda     LSTX
                cmp     #KEY_STOP
                beq     tf_exit
                lda     #$08
                jsr     READST              ; A is not used by READST
                beq     tf_loop
tf_exit:        jsr     CLRCHN
                rts

; =============================================================================
; load_buffer ($2B72)   jump table entry $209C
; -----------------------------------------------------------------------------
; Purpose : append file #2 to the capture buffer (raw bytes) until EOF or
;           the buffer is full ($E000).  cap_end updated.
; =============================================================================
load_buffer:    ldx     #LFN_FILE
                jsr     CHKIN
                lda     cap_end
                sta     zp_capptr
                lda     cap_end+1
                sta     zp_capptr+1
lb_loop:        jsr     CHRIN
                pha
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     STAVEC
                pla
                jsr     STASH
                inc     zp_capptr
                bne     lb_chk_full
                inc     zp_capptr+1
lb_chk_full:    lda     zp_capptr+1
                cmp     #>CAP_LIMIT
                bne     lb_next
                jmp     term_save_exit
lb_next:        lda     #$08
                jsr     READST
                beq     lb_loop
                jmp     term_save_exit

; =============================================================================
; xm_send ($2BAB)   BASIC: SYS xc ($20ED) line 2224, after a NAK was received
; -----------------------------------------------------------------------------
; Purpose : XMODEM (checksum) send of file #2.  Block in XM_BUF+1..+$84:
;           SOH, block, 255-block, 128 data bytes, checksum.  The last block
;           is padded with $1A.  Each block is resent on NAK (max 10 times).
; Output  : xm_status = 0 sent (BASIC then sends EOT), 3 CAN or ESC,
;           4 too many retries.  Prints '-' per ACK, ':' per NAK.
; Note    : ; ? the byte read together with the EOF status ($40) is not
;           stored, so the last byte of the file seems to be lost.
; =============================================================================
xm_send:        lda     #$01
                sta     xm_block
                tay
xm_s_block:     lda     #XM_SOH
                sta     XM_BUF,y            ; SOH
                iny
                sty     xm_pos
                lda     xm_block
                sta     XM_BUF,y
                eor     #$FF
                iny                         ; 255 - block number
                sta     XM_BUF,y
                lda     #$00
                sta     xm_sum
                sta     xm_retry
                ldx     #LFN_FILE
                jsr     CHKIN
                sty     xm_pos
xm_s_read:      inc     xm_pos
                jsr     GETIN               ; next byte from file #2
                sta     xm_char
                jsr     READST
                beq     xm_s_store          ; status 0: store byte; else pad the block
xm_s_pad:       lda     #$1A                ; pad with $1A (CP/M EOF)
                ldy     xm_pos
                sta     XM_BUF,y
                lda     xm_sum
                clc
                adc     #$1A
                and     #$FF
                sta     xm_sum
                iny
                sty     xm_pos
                cpy     #$84
                bne     xm_s_pad
                lda     xm_sum
                sta     XM_BUF,y
                ldy     #$01
xm_s_last_out:  sty     xm_index            ; send the last block
xm_s_last_lp:   ldx     #LFN_MODEM
                jsr     CHKOUT
                ldy     xm_index
                lda     XM_BUF,y
                jsr     CHROUT
                inc     xm_index
                ldy     xm_index
                cpy     #$85
                bne     xm_s_last_out
xm_s_last_wait: clc                         ; wait until the transmitter is idle
                lda     ENABL
                and     #$03
                cmp     #$00
                bne     xm_s_last_wait
                jsr     CLRCHN
xm_s_last_resp: ldx     #LFN_MODEM
                jsr     CHKIN
                jsr     GETIN
                pha
                ldx     SFDX
                cpx     #KEY_ESC
                bne     xm_s_last_j
                pla
                jmp     xm_s_cancel
xm_s_last_j:    jmp     xm_s_last_got
xm_s_store:     ldy     xm_pos
                lda     xm_char
                sta     XM_BUF,y
                lda     xm_sum
                clc
                adc     XM_BUF,y
                and     #$FF
                sta     xm_sum
                ldy     xm_pos
                iny
                cpy     #$84
                bne     xm_s_read_j
                jmp     xm_s_full
xm_s_read_j:    jmp     xm_s_read
xm_s_full:      lda     xm_sum              ; store checksum
                sta     XM_BUF,y
xm_s_resend:    jsr     xm_flush            ; send the block (after flushing input)
                ldy     #$01
xm_s_out:       sty     xm_index
                ldx     #LFN_MODEM
                jsr     CHKOUT
                ldy     xm_index
                lda     XM_BUF,y
                jsr     CHROUT
                iny
                cpy     #$85
                bne     xm_s_out
xm_s_wait:      clc
                lda     ENABL
                and     #$03
                cmp     #$00
                bne     xm_s_wait
                jsr     CLRCHN
                ldx     #LFN_MODEM
                jsr     CHKIN
xm_s_resp:      jsr     GETIN
                pha
                ldx     SFDX
                cpx     #KEY_ESC
                bne     xm_s_got
                pla
                jmp     xm_s_cancel
xm_s_got:       pla
                cmp     #$00
                beq     xm_s_resp
                pha
                jsr     CLRCHN
                pla
                cmp     #XM_ACK             ; ACK: next block
                bne     xm_s_nak
                lda     xm_good_char
                jsr     CHROUT
                inc     xm_block
                lda     xm_block
                and     #$FF
                sta     xm_block
                ldy     #$01
                jmp     xm_s_block
xm_s_nak:       cmp     #XM_NAK             ; NAK: resend, max 10 retries
                bne     xm_s_can
                lda     xm_bad_char
                jsr     CHROUT
                inc     xm_retry
                lda     xm_retry
                cmp     #$0B
                bne     xm_s_resend
                lda     #$04
                sta     xm_status
                jmp     xm_s_exit
xm_s_can:       cmp     #XM_CAN             ; CAN
                bne     xm_s_resp_j
xm_s_cancel:    lda     #$03                ; ESC or CAN: status 3
                sta     xm_status
                jmp     xm_s_exit
xm_s_resp_j:    jmp     xm_s_resp
xm_s_last_got:  pla
                cmp     #$00
                beq     xm_s_last_none
                jmp     xm_s_last_chk
xm_s_last_none: jmp     xm_s_last_resp
xm_s_last_chk:  pha
                jsr     CLRCHN
                pla
                cmp     #XM_ACK             ; ACK of last block: status 0
                bne     xm_s_last_nak
                lda     xm_good_char
                jsr     CHROUT
                lda     #$00
                sta     xm_status
                jmp     xm_s_exit
xm_s_last_nak:  cmp     #XM_NAK
                bne     xm_s_last_can
xm_s_last_retry:
                lda     xm_bad_char
                jsr     CHROUT
                inc     xm_retry
                lda     xm_retry
                cmp     #$0B
                bne     xm_s_last_again
                jmp     xm_s_last_fail
xm_s_last_again:
                jmp     xm_s_last_lp
xm_s_last_fail: lda     #$04
                sta     xm_status
                jmp     xm_s_exit
xm_s_last_can:  cmp     #XM_CAN             ; other bytes count as NAK
                bne     xm_s_last_retry
                lda     #$03
                sta     xm_status
xm_s_exit:      jsr     CLRCHN
                rts

; =============================================================================
; XMODEM helpers
; -----------------------------------------------------------------------------
; xm_wait_tx ($2D49)  same as rs_wait_tx.
; xm_delay ($2D58)    same as delay.
; xm_get ($2D65)      get byte from RS-232 input buffer, no wait.
;                     A = byte (0 if none), zp_status = 0 got / 2 none.
; xm_flush ($2D83)    empty the RS-232 input buffer.
; xm_check_esc ($2D8A) if ESC held, unwind stack to xm_saved_sp and
;                     return to BASIC (xm_unwind is also used to exit).
; =============================================================================
xm_wait_tx:     jsr     K_E6C2
                lda     ENABL
                cmp     #$80
                beq     xm_wait_tx
                cmp     #$92
                beq     xm_wait_tx
                rts
xm_delay:       ldx     #$00
xm_delay_x:     ldy     #$00
xm_delay_y:     iny
                bne     xm_delay_y
                inx
                cpx     #$78
                bne     xm_delay_x
                rts
xm_get:         lda     RIDBE
                cmp     RIDBS
                beq     xm_get_empty
                ldy     RIDBS
                lda     (RIBUF),y
                pha
                inc     RIDBS
                lda     #$00
                sta     zp_status
                pla
                rts
xm_get_empty:   lda     #$02
                sta     zp_status
                lda     #$00
                rts
xm_flush:       ldx     RIDBE
                stx     RIDBS
                rts
xm_check_esc:   lda     SFDX
                cmp     #KEY_ESC
                bne     xm_check_esc_x
xm_unwind:      pla
                tsx
                cpx     xm_saved_sp
                bne     xm_unwind
xm_check_esc_x: rts

; =============================================================================
; xm_recv ($2D98)   BASIC: mg=xc+8:POKEmg,2:SYS xc+4 ($20F1) line 2264
; -----------------------------------------------------------------------------
; Purpose : XMODEM (checksum) receive to file #2.  Sends NAK every 2*256
;           jiffies until SOH, then receives blocks; ACK good ones, NAK bad
;           ones, ACK a duplicate of the last block.
; Output  : xm_status = 0 EOT received, 1 sync lost (255 junk bytes or wrong
;           block number), 3 CAN or ESC, 4 more than 10 tries.
;           Prints '-' good block, ':' bad block, '/' duplicate.
; =============================================================================
xm_recv:        tsx
                stx     xm_saved_sp
                lda     #$01
                sta     xm_block
                sta     zp_fa
                lda     #$00
                sta     xm_retry
                sta     xm_index
                jsr     xm_wait_tx
xm_r_nak_start: lda     #$00                ; jiffy clock = 0
                tax
                tay
                jsr     SETTIM
                ldx     #LFN_MODEM
                jsr     CHKOUT
                lda     #XM_NAK
                jsr     CHROUT              ; NAK: start, checksum mode
                jsr     CLRCHN
xm_r_wait_soh:  jsr     xm_check_esc
                jsr     xm_get
                tax
                lda     zp_status
                cmp     #$02
                beq     xm_r_soh_tmo
                txa
                cmp     #XM_SOH             ; SOH?
                bne     xm_r_soh_tmo
                cmp     #XM_CAN             ; never true (A = 1 here)
                beq     xm_r_can
                ldy     zp_fa
                jmp     xm_r_store
xm_r_soh_tmo:   jsr     RDTIM               ; no SOH: resend NAK after 2*256 jiffies
                cpx     #$02
                beq     xm_r_nak_start
                bne     xm_r_wait_soh
xm_r_byte:      lda     #$00                ; jiffy clock = 0
                tax
                tay
                jsr     SETTIM
xm_r_byte_lp:   jsr     CLRCHN
                jsr     xm_check_esc
                jsr     xm_get
                tax
                lda     zp_status
                cmp     #$00
                beq     xm_r_got
                ldy     zp_fa               ; no byte: wait forever between blocks,
                cpy     #$01
                beq     xm_r_byte_lp
                jsr     RDTIM               ; in a block NAK after 256 jiffies
                cpx     #$01
                beq     xm_r_nak
                bne     xm_r_byte_lp
xm_r_got:       txa                         ; first byte of a block:
                ldy     zp_fa
                cpy     #$01
                bne     xm_r_store
                cmp     #XM_SOH             ; SOH
                beq     xm_r_store
                cmp     #XM_CAN             ; CAN
                bne     xm_r_eot
xm_r_can:       lda     #$03
xm_r_exit:      sta     xm_status
                jmp     xm_unwind
xm_r_eot:       cmp     #XM_EOT             ; EOT: send ACK, status 0
                bne     xm_r_junk
                ldx     #LFN_MODEM
                jsr     CHKOUT
                lda     #XM_ACK
                jsr     CHROUT
                jsr     CLRCHN
                lda     #$00
                jmp     xm_r_exit
xm_r_junk:      inc     xm_index            ; junk byte: 255 of them = sync lost
                lda     xm_index
                cmp     #$FF
                bne     xm_r_byte
                lda     #$01
                jmp     xm_r_exit
xm_r_store:     sta     XM_BUF,y
                inc     zp_fa
                lda     zp_fa
                cmp     #$85                ; SOH + 2 + 128 + 1 = 132 bytes
                bne     xm_r_byte
                lda     #$00
                sta     xm_index
                lda     XM_BUF+2            ; block + (255-block) = 255?
                clc
                adc     XM_BUF+3
                cmp     #$FF
                beq     xm_r_hdr_ok
xm_r_nak:       jsr     CLRCHN              ; bad block: ':' and NAK
                lda     xm_bad_char
                jsr     CHROUT
                inc     xm_retry
                lda     xm_retry
                cmp     #$0B
                beq     xm_r_too_many
                lda     #$01
                sta     zp_fa
                jsr     xm_flush
                ldx     #LFN_MODEM
                jsr     CHKOUT
                lda     #XM_NAK
                jsr     CHROUT
                jsr     CLRCHN
                jmp     xm_r_byte
xm_r_too_many:  lda     #$04
                jmp     xm_r_exit
xm_r_hdr_ok:    lda     XM_BUF+2            ; expected block?
                cmp     xm_block
                beq     xm_r_sum
                lda     xm_block            ; previous block (duplicate)?
                sec
                sbc     #$01
                tax
                cpx     XM_BUF+2
                bne     xm_r_chk_wrap
                beq     xm_r_dup
xm_r_chk_wrap:  ldx     XM_BUF+2
                cpx     #$FF
                bne     xm_r_sync_lost
                ldx     xm_block
                cpx     #$00
                beq     xm_r_dup
xm_r_sync_lost: ldx     #LFN_MODEM          ; wrong block: send CAN, status 1
                jsr     CHKOUT
                lda     #XM_CAN
                jsr     CHROUT
                jsr     CLRCHN
                lda     #$01
                jmp     xm_r_exit
xm_r_dup:       jsr     CLRCHN
                lda     #'/'                ; progress: duplicate block
                jsr     CHROUT
                ldx     #LFN_MODEM
                jsr     CHKOUT
                lda     #XM_ACK
                jsr     CHROUT
                jsr     xm_flush
                jsr     CLRCHN
                jmp     xm_r_next
xm_r_sum:       lda     #$00                ; add the 128 data bytes
                sta     xm_sum
                ldy     #$04
xm_r_sum_lp:    lda     xm_sum
                clc
                adc     XM_BUF,y
                and     #$FF
                sta     xm_sum
                iny
                cpy     #$84
                bne     xm_r_sum_lp
                lda     XM_BUF,y
                cmp     xm_sum
                beq     xm_r_write
                jmp     xm_r_nak
xm_r_write:     ldy     #$04                ; good: write data to file #2
xm_r_write_lp:  ldx     #LFN_FILE
                jsr     CHKOUT
                lda     XM_BUF,y
                jsr     CHROUT
                iny
                cpy     #$84
                bne     xm_r_write_lp
                jsr     xm_wait_tx
                jsr     xm_delay
                jsr     xm_wait_tx
                ldx     #LFN_MODEM          ; ACK
                jsr     CHKOUT
                lda     #XM_ACK
                jsr     CHROUT
                jsr     CLRCHN
                inc     xm_block
                lda     xm_good_char
                jsr     CHROUT
xm_r_next:      lda     #$01
                sta     zp_fa
                lda     #$00
                sta     xm_retry
                sta     xm_index
                jmp     xm_r_byte

; =============================================================================
; vdc_write_reg ($2F46)
; -----------------------------------------------------------------------------
; Input   : X = VDC register, A = value.  Waits for VDC ready (status bit 7).
; =============================================================================
vdc_write_reg:  stx     VDC_ADDR
vdc_wait:       bit     VDC_ADDR
                bpl     vdc_wait
                sta     VDC_DATA
                rts

; =============================================================================
; vdc_poke ($2F52)
; -----------------------------------------------------------------------------
; Purpose : write vdc_wr_data to VDC RAM at vdc_wr_addr (R18/R19, R31).
;           ; ? then writes the same value to R18 again (no visible use).
; =============================================================================
vdc_poke:       ldx     #$12
                lda     vdc_wr_addr+1
                jsr     vdc_write_reg
                inx
                lda     vdc_wr_addr
                jsr     vdc_write_reg
                ldx     #$1F
                lda     vdc_wr_data
                jsr     vdc_write_reg
                ldx     #$12
                jmp     vdc_write_reg

; =============================================================================
; ed_keys ($2F6E) / ed_key_loop ($2F7A)
; -----------------------------------------------------------------------------
; Purpose : key loop of the buffer editor.  Reads LSTX (matrix code) and
;           runs the action.  Cursor = attribute address in ed_vaddr
;           (window rows 3-23, attribute RAM $08F0-$0F7F).
;   UP/DOWN/LEFT/RIGHT  move cursor (top-row cursor keys)
;   F1 page down    F3 page up    F5 set block mark    F7 cut mark..cursor
;   DEL delete char at cursor     RETURN insert CR     SPACE insert space
;   ESC exit (RTS)
; =============================================================================
ed_keys:        lda     ed_cursor_lo
                sta     ed_vaddr
                lda     ed_cursor_hi
                sta     ed_vaddr+1
ed_key_loop:    lda     LSTX
                cmp     #KEY_UP
                beq     ed_k_up
                cmp     #KEY_DOWN
                beq     ed_k_down
                cmp     #KEY_LEFT
                beq     ed_k_left
                cmp     #KEY_RIGHT
                beq     ed_k_right
                cmp     #KEY_DEL
                beq     ed_k_del
                cmp     #KEY_F5
                beq     ed_k_f5
                cmp     #KEY_F7
                beq     ed_k_f7
                cmp     #KEY_F1
                beq     ed_k_f1
                cmp     #KEY_F3
                beq     ed_page_up
                cmp     #KEY_ESC
                beq     ed_k_esc
                cmp     #KEY_RETURN
                beq     ed_k_return
                cmp     #KEY_SPACE
                beq     ed_k_space
                jmp     ed_key_loop
ed_k_up:        jsr     ed_key_delay
                jmp     ed_up
ed_k_down:      jsr     ed_key_delay
                jmp     ed_down
ed_k_left:      jsr     ed_key_delay
                jmp     ed_left
ed_k_right:     jsr     ed_key_delay
                jmp     ed_right
ed_k_f1:        jmp     ed_page_down
ed_k_del:       lda     #$01                ; delete 1 character
                sta     zp_fa
                lda     #$00
                sta     zp_fb
                jmp     ed_delete
ed_k_f5:        jmp     ed_mark_set
ed_k_f7:        jmp     ed_cut
ed_k_esc:       rts
ed_k_return:    jmp     ed_ins_cr
ed_k_space:     jmp     ed_ins_space

; =============================================================================
; ed_page_up ($2FE2)  F3
; -----------------------------------------------------------------------------
; Purpose : show the page before the current one (ed_next_page - $0D20,
;           that is two pages of 21*80).  Near the buffer start, show from
;           the start.  ; ? the LSR A instructions have no visible use; the
;           high-byte test uses BPL (signed).
; =============================================================================
ed_page_up:     lsr     a
                sec
                lda     ed_next_page
                sbc     #$20
                sta     zp_capptr
                sta     ed_top
                lda     ed_next_page+1
                sbc     #$0D
                sta     zp_capptr+1
                sta     ed_top+1
                lsr     a
                sec
                lda     ed_top+1
                cmp     #$70
                bpl     ed_redraw
                sec
                sbc     #$04
                beq     ed_pu_start
                bmi     ed_pu_start
                jmp     ed_redraw
ed_pu_start:    jmp     ed_draw_start

; =============================================================================
; ed_page_down ($300E)  F1
; -----------------------------------------------------------------------------
; Purpose : show the next page; near the end of the buffer show the last
;           page; for a short buffer show from $0402.  ; ? exact limits
; ed_redraw ($3049): erase cursor, VDC address = $00EF, draw from zp_capptr.
; =============================================================================
ed_page_down:   clc
                lda     ed_next_page
                adc     #$90
                sta     ed_tmp4
                lda     ed_next_page+1
                adc     #$06
                sec
                cmp     cap_end+1
                bcs     ed_pd_clamp
                beq     ed_pd_cmp_lo
                jmp     ed_pd_draw
ed_pd_cmp_lo:   lda     cap_end
                cmp     ed_tmp4
                bpl     ed_pd_draw
                beq     ed_pd_draw
                jmp     ed_pd_clamp
ed_pd_draw:     sec
                lda     ed_next_page
                sbc     #$02
                sta     zp_capptr
                sta     ed_top
                lda     ed_next_page+1
                sbc     #$00
                sta     zp_capptr+1
                sta     ed_top+1
ed_redraw:      jsr     ed_erase_cursor
                lda     #$00
                sta     ed_vaddr+1
                lda     #$EF
                sta     ed_vaddr
                jmp     ed_draw_loop
ed_pd_clamp:    sec
                lda     cap_end+1
                cmp     #$0A
                beq     ed_pd_cmp_lo2
                bcc     ed_pd_first
                bcs     ed_pd_last
ed_pd_cmp_lo2:  sec
                lda     cap_end
                cmp     #$91
                bcc     ed_pd_first
ed_pd_last:     sec
                lda     cap_end
                sbc     #$8E
                sta     ed_next_page
                lda     cap_end+1
                sbc     #$06
                sta     ed_next_page+1
                jmp     ed_pd_draw
ed_pd_first:    lda     #$02
                sta     ed_next_page
                lda     #$04
                sta     ed_next_page+1
                jmp     ed_pd_draw

; =============================================================================
; ed_erase_cursor ($308E): attribute $87 at ed_vaddr.  Carry clear on exit.
; ed_show_cursor ($30A5): if cursor is past the buffer end, move it to $08F0;
;           then attribute $BB at ed_vaddr and back to the key loop.
; =============================================================================
ed_erase_cursor:
                clc
                lda     ed_vaddr
                sta     vdc_wr_addr
                lda     ed_vaddr+1
                sta     vdc_wr_addr+1
                lda     #$87
                sta     vdc_wr_data
                jsr     vdc_poke
                clc
                rts
ed_show_cursor: clc
                lda     ed_vaddr
                adc     ed_top
                sta     ed_tmp1
                lda     ed_vaddr+1
                adc     ed_top+1
                sta     ed_tmp1+1
                sec
                lda     ed_tmp1
                sbc     #$EE
                sta     ed_tmp1
                lda     ed_tmp1+1
                sbc     #$08
                sta     ed_tmp1+1
                sec
                lda     cap_end+1
                cmp     ed_tmp1+1
                bcc     ed_cursor_home
                bne     ed_draw_cursor
                sec
                lda     cap_end
                cmp     ed_tmp1
                bcs     ed_draw_cursor
ed_cursor_home: lda     #$08
                sta     ed_vaddr+1
                lda     #$F0
                sta     ed_vaddr
ed_draw_cursor: lda     ed_vaddr
                sta     vdc_wr_addr
                lda     ed_vaddr+1
                sta     vdc_wr_addr+1
                lda     #$BB
                sta     vdc_wr_data
                jsr     vdc_poke
                jmp     ed_key_loop

; =============================================================================
; Cursor moves: ed_right +1, ed_left -1, ed_up -80, ed_down +80, with wrap
; inside the window ($08F0-$0F7F).  ; ? the bounds tests are not exact.
; =============================================================================
ed_right:       jsr     ed_erase_cursor
                lda     ed_vaddr
                adc     #$01
                sta     ed_vaddr
                lda     ed_vaddr+1
                adc     #$00
                sta     ed_vaddr+1
                and     #$FF
                cmp     #$0F
                bmi     ed_right_x
                clc
                lda     ed_vaddr
                cmp     #$80
                bne     ed_right_x
                clc
                lda     #$F0
                sta     ed_vaddr
                lda     #$08
                sta     ed_vaddr+1
ed_right_x:     jmp     ed_show_cursor
ed_left:        jsr     ed_erase_cursor
                lda     ed_vaddr
                sec
                sbc     #$01
                sta     ed_vaddr
                lda     ed_vaddr+1
                sbc     #$00
                sta     ed_vaddr+1
                clc
                lda     ed_vaddr
                cmp     #$EF
                bne     ed_left_x
                lda     ed_vaddr+1
                cmp     #$08
                bne     ed_left_x
                clc
                lda     #$7F
                sta     ed_vaddr
                lda     #$0F
                sta     ed_vaddr+1
ed_left_x:      jmp     ed_show_cursor
ed_up:          jsr     ed_erase_cursor
                lda     ed_vaddr
                sec
                sbc     #$50
                sta     ed_vaddr
                lda     ed_vaddr+1
                sbc     #$00
                sta     ed_vaddr+1
                clc
                lda     ed_vaddr+1
                and     #$FF
                cmp     #$09
                bpl     ed_up_x
                clc
                lda     ed_vaddr
                and     #$FF
                cmp     #$EF
                bpl     ed_up_x
                clc
                lda     ed_vaddr
                adc     #$91
                sta     ed_vaddr
                lda     ed_vaddr+1
                adc     #$06
                sta     ed_vaddr+1
ed_up_x:        jmp     ed_show_cursor
ed_down:        jsr     ed_erase_cursor
                lda     ed_vaddr
                adc     #$50
                sta     ed_vaddr
                lda     ed_vaddr+1
                adc     #$00
                sta     ed_vaddr+1
                and     #$FF
                cmp     #$0F
                bne     ed_down_x
                lda     ed_vaddr
                and     #$FF
                clc
                lda     ed_vaddr
                sec
                sbc     #$80
                bcc     ed_down_x
                clc
                adc     #$F1
                sta     ed_vaddr
                lda     #$08
                adc     #$00
                sta     ed_vaddr+1
ed_down_x:      jmp     ed_show_cursor

; =============================================================================
; ed_key_delay ($31D1): wait 20*255 loops, then LSTX = $FF (key repeat).
; =============================================================================
ed_key_delay:   lda     #$00
                sta     ed_delay
                sta     ed_delay+1
ed_kd_loop:     inc     ed_delay
                lda     #$FF
                cmp     ed_delay
                bne     ed_kd_loop
                inc     ed_delay+1
                lda     #$14
                cmp     ed_delay+1
                beq     ed_kd_done
                lda     #$00
                sta     ed_delay
                jmp     ed_kd_loop
ed_kd_done:     lda     #$FF
                sta     LSTX
                rts
ed_out_j:       jmp     ed_out_char

; =============================================================================
; editor ($31FD)   jump table entry $2121
; -----------------------------------------------------------------------------
; Purpose : full-screen viewer/editor for the capture buffer on the VDC
;           (rows 3-23).  Returns at once if the buffer is empty.
;           ed_mode ($2109) selects extra output to file #2 while drawing
;           (see ed_draw_loop).  ; ? no caller sets ed_mode in pc.ml.
; =============================================================================
editor:         lda     #$0C                ; block mark = $0CF1 (buffer $0401)
                sta     ed_mark+1
                lda     #$F1
                sta     ed_mark
                lda     cap_end+1           ; buffer empty (cap_end = $0400)?
                cmp     #$04
                bne     ed_init
                lda     cap_end
                cmp     #$00
                bne     ed_init
                rts
ed_init:        lda     #$08                ; cursor = $08F0 (row 3, column 0)
                sta     ed_cursor_hi
                lda     #$F0
                sta     ed_cursor_lo
ed_draw_start:  lda     #$EF                ; VDC screen address = $00EF (+1 per char)
                sta     ed_vaddr
                lda     #$00
                sta     ed_vaddr+1
                ldx     #LFN_FILE
                jsr     CHKOUT
                lda     #$00
                sta     zp_capptr
                sta     ed_top
                lda     #$04
                sta     zp_capptr+1
                sta     ed_top+1

; -----------------------------------------------------------------------------
; ed_draw_loop ($323D): FETCH a buffer char, change PETSCII to screen code,
; write it to VDC screen RAM.  When the window is full ($0780), or the buffer
; end is reached (rest filled with spaces), go to the key loop.
; ed_mode 1: also print each char to file #2 and page on automatically
;            (F1 logic) when a page is full, so the whole buffer is output.
; ed_mode 2: also print each char to file #2, with case swap.
; ed_mode 3: only print to file #2, no drawing.   ; ? (no setter found)
; -----------------------------------------------------------------------------
ed_draw_loop:   ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     FETVEC
                jsr     FETCH
                sta     ed_char
                jsr     CLRCHN
                lda     ed_mode
                cmp     #$03
                beq     ed_out_j
                lda     ed_char
                cmp     #$20                ; PETSCII -> screen code
                bmi     ed_sc_ctrl
                cmp     #$40
                bmi     ed_draw_put
                cmp     #$60
                bmi     ed_sc_40
                cmp     #$80
                bmi     ed_sc_60
                cmp     #$C0
                bmi     ed_draw_put
                cmp     #$E0
                bmi     ed_sc_c0
ed_draw_put:    sta     vdc_wr_data
                clc
                lda     ed_vaddr
                adc     #$01
                sta     ed_vaddr
                lda     ed_vaddr+1
                adc     #$00
                sta     ed_vaddr+1
                clc
                lda     ed_vaddr
                cmp     #$80                ; window full at $0780?
                bne     ed_draw_poke
                lda     ed_vaddr+1
                cmp     #$07
                bne     ed_draw_poke
                lda     zp_capptr
                sta     ed_next_page
                lda     zp_capptr+1
                sta     ed_next_page+1
                lda     ed_cursor_hi
                sta     ed_vaddr+1
                lda     ed_cursor_lo
                sta     ed_vaddr
                lda     #$BB
                sta     vdc_wr_data
                lda     ed_mode
                cmp     #$01
                beq     ed_draw_full_m1
                jmp     ed_keys
ed_draw_full_m1:
                jmp     ed_page_down
ed_sc_ctrl:     clc                         ; $00-$1F -> +$80 (reverse); CR shown as $9F
                adc     #$80
                cmp     #$8D
                bne     ed_draw_put
                lda     #$9F
                jmp     ed_draw_put
ed_sc_40:       sec
                sbc     #$40
                jmp     ed_draw_put
ed_sc_60:       sec
                sbc     #$20
                jmp     ed_draw_put
ed_sc_c0:       and     #$7F
                jmp     ed_draw_put
ed_draw_poke:   lda     ed_vaddr
                sta     vdc_wr_addr
                lda     ed_vaddr+1
                sta     vdc_wr_addr+1
                jsr     vdc_poke
                lda     ed_mode
                cmp     #$02
                bne     ed_draw_m1_j
                lda     ed_char
                cmp     #$40
                bmi     ed_m2_del
                cmp     #$5B
                bpl     ed_m2_lower
                ora     #$20
                sta     ed_char
                jmp     ed_out_char
ed_m2_lower:    cmp     #$60
                bmi     ed_m2_store
                cmp     #$7B
                bpl     ed_m2_store
                and     #$DF
                jmp     ed_m2_store
ed_m2_del:      cmp     #$14
                bne     ed_m2_store
                lda     #$08
ed_m2_store:    sta     ed_char
                jmp     ed_out_char
ed_draw_m1_j:   jmp     ed_draw_m1
ed_draw_loop_j: jmp     ed_draw_loop
ed_draw_rts:    rts
ed_draw_m1:     lda     ed_mode
                cmp     #$01
                bne     ed_draw_next
ed_out_char:    ldx     #LFN_FILE
                jsr     CHKOUT
                lda     ed_char
                jsr     CHROUT
                lda     LSTX
                cmp     #KEY_ESC
                beq     ed_draw_rts
ed_draw_next:   inc     zp_capptr
                bne     ed_draw_chk_end
                inc     zp_capptr+1
ed_draw_chk_end:
                lda     zp_capptr+1
                cmp     cap_end+1
                bne     ed_draw_loop_j
                lda     zp_capptr
                cmp     cap_end
                bne     ed_draw_loop_j
                clc
                lda     ed_mode
                cmp     #$03
                beq     ed_draw_exit
ed_fill_blank:  lda     #$20
                sta     vdc_wr_data
                inc     ed_vaddr
                lda     ed_vaddr
                clc
                sta     vdc_wr_addr
                cmp     #$00
                bne     ed_fill_poke
                clc
                inc     ed_vaddr+1
                lda     ed_vaddr+1
                sta     vdc_wr_addr+1
ed_fill_poke:   jsr     vdc_poke
                clc
                lda     ed_vaddr
                cmp     #$80
                bne     ed_fill_blank
                lda     ed_vaddr+1
                cmp     #$07
                bne     ed_fill_blank
                lda     zp_capptr
                sta     ed_next_page
                lda     zp_capptr+1
                sta     ed_next_page+1
                lda     ed_mode
                cmp     #$01
                beq     ed_draw_exit
                jmp     ed_keys
ed_draw_exit:   rts

; =============================================================================
; load_conv ($339A)   jump table entry $2124
; -----------------------------------------------------------------------------
; Purpose : append file #2 to the capture buffer until EOF or $E000.  If
;           ld_raw = 0, LF is dropped and ASCII is changed to PETSCII.
; =============================================================================
load_conv:      ldx     #LFN_FILE
                jsr     CHKIN
                lda     cap_end
                sta     zp_capptr
                lda     cap_end+1
                sta     zp_capptr+1
lc_loop:        jsr     CHRIN
                sta     ld_char
                lda     ld_raw
                cmp     #$00
                beq     lc_convert
                lda     ld_char
lc_store:       pha
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     STAVEC
                pla
                jsr     STASH
                inc     zp_capptr
                bne     lc_chk_full
                inc     zp_capptr+1
lc_chk_full:    lda     zp_capptr+1
                cmp     #>CAP_LIMIT
                bne     lc_next
                jmp     lc_exit
lc_next:        lda     #$08
                jsr     READST
                beq     lc_loop
lc_exit:        lda     zp_capptr
                sta     cap_end
                lda     zp_capptr+1
                sta     cap_end+1
                jsr     CLRCHN
                rts
lc_convert:     lda     ld_char
                cmp     #$00
                bne     lc_not0
                jmp     lc_store
lc_not0:        cmp     #$0A
                bne     lc_conv
                jmp     lc_next
lc_conv:        and     #$7F
                cmp     #$40
                bmi     lc_conv2
                cmp     #$5B
                bpl     lc_conv2
                ora     #$80
                jmp     lc_store
lc_conv2:       cmp     #$60
                bmi     lc_store_j
                cmp     #$80
                bpl     lc_conv3
                and     #$DF
lc_store_j:     jmp     lc_store
lc_conv3:       cmp     #$C0                ; ?  not reached: AND #$7F above
                bmi     lc_store_j
                cmp     #$DB
                bpl     lc_store_j
                and     #$7F
                ora     #$20
                jmp     lc_store_j

; =============================================================================
; ed_delete ($3427)  DEL key
; -----------------------------------------------------------------------------
; Purpose : delete the character under the cursor (unless at buffer end),
;           then redraw from the cursor position.
; =============================================================================
ed_delete:      sec
                lda     ed_vaddr
                sbc     #$F0
                sta     zp_capptr
                lda     ed_vaddr+1
                sbc     #$08
                sta     zp_capptr+1
                clc
                lda     ed_top
                adc     zp_capptr
                sta     ed_tmp2
                lda     ed_top+1
                adc     zp_capptr+1
                sta     ed_tmp2+1
                clc
                lda     ed_tmp2
                adc     #$01
                sta     ed_tmp2
                lda     ed_tmp2+1
                adc     #$00
                sta     ed_tmp2+1
                lda     cap_end+1
                cmp     ed_tmp2+1
                bne     ed_del_do
                lda     cap_end
                cmp     ed_tmp2
                bne     ed_del_do
                clc
                lda     ed_next_page
                sta     zp_capptr
                lda     ed_next_page+1
                sta     zp_capptr+1
                jmp     ed_key_loop
ed_del_do:      clc
                lda     ed_top
                adc     zp_capptr
                sta     zp_capptr
                sta     ed_curbuf
                lda     ed_top+1
                adc     zp_capptr+1
                sta     zp_capptr+1
                sta     ed_curbuf+1
                clc
                lda     zp_capptr
                adc     #$01
                sta     zp_capptr
                lda     zp_capptr+1
                adc     #$00
                sta     zp_capptr+1
                jsr     buf_remove
                lda     ed_curbuf
                sta     zp_capptr
                sta     ed_tmp2
                lda     ed_curbuf+1
                sta     zp_capptr+1
                sta     ed_tmp2+1
                sec
                lda     ed_vaddr
                sta     ed_cursor_lo
                lda     ed_vaddr+1
                sta     ed_cursor_hi
                sec
                lda     ed_vaddr
                sbc     #$01
                sta     ed_vaddr
                lda     ed_vaddr+1
                sbc     #$08
                sta     ed_vaddr+1
                clc
                jmp     ed_draw_loop

; =============================================================================
; buf_remove ($34CD)
; -----------------------------------------------------------------------------
; Purpose : remove zp_fa/zp_fb bytes from the capture buffer, ending just
;           before zp_capptr: move every byte from zp_capptr .. cap_end-1 down
;           by the count, then cap_end = cap_end - count.
; Input   : zp_capptr = first byte to keep, zp_fa/zp_fb = count.
; =============================================================================
buf_remove:     clc
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     FETVEC
                jsr     FETCH
                pha
                sec
                lda     zp_capptr
                sta     zp_fc
                sbc     zp_fa
                sta     zp_capptr
                lda     zp_capptr+1
                sta     zp_fd
                sbc     zp_fb
                sta     zp_capptr+1
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     STAVEC
                pla
                jsr     STASH
                clc
                lda     zp_fc
                adc     #$01
                sta     zp_capptr
                lda     zp_fd
                adc     #$00
                sta     zp_capptr+1
                lda     cap_end
                cmp     zp_capptr
                beq     buf_remove_chk
                jmp     buf_remove
buf_remove_chk: lda     cap_end+1
                cmp     zp_capptr+1
                bne     buf_remove
                sec
                lda     cap_end
                sbc     zp_fa
                sta     cap_end
                lda     cap_end+1
                sbc     zp_fb
                sta     cap_end+1
                rts

; =============================================================================
; ed_mark_set ($3529)  F5: block mark = cursor buffer address (+$08F0).
; =============================================================================
ed_mark_set:    clc
                lda     ed_vaddr
                adc     ed_top
                sta     ed_mark
                sta     ed_curbuf
                lda     ed_vaddr+1
                adc     ed_top+1
                sta     ed_mark+1
                sta     ed_curbuf+1
                lda     ed_top
                sta     ed_mark_top
                lda     ed_top+1
                sta     ed_mark_top+1
                jmp     ed_key_loop

; =============================================================================
; ed_cut ($3551)  F7
; -----------------------------------------------------------------------------
; Purpose : delete the text from the block mark up to (not including) the
;           cursor character, if the cursor is after the mark, then redraw.
; =============================================================================
ed_cut:         lda     ed_mark
                sta     ed_tmp2
                lda     ed_mark+1
                sta     ed_tmp2+1
                clc
                lda     ed_vaddr
                adc     ed_top
                sta     ed_tmp3
                lda     ed_vaddr+1
                adc     ed_top+1
                sta     ed_tmp3+1
                lda     ed_tmp3+1
                sec
                cmp     ed_tmp2+1
                bcc     ed_cut_none
                beq     ed_cut_cmp_lo
                jmp     ed_cut_do
ed_cut_cmp_lo:  lda     ed_tmp3
                cmp     ed_tmp2
                bpl     ed_cut_do
ed_cut_none:    jmp     ed_key_loop
ed_cut_do:      sec
                lda     ed_tmp3
                sbc     ed_tmp2
                sta     ed_tmp2
                lda     ed_tmp3+1
                sbc     ed_tmp2+1
                sta     ed_tmp2+1
                sec
                lda     ed_tmp3
                sbc     #$F0
                sta     ed_tmp3
                lda     ed_tmp3+1
                sbc     #$08
                sta     ed_tmp3+1
                lda     ed_tmp3
                sta     zp_capptr
                lda     ed_tmp3+1
                sta     zp_capptr+1
                clc
                lda     ed_tmp2
                sta     zp_fa
                lda     ed_tmp2+1
                sta     zp_fb
                jsr     buf_remove
                sec
                lda     ed_curbuf
                sbc     #$F0
                sta     zp_capptr
                sta     ed_tmp2
                lda     ed_curbuf+1
                sbc     #$08
                sta     zp_capptr+1
                sta     ed_tmp2+1
                lda     #$87
                sta     vdc_wr_data
                jsr     ed_poke_cursor
                sec
                lda     ed_vaddr
                sbc     zp_fa
                sta     ed_vaddr
                lda     ed_vaddr+1
                sbc     zp_fb
                sta     ed_vaddr+1
                lda     #$BB
                sta     vdc_wr_data
                sec
                lda     ed_top+1
                cmp     ed_mark_top+1
                beq     ed_cut_redraw
                lda     #$F0
                sta     ed_vaddr
                lda     #$08
                sta     ed_vaddr+1
ed_cut_redraw:  jsr     ed_poke_cursor
                sec
                lda     ed_vaddr
                sta     ed_cursor_lo
                sbc     #$01
                sta     ed_vaddr
                lda     ed_vaddr+1
                sta     ed_cursor_hi
                sbc     #$08
                sta     ed_vaddr+1
                jmp     ed_draw_loop

; -----------------------------------------------------------------------------
; ed_poke_cursor ($3628): write vdc_wr_data at VDC address ed_vaddr.
; -----------------------------------------------------------------------------
ed_poke_cursor: lda     ed_vaddr
                sta     vdc_wr_addr
                lda     ed_vaddr+1
                sta     vdc_wr_addr+1
                jsr     vdc_poke
                rts

; =============================================================================
; ed_ins_space ($3638) SPACE / ed_ins_cr ($363F) RETURN / ed_insert ($3646)
; -----------------------------------------------------------------------------
; Purpose : insert zp_fe at the cursor: shift the rest of the buffer up by
;           one byte (cap_end + 1), then redraw from the cursor.
; =============================================================================
ed_ins_space:   lda     #$20
                sta     zp_fe
                jmp     ed_insert
ed_ins_cr:      lda     #$0D
                sta     zp_fe
                jmp     ed_insert
ed_insert:      clc
                lda     cap_end
                adc     #$02
                sta     cap_end
                lda     cap_end+1
                adc     #$00
                sta     cap_end+1
                clc
                lda     ed_vaddr
                adc     ed_top
                sta     ed_tmp3
                lda     ed_vaddr+1
                adc     ed_top+1
                sta     ed_tmp3+1
                sec
                lda     ed_tmp3
                sbc     #$F0
                sta     ed_tmp3
                sta     zp_capptr
                lda     ed_tmp3+1
                sbc     #$08
                sta     ed_tmp3+1
                sta     zp_capptr+1
ed_ins_loop:    clc
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     FETVEC
                jsr     FETCH
                pha
                ldx     #MMU_BANK1
                ldy     #$00
                lda     #<zp_capptr
                sta     STAVEC
                lda     zp_fe
                jsr     STASH
                clc
                pla
                sta     zp_fe
                lda     zp_capptr
                adc     #$01
                sta     zp_capptr
                lda     zp_capptr+1
                adc     #$00
                sta     zp_capptr+1
                lda     cap_end
                cmp     zp_capptr
                beq     ed_ins_chk
                jmp     ed_ins_loop
ed_ins_chk:     lda     cap_end+1
                cmp     zp_capptr+1
                bne     ed_ins_loop
                sec
                lda     zp_capptr
                sbc     #$01
                sta     cap_end
                lda     zp_capptr+1
                sbc     #$00
                sta     cap_end+1
                sec
                lda     ed_vaddr
                sta     ed_cursor_lo
                sbc     #$01
                sta     ed_vaddr
                lda     ed_vaddr+1
                sta     ed_cursor_hi
                sbc     #$08
                sta     ed_vaddr+1
                lda     ed_tmp3
                sta     zp_capptr
                lda     ed_tmp3+1
                sta     zp_capptr+1
                jmp     ed_draw_loop

; =============================================================================
; Pad byte (not used by code)
; =============================================================================
pad_end:        .byte   $1A


; end of pc.ml
