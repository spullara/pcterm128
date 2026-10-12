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
