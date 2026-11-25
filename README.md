# Digital Clock and Stopwatch in x86 Assembly

A console-based **digital clock and stopwatch** written entirely in 32-bit x86 assembly language (MASM) using the **Irvine32** library.

The program starts as a live 12-hour clock. Press **S** and it switches to a stopwatch with lap recording, while a smaller clock keeps running on screen.

> Course project for **Computer Organization and Assembly Language (COAL)**.

---

## Features

- **Live digital clock** in 12-hour format with AM/PM (`08:53:29 PM`)
- **Stopwatch** with hundredths of a second (`MM:SS.CC`)
- **Start / stop / resume** with a single key
- **Lap recording** that shows the 5 most recent laps, newest first
- **Reset** that returns to the clock screen
- **Small live clock** that stays visible while the stopwatch is running
- **Colored text interface** with a box-drawn frame and a status line (CLOCK / RUNNING / STOPPED)
- **Fixed window size** (42 x 20) and **automatic redraw** if the console is resized
- **Drift-free timing** based on the system millisecond timer, including correct handling of midnight

## Controls

| Key | Action |
|---|---|
| `S` | Start the stopwatch (from clock mode), then stop / resume |
| `L` | Record a lap (only while the stopwatch is running) |
| `R` | Reset the stopwatch and return to the clock (only while stopped) |
| `Q` | Quit the program |

Keys are not case-sensitive. Any other key is ignored.

## Screen Layout

```
╔══════════════════════════════════════╗
║           DIGITAL STOPWATCH          ║
╠══════════════════════════════════════╣
║                                      ║
║            08:53:29 PM               ║   <- clock or stopwatch time
║              CLOCK                   ║   <- status
║       Press S to start stopwatch     ║   <- hint / small clock
╠══════════════════════════════════════╣
║ LAP TIMES                            ║
║ Lap 3  00:12.45                      ║
║ Lap 2  00:08.10                      ║
║ Lap 1  00:03.92                      ║
║                                      ║
║                                      ║
╠══════════════════════════════════════╣
║ [S]Start/Stop [L]Lap [R]Reset [Q]Quit║
╚══════════════════════════════════════╝
```

## Requirements

- Windows
- Visual Studio (with the *Desktop development with C++* workload)
- MASM (included with Visual Studio)
- [Irvine32 library](https://www.asmirvine.com/) installed, by default in `C:\irvine`
- Build configuration: **Debug, x86 (32-bit)**

## Setup and Build

1. **Install the Irvine32 library** and note its folder (for example `C:\irvine`).
2. **Create or open a MASM project** in Visual Studio:
   - Create an *Empty Project* (C++) and set the platform to **x86**.
   - Right-click the project, choose **Build Dependencies > Build Customizations**, and tick **masm**.
   - Add `Test.asm` (the source file in this repository) to the project. Make sure its item type is *Microsoft Macro Assembler*.
3. **Configure the project properties** (All Configurations):
   - **Microsoft Macro Assembler > General > Include Paths:** `C:\irvine`
   - **Linker > General > Additional Library Directories:** `C:\irvine`
   - **Linker > Input > Additional Dependencies:** `irvine32.lib;kernel32.lib;user32.lib`
   - **Linker > System > SubSystem:** `Console`
4. **Build and run** with `Ctrl + F5` (Start Without Debugging).

If you already use a working Irvine32 project template, simply replace its `.asm` file with `Test.asm`.

## How It Works

### Timing

The program does not count delay loops. It reads `GetMseconds` (milliseconds since midnight):

- When the stopwatch starts: `startTick = now - elapsed`
- While running: `elapsed = now - startTick`
- If `now < startTick`, midnight has passed and 86,400,000 ms is added.

Because of this, pausing and resuming works correctly and the display never drifts, even if drawing the screen is slow.

### Time conversion

Milliseconds are converted with `DIV` in steps:

| Display | Divisors used |
|---|---|
| Stopwatch `MM:SS.CC` | 60000, then 1000, then 10 |
| Clock `HH:MM:SS` | 3600000, then 60000, then 1000 |

For the 12-hour clock, hours of 12 or more are PM and 12 is subtracted; an hour of 0 is shown as 12.

### Program structure

```
main
 |-- SetupConsole            fixed 42x20 window and buffer
 |-- DrawFrame / DrawLaps    static interface
 |-- MAIN LOOP (about every 10 ms)
      |-- GetSizeKey / RedrawAll     repaint after a resize
      |-- ReadKey -> ToggleRun / DoLap / DoReset / Quit
      |-- ShowClockBig               clock mode
      |-- GetElapsed / ShowTime      stopwatch mode
      |-- ShowSmallClock             small clock in stopwatch mode
```

## Assembly Concepts Demonstrated

- Registers: `EAX`, `EBX`, `EDX`, `ESI`, `ESP`
- Data types: `BYTE`, `DWORD`, structures (`SMALL_RECT`, `COORD`), constants, `DUP`
- Data movement: `MOV`, `MOVZX`, `OFFSET`
- Arithmetic: `ADD`, `SUB`, `DIV`, `INC`, `DEC`
- Logic and shifts: `AND`, `OR`, `SHL`
- Comparison and jumps: `CMP`, `JE`, `JNE`, `JZ`, `JB`, `JAE`, `JNS`, `JMP`
- Loops built from counters and conditional jumps
- Procedures: `CALL`, `RET`, `PROC` / `ENDP`, `INVOKE`
- Stack: `PUSH`, `POP`, `PUSHAD`, `POPAD`
- Arrays with scaled-index addressing (`laps[esi*4+4]`) and zero-terminated strings
- A macro (`GotoRC`)
- Input and output with the Irvine32 library

## Limitations

- Windows only (Irvine32 and Windows console functions).
- Keyboard control only; no mouse or graphical interface.
- Only the last 5 laps are shown, and laps are not saved to a file.
- The clock uses the system time and cannot be set manually.
- The stopwatch is limited to a 24-hour span (it is based on milliseconds since midnight).
- No alarm, countdown timer or sound.

## Repository Contents

```
.
├── Test.asm        Source code (MASM, Irvine32)
├── README.md       This file
├── docs/           Project documentation
└── screenshots/    Program screenshots
```

## Author

**[MUSFIRA REHAN - HOORIA ALI - INSIYA MURAD]**
Roll No: [25K0873-25K0720-25K0560] | Section: [BCS-3F]
Instructor: [FAREEHA JABEEN]

Computer Organization and Assembly Language (COAL)
