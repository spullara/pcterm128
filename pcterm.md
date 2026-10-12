# PC-Term128: Commodore 128 Terminal Emulator and File Transfer Application

## Overall Description

PC-Term128 is a terminal and file transfer program for the Commodore 128, written in BASIC 7.0 with machine language (ML) helper modules. It runs on the 80-column (VDC) screen. It provides modem control (Hayes and non-Hayes modems), tone and pulse dialing, Punter and Xmodem file transfers, a capture buffer, a macro system, a wardialer, a line-based text editor, phonebook management, disk utilities and a help system. All menus use the "Master Menus" routine at line 26000. The line numbers below are BASIC line numbers in `pcterm.source`.

## Section-by-Section Breakdown

### 1. Initialization and Setup (lines 0-95 and 700-730)
- Line 0: if the PC.ML4 fast loader is active (`PEEK(4906)=67`), it disables it with `SYS 4867` and restarts the program with `RUN 1`
- Lines 1-13: set FAST mode, the 80-column screen and the BASIC memory pointers, and draw the screen frame with the "(C)1987 PC-Soft by Sam Pullara" and "Master Menus(tm)" texts
- Lines 2-50: define the text tables for the settings (parity, word length, stop bits, handshake, duplex, Ascii/Comscii, Tone/Pulse, modem types 1660/1650/1670/Mitey Mo, pulse speeds, Punter/Xmodem)
- Line 26 finds the drives and the printer (line 4170); line 28 clears the capture buffer pointers and flags
- Line 40 opens the RS-232 channel (`OPEN5,2,0`), calls line 700 and installs the PC.ML output hook (`SYS $20BA`)
- Lines 700-730: set the function keys, load `pc.config` and `pc.keys` (line 3675), send the Hayes init string for the 1670 modem, load the phonebook, and load PC.ML ($2000), `pc.ascii` ($1400), the character set (line 4090), PC.ML2 ($0B00) and PC.ML3 ($0E00). Line 716 would load PC.ML6, but it never runs because PC.ML is already loaded
- Lines 60-90: set the baud rate (1200 for the 1670 modem, else 300; timing in line 1900), run the auto macro (line 1800) and play a start-up tune

### 2. Main Menu and Core Functions (lines 95-305)
- Lines 100-120 define the main menu: Wait for Call, Call a Number, Hang-Up, Pick-Up, Terminal Mode, Direct Connect, Disk Options, Wardialer, Baud, Download, Upload, Toggle Protocol, Phonebook, Redial, Macro-Mode, Configure Menu, and Multi-Transfer (shown only when Punter is selected)
- Line 150 sends each choice to its routine; line 155 shows the menu again
- Wait for Call (lines 160-175) watches the ring line of the user port and goes to Direct Connect when the phone rings
- Direct Connect (lines 180-220) waits for the carrier signal; it stops on a key press or, after the "Pause" time, reports "No Answer" and dials again
- When a carrier is found, line 1295 plays a tune and lines 300-305 start Terminal Mode

### 3. Dialing and Phone Management (lines 435-625 and 3235-3380)
- Hang-Up (lines 435-455) and Pick-Up (lines 595-625) for each modem type: by the off-hook line on the user port (CIA 2), or by Hayes commands (`+++`, `ATDT`) for the 1670
- Call a Number (lines 500-590): Hayes modems get `ATDT`/`ATDP` + number; other modems go off hook and dial with SID tone pairs (lines 530-580)
- Pulse dialing (lines 3235-3380) for non-Hayes modems, with four pulse speeds (Lightning, Fast, Normal, Slow)
- Redial (line 1740) dials the last number again

### 4. File Transfer Functions (lines 1999-2274)
- Supports the Punter (C1) and Xmodem protocols; Toggle Protocol (line 1705) switches between them (block size 255 for Punter, 128 for Xmodem)
- Punter upload (lines 2002-2032) reads the file size from the directory, shows the estimated transfer time and calls the Punter code in PC.ML
- Punter download (lines 2042-2050) receives the file type first, then the file
- Xmodem upload (lines 2218-2250) waits for a NAK, sends the file and the EOT handshake; Xmodem download is in lines 2252-2274. Both show the PC.ML result code as a message
- Multi-transfer (lines 2052-2214): a directory reader (`SYS $209F`), a four-column file picker with cursor keys, SPACE to select, R to reverse the selection, and the multi-send and multi-receive loops
- The Multi-Xfer menu (lines 9000-9010) has Multi-Upload, Multi-Download and Send Disk entries

### 5. Terminal Mode and Command Handling (lines 1950-1970, 3740-3945 and 4600-4610)
- Lines 1950-1970 set the function keys, show the status line (Duplex, Mode, Baud, Buffer; lines 1165-1167) and start the terminal loop
- Lines 4600-4610 call the PC.ML2 terminal loop (`SYS 2816`). HOME returns to the main menu; ALT runs a command (lines 3740-3929); a full capture buffer is closed
- ALT commands include duplex, Ascii/Comscii, hex/decimal converters, the SEQ reader, baud change, slow and fast directory, upload, download, capture buffer open/close/clear/size/print/save/load, pick-up, hang-up, autodial by number or name, redial, transfer time, Hayes command, disk command, the editor, protocol toggle, printer memo and a peripheral re-check
- ALT plus a shifted letter sends a control character (line 3916). The help screen (Alt-?) is in lines 1170-1235
- Other control characters, such as CTRL-C, are not intercepted; they are sent to the remote system

### 6. Configuration and Settings (lines 3600-3720 and 5000-5840)
- The Configure Menu (lines 3600-3720) sets the dial type, modem type, pulse speed, function keys (lines 3405-3435), block size (lines 1942-1945), character set and colors (lines 1300-1322), and saves, loads or restores the config files (`pc.config`, `pc.keys`, `pc.char`)
- The Modem Parameters menu (lines 5000-5405) sets the speaker, response mode, pause time, auto answer and echo with Hayes commands, and the parity, word length, stop bits and handshake
- Line 5800 writes the RS-232 command and control register values; line 5500 sends the modem init string
- The baud rate (110 to 2400) is set from the main menu (lines 1900-1940)

### 7. Text Editor (lines 6000-7450)
- Edits the capture buffer, a file on disk or a new file (B/F/N), up to 100 lines of 79 characters
- ESC on an empty line opens the Editor Commands menu: delete lines, edit a line, read or list the workspace, save the file, and quit
- The editor is opened with ALT-E in Terminal Mode; the macro editor also uses it

### 8. Phonebook Management (lines 3000-3230)
- Stores up to 25 entries with a name, number, baud rate (300 or 1200) and mode (Ascii or Comscii)
- Menu options: call, autodial, change, erase and add a number, multi-dial (up to 16 entries dialed in turn until a carrier is found), load, save, phonebook name and restore backup
- The Load PhoneBook, Save PhoneBook and PB Name options jump to lines that are not in the program (2420, 2435, 2445)

### 9. Disk Operations (lines 4000-4165, 4500-4520, 4800-4875 and 10000-10060)
- The Disk Options menu has Directory, Disk Commands (lines 900-920), Stats of a File (load address, end address and size), Change Drive, Read File (shows a file with PC.ML3), Comscii/Ascii (lines 10000-10060, converts the case of a SEQ file into a new file) and File Copier
- The File Copier (lines 4800-4875) lists the directory, copies a file through the capture buffer with a disk swap, and scratches files
- Change Drive jumps to line 2480, which is not in the program
- Lines 750-895 hold a directory lister that writes to the screen and the modem (ALT-7)

### 10. Help System (lines 4700-4795)
- Opened with ESC from any Master Menu; it is not context-sensitive
- Lists the subjects from the `pc.Doc Index` file; the user types a subject name, and the program shows that record range from the relative file `pc.doc` (drive 8 only)

### 11. Master Menu System (lines 26000-26220)
- A reusable menu routine used throughout the application; REM lines 26000-26013 document its input and output variables
- Draws the options as a boxed list (a., b., c., ...) at column `tb%`
- The user selects with the option letter, the cursor keys and RETURN, or a joystick in port 2; ESC opens the help system

### 12. Macro Mode (lines 1490-1810)
- Loads, saves, creates (with the editor), lists, appends, deletes and runs macros, stored as `mcr.<name>` files
- Macro commands: `c-` dial a number, `p-` send text, `d-` download, `u-` upload, `b-` set baud, `s-` wait until a time, `bo`/`bc` capture on/off, `xx` hang up and stop
- Lines 1800-1810 run the `mcr.Auto` macro at start-up if it is on the disk

### 13. Wardialer (lines 1000-1065)
- Dials a range of numbers (area code, start and end number) and records each number that answers with a carrier
- Shows the list of carrier numbers at the end; ESC stops the scan

### 14. Peripherals and Character Sets (lines 4090-4220)
- Lines 4170-4220 find the active drives (devices 8-13) and the printer (device 4)
- Lines 4090-4140 load a character set file (`pc.char N`) and copy it into the VDC with a small ML routine that calls the KERNAL DLCHR routine; if the set is missing, the user can list the available sets

## Technical Notes

The application is divided into clearly defined sections for different functions. It makes extensive use of BASIC's GOTO and GOSUB statements for flow control, which was common for BASIC programs of this era. It uses C128 hardware directly: the VDC for the 80-column screen, CIA 2 (the user port) for the RS-232 port and the modem lines (carrier, ring and off-hook), and the SID chip for tone dialing.

The ML modules (see `disasm/README.md`):
- **PC.ML** ($2000): Punter and Xmodem transfers, the directory reader and the RS-232 output hook
- **PC.ML2** ($0B00): the terminal loop
- **PC.ML3** ($0E00): file and capture-buffer I/O (show a file, load a file into the buffer, send the buffer to the printer, screen or disk)
- **PC.ML4** ($1300): the 1541 fast loader, loaded by `pcboot`
- **PC.ML5** and **PC.ML6** are not loaded by any line that runs

Incomplete parts of the program:
- Some GOTO/GOSUB targets are not in the program: 2045, 2095, 2420, 2435, 2445, 2455, 2480, 2685, 3925, 3930 and 3933. The affected functions include macro `d-` and `p-` commands, See Buffer, the phonebook load/save/name options, Change Drive, saving the capture buffer and sending the buffer to the modem.
- The Multi-Xfer menu targets do not match the labels: Multi-Upload (line 2064) only prints the picker header, Multi-Download (line 2142) runs the multi-send, and Send Disk (line 2034) sends every file on the disk. No menu reaches the multi-receive loop (line 2188).
- The upload file-type prompt asks for P, S or U, but line 2012 accepts "w" for user files.
- Line 40000 is only a comment about VT-102 screen handling; the program has no VT-102 code.
