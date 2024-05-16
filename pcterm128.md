# Commodore 128 Terminal Program Pseudocode

## Setup and Initialization (Lines 1-27)
- Set up graphics mode, colors, and define some string variables 
- Define more string and array variables
- Set up modem and communication parameters
- Load phonebook data

## Main Program Loop (Lines 28-155)
- Initialize memory pointers and buffers
- Display title screen with ASCII art borders
- Display main menu
- Wait for user selection and GOSUB to appropriate routine based on selection

## Wait for Call (Lines 160-220)
- Wait for call routine
- Answers incoming call and establishes connection

## Terminal Mode (Lines 300-890)
- Terminal mode
- Handles duplex, capture buffer, protocol transfers, dialing, etc.

## Disk Command Mode (Lines 900-1170)
- Disk command mode
- Allows sending disk commands to drive

## Utility Routines (Lines 1260-1335)
- Utility routines for screen updates

## Macro Functions (Lines 1500-1755)
- Macro functions
- Allows recording and playback of command sequences

## Auto-Execute and Function Keys (Lines 1800-1965)
- Auto-execute macro on startup
- Assigns function keys
- Enters terminal mode

## File Transfer Routines (Lines 2000-2274)
- File transfer routines
- Supports Xmodem protocol uploads and downloads

## Toggle Duplex and Char Set (Lines 2615-2640)
- Toggle duplex and Commodore/ASCII char set

## Phonebook (Lines 3000-3550)
- Phonebook
- Add/edit/delete entries
- Auto-dialer

## Configuration Menu (Lines 3600-3720)
- Configuration menu
- Set various parameters like modem type, font, colors, function keys

## Disk Functions (Lines 4000-4825)
- Disk functions
- Directory, rename, scratch, view files

## Modem Parameter Menu (Lines 5000-5840)
- Modem parameter menu
- Set baud rate, parity, stop bits, etc and send init string

## Text Editor (Lines 6000-7450)
- Simple text editor

## Utility Routines (Lines 8000-10060)
- Single line routine to store a string in memory at a specific screen location
- Multi-Transfer menu
  - Allows selecting multi-upload, multi-download, send disk
- ASCII/PETSCII conversion routine
  - Translates a file from PETSCII to ASCII or vice versa
  - Reads from one file and writes the translated characters to a second file

## Menu Routines (Lines 26000-26220)
- Master Menu routine
  - Displays a menu of options based on passed string array
  - Allows selection with arrow keys, numeric keys or joystick
  - Returns user selection in the 'a' variable
  - Heavy use of cursor control characters for drawing the menu

