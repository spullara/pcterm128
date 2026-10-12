# Commodore 128 Terminal Program Pseudocode

All line numbers are BASIC line numbers in `pcterm.source`. The program uses the 80-column (VDC) screen.

## Boot Check (Line 0)
- If PEEK(4906)=67 (the pc.ml4 fast loader is active), SYS 4867 turns it off and the program restarts with RUN 1

## Setup and Initialization (Lines 1-27)
- FAST mode, 80-column screen and window, top of BASIC memory, colors
- Define the name strings for parity, word length, stop bits, echo and handshake
- Draw the title screen frame with "(PC-Term128)" and the copyright lines
- Define more variables and arrays (transfer type names, menu and phonebook arrays)
- Check for disk drives 8-13 and a printer (GOSUB 4170)

## Start-up and Main Menu (Lines 28-155)
- Reset the capture buffer pointers and flags
- Define the option name strings (duplex, mode, dial type, modem types, pulse speed, protocol)
- Open the RS-232 channel (file 5) and run the start-up loader (GOSUB 700)
- SYS $20BA installs the pc.ml RS-232 output hook
- Set the baud rate (GOSUB 1900) and reset VDC registers
- Run the auto macro (GOSUB 1800) and play a short tune
- Main menu (lines 100-120): Wait for Call, Call a Number, Hang-Up, Pick-Up, Terminal Mode, Direct Connect, Disk Options, Wardialer, Baud, Download, Upload, Toggle Protocol, Phonebook, Redial, Macro-Mode, Configure Menu, and Multi-Transfer (Punter only)
- Show the menu with the Master Menu routine (GOSUB 26000) and GOSUB to the selected routine (line 150)

## Wait for Call and Direct Connect (Lines 160-220)
- Wait for call: wait until the modem ring line is active, or a key aborts
- Direct Connect: wait for carrier, with a timeout ("No Answer") and key abort
- Does not answer the call itself; when carrier is found, plays the connect tune and enters terminal mode

## Enter Terminal Mode (Lines 300-305)
- Return at once if called from a macro
- After Wait for Call, try to send the capture buffer (GOSUB 3933, a line that is not in the program)
- Go to the terminal start at line 1950

## Hang-Up, Dialing and Pick-Up (Lines 435-625)
- Hang-up (435-455): drop the off-hook line, or send "+++" to a Hayes modem
- Call a Number (500-590): ask for the number; Hayes modem: send ATD; other modems: go off-hook and play DTMF tones through the SID chip; pulse dialing goes to line 3235
- Pick-up (595-625): set the off-hook line, or send ATDT to a Hayes modem

## Start-up Loader (Lines 700-730)
- Assign function keys, load the config file (GOSUB 3675), send the modem init string
- Load the phonebook file
- BLOAD pc.ml, pc.ascii, pc.ml2 and pc.ml3 if they are not in memory; load the character set (GOSUB 4090)
- Line 716 (BLOAD pc.ml6) never runs, because line 715 loads pc.ml first

## Directory Listing (Lines 735-895)
- Lines 735-745: reset the function keys and END (no caller)
- Lines 750-895: read the disk directory and print it to the screen and to the modem (terminal Alt-7 "Slow Dir")

## Disk Command (Lines 900-920)
- Send a command to the disk drive and show the drive status

## Wardialer (Lines 1000-1065)
- Ask for area code, start and end number
- Dial each number, wait for carrier, and list the numbers that answered with carrier

## Screen Output, Status Line and Help (Lines 1145-1235)
- Print text to the screen and to the modem
- Draw the terminal status line (duplex, mode, baud, buffer)
- Help screen with the list of Alt-key terminal commands

## Utility Routines (Lines 1260-1340)
- Save the program over itself (1270-1275, no caller)
- Connect tune and screen flash
- Set background and foreground colors (Configure Menu)
- Show a message in the status box at the bottom of the screen

## Macro Functions (Lines 1490-1755)
- Macro menu: load, save, create (in the text editor), destroy, execute, list, append and delete macro files ("mcr." prefix); clear buffer
- Macro commands: "c-" dial, "p-" send text, "xx" hang up and stop, "bo"/"bc" open/close capture, "d-" download, "u-" upload, "b-" set baud, "s-" wait for a time
- "p-" calls line 2685 and "See Buffer" goes to line 2455; these lines are not in the program
- Also here: toggle protocol (1705), toggle dial type (1710), redial (1740)

## Auto Macro, Baud Rate and Terminal Start (Lines 1800-1970)
- Load and execute the "mcr.Auto" macro at start-up, if the file exists
- Set the baud rate timer values (1900-1925); baud rate input (1930-1940); block size input (1942-1945)
- Terminal start (1950-1970): assign function keys, show the "[HOME] for Menu" line and go to the terminal loop at line 4600

## File Transfer Routines (Lines 2000-2274)
- Punter upload and download through pc.ml (SYS $20A5-$20B7)
- Xmodem upload and download through pc.ml (SYS xc and xc+4), with status messages
- Shows file size and estimated transfer time
- Multi-send: select files from the directory and send them one after another; "Send Disk" sends all files
- Multi-receive (2188-2214) has no caller

## Toggle Duplex and Mode (Lines 2615-2640)
- Toggle full/half duplex and Ascii/Comscii mode

## Phonebook (Lines 3000-3230)
- Phonebook menu: call, autodialer, change, erase, add entries (up to 25), multi-dial, restore backup
- Load PhoneBook, Save PhoneBook and PB Name go to lines 2420, 2435 and 2445, which are not in the program
- Multi-dial: dial up to 16 selected entries until one connects

## Pulse Dialing (Lines 3235-3380)
- Pulse dialing by switching the off-hook line, with speed set by the pulse setting

## Miscellaneous Routines (Lines 3385-3560)
- Send a file to the modem through the pc.ascii table (terminal Alt-5)
- Function key editor; pulse speed cycle
- Line input routine (3490-3540), used by all prompts and by the editor
- Restore the config or phonebook backup file

## Configuration Menu (Lines 3600-3720)
- Configuration menu
- Dial type, modem type, pulse speed, function keys, block size, save/load config, character set, colors, modem parameters, restore backup

## Terminal Commands (Lines 3740-3945)
- Run the Alt-key command the user typed in terminal mode
- Duplex, mode, upload, download, capture buffer (open, close, clear, size, print, save, load), pick-up, hang-up, autodial, redial, transfer time, hex/decimal, Hayes command, disk command, directory, editor, help
- Alt-Shift-letter sends a control character
- Some branches use lines 3925, 3930 and 3933, which are not in the program

## Disk Functions (Lines 4000-4220)
- Disk options menu: directory, disk commands, file statistics, change drive, read file, Comscii/Ascii conversion, file copier
- "Change Drive" goes to line 2480, which is not in the program
- Load a character set file and install it with a small ML routine (DATA lines 4115-4125)
- Check for drives and printer (4170-4220)

## Read File and Terminal Loop (Lines 4500-4610)
- Read file: show a file on the screen (SYS 3584, pc.ml3)
- Terminal loop (4600-4610): SYS 2816 (pc.ml2); on return, handle full buffer, HOME (menu) or an Alt-key command (GOSUB 3740)

## Help Viewer (Lines 4700-4795)
- Show the subjects in "pc.Doc Index" and read the selected text from "pc.doc"
- Opened with ESC in any menu

## File Copier (Lines 4800-4875)
- Directory, copy a file through the capture buffer (SYS 3587 and SYS 3707, pc.ml3), scratch a file

## Modem Parameter Menu (Lines 5000-5840)
- Modem parameter menu
- Speaker, response, pause before disconnect, auto answer, echo, parity, word length, stop bits, handshake
- Send the modem init string (5500-5510)
- Set the RS-232 command and control registers (5800-5840)

## Text Editor (Lines 6000-7450)
- Simple line editor for the buffer, a disk file or a new file (up to 100 lines)
- Editor commands: delete lines, edit line, read, list, save file, quit

## Utility Routines (Lines 8000-10060)
- Line 8000: print a string at a screen position through pc.ml5 (SYS $1627); no caller, and pc.ml5 is not loaded
- Multi-Transfer menu (9000-9010)
  - Multi-Upload, Multi-Download, Send Disk
  - The menu labels do not match the targets: "Multi-Download" runs the multi-send at line 2142, and "Multi-Upload" only reaches the RETURN at line 2068
- Comscii/Ascii conversion routine (10000-10060)
  - Reads one SEQ file and writes a second file
  - Swaps upper and lower case letters and changes LF to CHR$(0)

## Menu Routines (Lines 26000-26220)
- Master Menu routine
  - Displays a menu of options based on passed string array
  - Allows selection with cursor up/down and RETURN, the item letter, or a joystick in port 2
  - ESC opens the help viewer
  - Returns user selection in the 'a' variable
  - Heavy use of cursor control characters for drawing the menu

## Comment (Line 40000)
- A comment line only: "subroutine defining vt-102 screen handling variables & functions"; there is no VT-102 code in the program
