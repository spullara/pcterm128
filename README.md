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

Loads at $1300. PC.ML4 contains routines for increasing the disk speed (a fast loader for the 1541). I had to remove this from pcboot to get it to run under the VICE emulator.

### PC.ML5

Loads at $1600. This file is a small VDC helper: it writes VDC registers and prints a string at a fixed screen position. No BASIC line in this repository loads it.

### PC.ML6

Loads at $2A00. PC.ML6 is a memory image (a BSAVE of $2A00-$377F). It holds a terminal and capture loop, a 1571 "no verify" disk patch, and another build of the Punter code from PC.ML. BASIC line 716 would load it at $2000, but that line never runs, so PC-Term does not use this file.

## Operation

When PC-Term 128 is started, it initializes the hardware and software state, loads the necessary machine language routines, and displays the main menu.

From the main menu, the user can select various operations:

- Dialing a number from the phonebook
- Manually dialing a number
- Changing terminal settings (baud rate, parity, duplex, etc)
- Sending and receiving files using Punter or Xmodem protocols
- Accessing disk commands (directory, send, receive, etc)
- Hanging up the modem

When a connection is established, the terminal enters its online mode. In this mode, characters typed on the keyboard are sent to the remote system, and data received from the remote system is displayed on the screen. Special control characters (like CTRL-C for breaking the connection) are intercepted and handled by the terminal software.

File transfers are initiated from the menus and are handled by the Punter or Xmodem routines in PC.ML, which send and receive the data through the RS-232 port.

Throughout its operation, PC-Term 128 makes extensive use of the Commodore 128's hardware features, including the VIC-II chip for screen handling, the CIA chips for RS-232 serial communication and timing, and the KERNAL ROM routines for disk and keyboard I/O.
