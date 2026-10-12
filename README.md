# PC-Term 128 README

PC-Term 128 is a full-featured terminal program for the Commodore 128 computer, providing a wide range of capabilities for connecting to remote systems via a modem. The program is written in BASIC, with several machine language routines to handle performance-critical tasks.

## Main Program (BASIC)

The BASIC portion of PC-Term 128 provides the user interface and high-level control flow. It presents a series of menus for selecting the desired function, such as dialing a number, changing terminal settings, sending and receiving files, and accessing disk commands.

When an option is selected, the corresponding BASIC routine is called. These routines set up the necessary parameters and then call the appropriate machine language routines to perform the low-level tasks.

## Machine Language Routines

The machine language routines are divided into several files. A commented ca65 disassembly of each file, with a memory map and the BASIC callers, is in [disasm/README.md](disasm/README.md). To rebuild the files from the listings and compare them with the originals, run `sh disasm/verify.sh`.

### PC.ML

Loads at $2000. This file contains the Punter (C1) and Xmodem file transfer routines, a disk directory reader for BASIC, and a CHROUT hook that sends output to the RS-232 port. It also holds older buffer tools and a VDC buffer viewer/editor that BASIC does not call.

### PC.ML2

Loads at $0B00. PC.ML2 is the terminal loop. It uses the KERNAL RS-232 driver: it translates and prints received characters, stores them in the capture buffer when capture is on, and sends typed keys to the modem. It returns to BASIC on ALT, HOME, or when the buffer is full.

### PC.ML3

Loads at $0E00. This file provides routines for file and capture-buffer I/O: it shows a file on the screen, loads a file into the capture buffer, and sends the buffer to the printer, the screen or a disk file.

### PC.ML4

Loads at $1300. PC.ML4 contains routines for increasing the disk speed (a fast loader for the 1541). I had to remove this from pcboot to get it to run under the VICE emulator. Note: the pcboot and pcboot.source files in this repository still load it at $1300 and run SYS 4864 before they load pcterm.

### PC.ML5

Loads at $1600. This file is a small VDC helper: it writes VDC registers and prints a string at a fixed screen position. No BASIC line in this repository loads it.

### PC.ML6

Loads at $2A00. PC.ML6 is a memory image (a BSAVE of $2A00-$377F). It holds a terminal and capture loop, a 1571 "no verify" disk patch, and another build of the Punter code from PC.ML. BASIC line 716 would load it at $2000, but that line never runs, so PC-Term does not use this file.

## Operation

When PC-Term 128 is started, it sets up the 80-column screen, finds the disk drives, opens the RS-232 channel, loads the configuration, function keys, phonebook, machine language routines and character set, and sets the baud rate. Then it runs the auto macro (mcr.Auto) if the disk has one, and displays the main menu.

The main menu has these options:

- Wait for Call, Call a Number, Hang-Up and Pick-Up
- Terminal Mode and Direct Connect
- Disk Options (directory, disk commands, file stats, change drive, read file, Comscii/Ascii, file copier)
- Wardialer
- Baud (110 to 2400)
- Download, Upload and Toggle Protocol (Punter or Xmodem)
- Phonebook (call, autodial, change, erase and add numbers, multi-dial, load and save the phonebook)
- Redial
- Macro-Mode
- Configure Menu (dial type, modem, pulse speed, function keys, block size, config file, character set, colors, and modem parameters such as parity, word length, stop bits and handshake)
- Multi-Transfer (Punter only)

When a connection is established, the terminal enters its online mode. In this mode, characters typed on the keyboard are sent to the remote system, and data received from the remote system is displayed on the screen. Duplex and Ascii/Comscii mode are set in this mode. The terminal loop returns to BASIC when ALT or HOME is pressed or when the capture buffer is full. HOME goes back to the main menu. ALT plus a key runs a terminal command, for example duplex, capture buffer, upload, download, pick-up and hang-up (Alt-? shows the list). Other control characters, such as CTRL-C, are not intercepted: they are sent to the remote system.

File transfers are initiated from the menus and are handled by the Punter or Xmodem routines in PC.ML, which send and receive the data through the RS-232 port.

Throughout its operation, PC-Term 128 makes extensive use of the Commodore 128's hardware features, including the 8563 VDC chip for the 80-column screen, CIA 2 (the user port) for the RS-232 port and the modem control lines (carrier, ring and off-hook), the SID chip for tone dialing, and the KERNAL ROM routines for RS-232, disk and keyboard I/O. The KERNAL RS-232 driver uses CIA 2 timer NMIs to send and receive the bits.
