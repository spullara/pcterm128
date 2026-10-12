# PC-Term 128 ML disassembly

Each section below is written by a different task.

<!-- BEGIN section: small ML files (pc.ml2, pc.ml3, pc.ml4, pc.ml5) -->
## Small ML files: pc.ml2, pc.ml3, pc.ml4, pc.ml5

Syntax: ca65 (cc65 2.19). Every .s file writes its own 2-byte load address
(`.word`) and uses `.org`, so `ld65 -t none` makes the PRG file. To rebuild
and compare all listings with the original files:

    sh disasm/verify.sh            # all disasm/*.s
    sh disasm/verify.sh pc.ml4.s   # one file

`verify.sh` uses `disasm/<name>.cfg` with `ld65 -C` if that file exists.
Comments marked `; ?` are uncertain.

### Memory map

| File | Load | Size (code) | Entry points | BASIC caller |
|------|------|-------------|--------------|--------------|
| pc.ml2 | $0B00-$0BA4 | 165 | $0B00 TermLoop | pcterm 727 BLOAD; 4600 `SYS2816` |
| pc.ml3 | $0E00-$0EC7 | 200 | $0E00 ShowFile, $0E03 LoadBuffer, $0E29 ClearLoad, $0E7B SendBuffer | pcterm 728 BLOAD; `SYS3584` (4510), `SYS3587` (3935, 4845), `SYS3707` (3780, 3785, 4860); $0E29 has no caller |
| pc.ml4 | $1300-$16D0 | 977 | $1300 Enable, $1303 Disable, $135C TurboLoad (via ILOAD) | pcboot 1031 BLOAD + `sys4864`; pcterm 0 `sys4867` if PEEK(4906)=67 |
| pc.ml5 | $1600-$1679 | 122 | $1600 VdcWrite, $160B VdcReset, $1627 PrintAt | pcterm 8000 `SYSDEC("1627")`; no BLOAD found |

Shared data used by pc.ml2/pc.ml3: $0BFC duplex (POKE3068), $0BFD
character mode (POKE3069), $0BFE buffer full = $FF (3070), $0BFF capture on
(3071); capture buffer in bank 1 from $8000, end pointer in $FA/$FB;
translation table pc.ascii at $1400.

### Summaries (these correct the top-level README.md)

- **pc.ml2 - terminal loop.** Not a serial driver. It uses the KERNAL
  RS-232 driver through logical file 5. Each pass: a received byte is
  translated through the $1400 table (unless character mode = 1), stored in
  the capture buffer if capture is on, and printed; a typed key is
  translated, sent to the modem, and echoed in half duplex. LF and $8E from
  the modem are dropped. Returns to BASIC on ALT, HOME, or buffer full.
- **pc.ml3 - file and capture-buffer I/O.** Not a directory or load/save
  module. Uses logical file 1, opened by BASIC: ShowFile types a file on the
  screen; LoadBuffer appends a file to the capture buffer; SendBuffer writes
  the buffer to the printer, screen or a disk file. ESC stops each one.
- **pc.ml4 - "C128 TURBODISK" fast loader** (the README is right: it speeds
  up disk LOAD). Enable hooks the ILOAD vector ($0330). TurboLoad uploads
  512 bytes of 1541 drive code with M-W, starts it with "UC", and receives
  sectors with a 2-bit protocol over CLK/DATA. The drive code finds the
  PRG in the directory ("*" and "?" wildcards) and reads sectors with its
  own GCR loop. Verify and `LOAD"$"` use the normal KERNAL LOAD.
- **pc.ml5 - VDC / print helper.** Not Punter or Xmodem. Has a VDC register
  write routine, a routine that clears VDC address $0000, and PrintAt, which
  puts a BASIC string at a fixed screen address without moving the cursor
  (pcterm line 8000). It uses $1600-$1679, which is also part of pc.ml4's
  drive-code image, and no BASIC line in this repo loads it.
<!-- END section: small ML files -->

<!-- BEGIN section: pc.ml6 -->
## pc.ml6 (memory image $2A00-$377F)

Listing: `disasm/pc.ml6.s` (ca65, rebuild with `sh disasm/verify.sh pc.ml6.s`).
Comments marked `; ?` are uncertain.

### Load address: $2A00 is correct

The PRG header says $2A00. pcterm line 716 has
`BLOAD"pc.ml6",b0,p8192:u(dv%(dv)):SYSDEC("2f00"):SYSDEC("2000")`, and
`p8192` would load the file at $2000. The code shows that $2A00 is right:

- All absolute self-references fit $2A00 only: `STA $2A44`, `CMP $2A45,Y`,
  `JMP $2A30`, the jump table at $2AF0 (`JMP $2AFF/$2C9F/$2BDF/$2EA1/$2E6A`),
  `LDA $2D20,X`, `JSR $2F86`, `LDA $2F99,Y`, the Punter table at $3000
  (`JMP $301B/$35A1/$3695`), the self-modified `JMP` built from `#$33/#$30`
  (= $3033), and the BSOUT hook vector `#$BA/#$36` (= $36BA).
- `SYS $2F00` hits `JSR CLALL` at $2F00, the first instruction of a complete
  routine (the 1571 patch), only when the file is at $2A00. At $2000 the
  file would end at $2D7F.
- At $2000 the file would overwrite the pc.ml jump table ($2093-$20F4)
  that BASIC calls (`SYS $209F`...`$20BA`, `SYSxc` with xc=8429).

Line 716 does not run in practice: line 715 loads pc.ml first, and pc.ml has
the value 6 at $2328 (= 9000), so `PEEK(9000)<>6` is false. Also
`:u(dv%(dv))` is a separate statement (a ?SYNTAX ERROR); the `u` was meant
as a BLOAD parameter. `SYS $2000` has no target in this file.

### Memory map

| Range | Content | Entry points |
|-------|---------|--------------|
| $2A00-$2A81 | PrintBuf: print a $00-ended text from a bank to file 4; control-code table (filter skipped by a patch JMP) | $2A00 |
| $2A82-$2AEF | stale old code (data), except $2AC0-$2ACB CapStore (live) | - |
| $2AF0-$2D1F | jump table, terminal loop (file 5), ESC commands, capture to bank 1 $1000-$FDFF, status line, cursor | $2AF0 Terminal, $2AF3 Cursor, $2AF6 CaptureZero, $2AF9 SendBuf, $2AFC LoadBuf |
| $2D20-$2E69 | status texts, ASCII->PETSCII and PETSCII->ASCII tables (close to the pc.ascii data), hot-key table | - |
| $2E6A-$2EDC | LoadBuf / SendBuf (file 8), background colour by CTRL-B | - |
| $2EDD-$2EFF | RAM fill pattern (not used) | - |
| $2F00-$2FC0 | DiskPatch: 1571 "no verify" patch; 37 bytes of drive code sent with M-W to $0103 and started with M-E $011C | $2F00 (pcterm 716) |
| $2FC1-$2FFF | fill pattern, terminal variables $2FF0-$2FF5, stale bytes | - |
| $3000-$3736 | Punter C1 file transfer + RS-232 BSOUT hook (another build of pc.ml $20A2-$2814) | $3000/$3003/$3006/$3009/$300C/$300F, $3015, $3018 |
| $3737-$377F | fill bytes (not used) | - |

Outside the file the Punter code uses $3800-$381E (work area), $3900-$3AFF
(two block buffers) and $3B00-$3B03 (baud value, old BSOUT vector).

### Summary (corrects the top-level README.md)

- **Not the main program loop of PC-Term.** pc.ml6 is a BSAVE of memory
  $2A00-$377F: a mix of live routines, an older copy of the Punter code and
  stale bytes. No BASIC line uses it, except dead line 716.
- **Terminal part ($2A00-$2EDC):** a terminal loop with ASCII/graphics
  translation, a 60928-byte capture buffer in bank 1 with a status line
  (OPEN/CLOS/FULL/ZEROED, free bytes), XOFF when the buffer is full,
  ESC commands (O, C, Z, A, G, CLR) and hot keys that return to the caller.
  Three translation steps are skipped by patch `JMP`s.
- **DiskPatch ($2F00):** for a 1571 (fast serial) drive it resets the drive
  ("UJ"), uploads code that changes VERIFY jobs ($A0) into SEEK jobs ($B0),
  and starts it. This makes saves faster. The drive vector ($02A9) and ROM
  address ($9DDF) are not checked against a 1571 ROM.
- **Punter part ($3000-$3736):** the same routines as pc.ml (WaitCode,
  RecvFile, SendFile, RecvType, SendType, DumbTerm, WaitTx, HookBsout),
  assembled for $3000. Differences besides the addresses: 7 dispatcher
  entries (pc.ml has 11), another timeout value, the C= key as abort key,
  and buffers at $3900/$3A00.
<!-- END section: pc.ml6 -->

<!-- BEGIN section: pc.ml -->
## pc.ml (main ML module, $2000-$36EF)

Source: `disasm/pc.ml.s` (ca65; `.word` load address + `.org`, so
`ld65 -t none` works). Check: `sh disasm/verify.sh pc.ml.s`.
Comments marked `; ?` are uncertain.

### Memory map

| Address | Contents | BASIC caller |
|---------|----------|--------------|
| $2000-$2035 | variables: Punter state, `$201B` block size, `$201E` file type, `$202A/B` baud timer, `$202E/F` capture end | POKE `201b`, POKE/PEEK `201e`, POKE `202a`/`202b` (1905) |
| $2036-$2092 | three 31-byte macro slots (`JSR PRIMM`, text, `JMP $3743` ?) for C= 1/2/3 | - |
| $2093-$20A1 | jump table: terminal, type file, send buffer, load buffer, read dir | `SYSDEC("209f")` (2058) only |
| $20A5/$20A8/$20AB/$20AE | Punter: receive file / send file / receive type / send type | 2050, 2214 / 2024, 2176 / 2046, 2212 / 2022, 2172 |
| $20B7 | wait until RS-232 transmit is idle | before each Punter call |
| $20BA | install CHROUT hook (IBSOUT $0326 -> $2798) | 40 |
| $20ED / $20F1 | XMODEM send / receive (`xc`=8429); status at $20F5 (`xc+8`) | 2224 `SYSxc` / 2264 `SYSxc+4` |
| $20F5-$2120 | variables: XMODEM, VDC editor | PEEK/POKE `xc+8` |
| $2121 / $2124 | VDC buffer viewer/editor / load file into buffer with ASCII conversion | - |
| $2127-$2135 | Punter codes `GOOBADACKS/BSYN` | - |
| $2328 | operand of `LDY #6`; BASIC uses PEEK(9000)=6 as "pc.ml loaded" | 715, 716 |

Buffers outside the module: capture buffer in bank 1 $0400-$DFFF (FETCH/STASH,
MMU $7F); Punter blocks at $0500/$0600 and the XMODEM block at $0450-$04D4
(40-column screen RAM); result byte for BASIC at $0200 (`PEEK(512)=1` = ESC).

### Summary (corrects the top-level README.md)

pc.ml is **not** an init/expansion-check module. It holds the file transfer
code and some buffer tools:

- **Punter (C1) protocol** ($2136-$2680): send and receive files and the
  one-block "file type" transfer, with GOO/BAD/ACK/S/B/SYN handshakes,
  two 256-byte block buffers, 4-byte checksum, progress characters
  `-` `:` `*`. ESC aborts at once (stack unwind to the SYS level).
- **XMODEM checksum** ($2BAB-$2F45): 128-byte blocks, NAK start, 10 retries,
  `$1A` padding; result codes 0-4 in $20F5 used by BASIC lines 2224-2272.
- **CHROUT hook** ($2773-$2814): own RS-232 output that starts the CIA2
  timer with the baud value from $202A/$202B.
- **Directory reader** ($2A90): fills BASIC `A$` (found in the bank 1
  variable table) with `name,P`/`name,S` padded to 18 chars per call.
- **Older tools with no BASIC caller** (; ? probably replaced by pc.ml2,
  pc.ml3, pc.ml6): a terminal with capture to bank 1 ($2815), buffer
  send/print with echo wait ($295E), file type/load to buffer, a small
  ASCII "chat" terminal, and a VDC full-screen buffer viewer/editor
  ($2F46-$36EE) with cursor keys, page up/down, delete, insert, block cut.
- Open questions: the macro slots jump to $3743 (outside pc.ml); BASIC line
  716 loads pc.ml6 with `p8192` ($2000), on top of pc.ml.
<!-- END section: pc.ml -->
