# PC-Term 128 README

PC-Term 128 is a full-featured terminal program for the Commodore 128 computer, providing a wide range of capabilities for connecting to remote systems via a modem. The program is written in BASIC, with several machine language routines to handle performance-critical tasks.

## Main Program (BASIC)

The BASIC portion of PC-Term 128 provides the user interface and high-level control flow. It presents a series of menus for selecting the desired function, such as dialing a number, changing terminal settings, sending and receiving files, and accessing disk commands.

When an option is selected, the corresponding BASIC routine is called. These routines set up the necessary parameters and then call the appropriate machine language routines to perform the low-level tasks.

## Machine Language Routines

The machine language routines are divided into several files, each handling a specific aspect of the terminal's operation:

### PC.ML

This file contains routines for initializing the hardware and software state, checking for the presence of expansion devices, and handling the transfer of data between the computer and the modem.

### PC.ML2

PC.ML2 handles the low-level serial communication with the modem. It includes routines for sending and receiving individual bytes, as well as for handling special control characters and escape sequences.

### PC.ML3

This file provides routines for managing the disk drive, including loading and saving files, and for displaying disk directory listings.

### PC.ML4

PC.ML4 contains routines for the user interface, such as displaying menus, getting user input, and updating the screen.

### PC.ML5

This file handles the Punter and Xmodem file transfer protocols, including the logic for sending and receiving data packets, handling errors, and updating the progress display.

### PC.ML6

PC.ML6 is the main program loop and message handling routine. It constantly checks for various events (carrier detect, keyboard input, incoming data, etc.) and dispatches to the appropriate handling routines.

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

File transfers are initiated from the menus and are handled by the Punter or Xmodem routines in PC.ML5, in conjunction with the low-level routines in PC.ML2 for actually sending and receiving the data.

Throughout its operation, PC-Term 128 makes extensive use of the Commodore 128's hardware features, including the VIC-II chip for screen handling, the CIA chips for RS-232 serial communication and timing, and the KERNAL ROM routines for disk and keyboard I/O.
