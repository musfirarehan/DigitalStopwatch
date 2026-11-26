; ==============================================================
;  DIGITAL CLOCK + STOPWATCH  -  x86 MASM  (Irvine32 library)
;
;  On launch  : shows the CURRENT TIME (HH:MM:SS AM/PM, 12-hour) live.
;  Press S    : switches to stopwatch mode and starts counting.
;               (a small 12-hour clock stays visible on row 6)
;
;  Controls   : S = Start/Stop   L = Lap   R = Reset -> back to clock
;               Q = Quit
;  Stopwatch  : MM:SS.CC (minutes : seconds . hundredths)
;  UI         : Colored box-drawing console screen, status line,
;               and a list of the last 5 lap times.
;
;  Timing     : uses GetMseconds (ms since midnight), so the
;               displayed time is exact and does not drift.
;
;  Build      : Visual Studio + Irvine32 project template
;               (32-bit, MASM), or any Irvine32 setup.
; ==============================================================
INCLUDE Irvine32.inc
; ---------- helper macro: move cursor to (row, col) ----------
GotoRC MACRO row, col
    mov  dh, row
    mov  dl, col
    call Gotoxy
ENDM
MS_PER_DAY = 86400000
.data
; ---- frame pieces (code page 437 box characters) ----
topLine     BYTE 201, 38 DUP(205), 187, 0
midLine     BYTE 204, 38 DUP(205), 185, 0
botLine     BYTE 200, 38 DUP(205), 188, 0
sideLine    BYTE 186, 38 DUP(' '), 186, 0
; ---- text ----
msgTitle    BYTE "DIGITAL STOPWATCH", 0
msgRun      BYTE "RUNNING", 0
msgStop     BYTE "STOPPED", 0
msgClockSt  BYTE "CLOCK  ", 0
msgLaps     BYTE "LAP TIMES", 0
msgKeys     BYTE "[S]Start/Stop [L]Lap [R]Reset [Q]Quit", 0
msgLapLbl   BYTE "Lap ", 0
msgBlank    BYTE 30 DUP(' '), 0
msgBye      BYTE "Stopwatch closed.", 0
msgHint     BYTE "Press S to start stopwatch", 0
msgClockLbl BYTE "Clock ", 0
; ---- state ---
mode        BYTE  0             ; 0 = clock mode, 1 = stopwatch mode
elapsed     DWORD 0             ; elapsed time in ms (while stopped)
startTick   DWORD 0             ; reference tick while running
running     BYTE  0             ; 1 = running
lapTotal    DWORD 0             ; number of laps taken
laps        DWORD 5 DUP(0)      ; last 5 laps, newest at index 0
; ---- scratch ----
rowIdx      DWORD 0
tmpRem      DWORD 0
pmFlag      BYTE  0             ; 1 = PM, 0 = AM
; ---- console size handling ---
hOut        DWORD 0
winRect     SMALL_RECT <0,0,41,19>  ; window: 42 columns x 20 rows
bufSize     COORD <42,20>           ; buffer = window -> no scrollbars
lastSize    DWORD 0                 ; to detect window resize
.code
; ==============================================================
main PROC
    call SetupConsole           ; fixed 42x20 window, no scrolling
    call Clrscr
    call DrawFrame
    call DrawLaps
    call ShowRow6Hint
    call ShowStatus
    call GetSizeKey
    mov  lastSize, eax
MainLoop:
    call GetSizeKey             ; window resized / maximized?
    cmp  eax, lastSize
    je   SizeOk
    mov  lastSize, eax
    call RedrawAll              ; repaint cleanly after a resize
SizeOk:
    call ReadKey                ; ZF=1 if no key pressed
    jz   NoKey
    and  al, 0DFh               ; to upper case
    cmp  al, 'Q'
    je   Quit
    cmp  al, 'S'
    jne  NotS
    call ToggleRun
    jmp  NoKey
NotS:
    cmp  al, 'L'
    jne  NotL
    call DoLap
    jmp  NoKey
NotL:
    cmp  al, 'R'
    jne  NoKey
    call DoReset
NoKey:
    cmp  mode, 0
    jne  SwMode
    ; ---- clock mode: big live clock ----
    call ShowClockBig
    jmp  Idle
SwMode:
    ; ---- stopwatch mode ----
    cmp  running, 0
    je   SwClock
    call GetElapsed
    mov  elapsed, eax
    call ShowTime
SwClock:
    call ShowSmallClock         ; small live clock on row 6
Idle:
    mov  eax, 10                ; ~10 ms pause (keeps CPU usage low)
    call Delay
    jmp  MainLoop
Quit:
    mov  eax, lightGray
    call SetTextColor
    GotoRC 18, 0
    mov  edx, OFFSET msgBye
    call WriteString
    call Crlf
    exit
main ENDP
; ==============================================================
;  SetupConsole : force a 42x20 window with a buffer of the same
;                 size, so there are no scrollbars and the
;                 screen can never be scrolled out of position
; ==============================================================
SetupConsole PROC
    INVOKE GetStdHandle, STD_OUTPUT_HANDLE
    mov  hOut, eax
    INVOKE SetConsoleWindowInfo, hOut, TRUE, ADDR winRect
    push DWORD PTR bufSize      ; COORD is passed by value (4 bytes)
    push hOut
    call SetConsoleScreenBufferSize
    ret
SetupConsole ENDP

; ==============================================================
;  GetSizeKey : EAX = packed console size (rows:cols)
; ==============================================================
GetSizeKey PROC
    call GetMaxXY               ; AX/DX = console rows/columns
    movzx eax, ax
    movzx edx, dx
    shl  eax, 16
    or   eax, edx
    ret
GetSizeKey ENDP

; ==============================================================
;  RedrawAll : clear the screen and repaint everything
; ==============================================================
RedrawAll PROC
    call Clrscr
    call DrawFrame
    call DrawLaps
    call ShowStatus
    cmp  mode, 0
    jne  RA_sw
    call ShowRow6Hint
    ret
RA_sw:
    call ShowTime
    ret
RedrawAll ENDP

; ==============================================================
;  GetElapsed : returns EAX = ms since startTick (handles midnight)
; ==============================================================
GetElapsed PROC
    call GetMseconds
    cmp  eax, startTick
    jae  GE_ok
    add  eax, MS_PER_DAY        ; midnight wrap
GE_ok:
    sub  eax, startTick
    ret
GetElapsed ENDP

; ==============================================================
;  ToggleRun : start / stop (first start leaves clock mode)
; ==============================================================
ToggleRun PROC
    cmp  running, 0
    jne  TR_stop

    ; --- leaving clock mode? ---
    cmp  mode, 0
    jne  TR_start
    mov  mode, 1
    call ClearRow6
    call ClearRow4
TR_start:
    ; --- start: startTick = now - elapsed ---
    call GetMseconds
    cmp  eax, elapsed
    jae  TR_s1
    add  eax, MS_PER_DAY
TR_s1:
    sub  eax, elapsed
    mov  startTick, eax
    mov  running, 1
    jmp  TR_done
TR_stop:
    call GetElapsed
    mov  elapsed, eax
    mov  running, 0
TR_done:
    call ShowStatus
    call ShowTime
    ret
ToggleRun ENDP
; ==============================================================
;  DoLap : record current time (only while running)
; ==============================================================
DoLap PROC
    cmp  running, 0
    je   DL_exit
    call GetElapsed             ; EAX = current time
    mov  esi, 3                 ; shift older laps down
DL_shift:
    mov  ebx, laps[esi*4]
    mov  laps[esi*4+4], ebx
    dec  esi
    jns  DL_shift
    mov  laps, eax              ; newest lap at index 0
    inc  lapTotal
    call DrawLaps
DL_exit:
    ret
DoLap ENDP
; ==============================================================
;  DoReset : clear stopwatch and return to clock mode
;            (only while stopped)
; ==============================================================
DoReset PROC
    cmp  running, 0
    jne  DR_exit
    mov  elapsed, 0
    mov  lapTotal, 0
    mov  mode, 0
    call DrawLaps
    call ClearRow6
    call ClearRow4
    call ShowRow6Hint
    call ShowStatus
DR_exit:
    ret
DoReset ENDP
; ==============================================================
;  DrawFrame : static screen layout
; ==============================================================
DrawFrame PROC
    mov  eax, lightCyan
    call SetTextColor

    mov  rowIdx, 0
FR_loop:
    mov  eax, rowIdx
    mov  ebx, OFFSET sideLine           ; default: side row
    cmp  eax, 0
    jne  FR_n1
    mov  ebx, OFFSET topLine
FR_n1:
    cmp  eax, 16
    jne  FR_n2
    mov  ebx, OFFSET botLine
FR_n2:
    cmp  eax, 2
    je   FR_mid
    cmp  eax, 7
    je   FR_mid
    cmp  eax, 14
    jne  FR_draw
FR_mid:
    mov  ebx, OFFSET midLine
FR_draw:
    mov  dh, al
    mov  dl, 0
    call Gotoxy
    mov  edx, ebx
    call WriteString
    inc  rowIdx
    cmp  rowIdx, 17
    jb   FR_loop

    ; title
    mov  eax, white
    call SetTextColor
    GotoRC 1, 11
    mov  edx, OFFSET msgTitle
    call WriteString

    ; lap header
    mov  eax, yellow
    call SetTextColor
    GotoRC 8, 3
    mov  edx, OFFSET msgLaps
    call WriteString

    ; key help
    mov  eax, lightGray
    call SetTextColor
    GotoRC 15, 1
    mov  edx, OFFSET msgKeys
    call WriteString
    ret
DrawFrame ENDP
; ==============================================================
;  ShowStatus : CLOCK / RUNNING / STOPPED
; ==============================================================
ShowStatus PROC
    GotoRC 5, 16
    cmp  mode, 0
    jne  SS_sw
    mov  eax, lightCyan
    call SetTextColor
    mov  edx, OFFSET msgClockSt
    jmp  SS_print
SS_sw:
    cmp  running, 0
    jne  SS_run
    mov  eax, lightRed
    call SetTextColor
    mov  edx, OFFSET msgStop
    jmp  SS_print
SS_run:
    mov  eax, lightGreen
    call SetTextColor
    mov  edx, OFFSET msgRun
SS_print:
    call WriteString
    GotoRC 18, 0                ; park the cursor out of the way
    ret
ShowStatus ENDP
; ==============================================================
;  ShowTime : big stopwatch display at row 4
; ==============================================================
ShowTime PROC
    mov  eax, yellow
    cmp  running, 0
    je   ST_col
    mov  eax, lightGreen
ST_col:
    call SetTextColor
    GotoRC 4, 16
    mov  eax, elapsed
    call PrintTime
    GotoRC 18, 0
    ret
ShowTime ENDP
; ==============================================================
;  ShowClockBig : current time HH:MM:SS at row 4 (clock mode)
; ==============================================================
ShowClockBig PROC
    mov  eax, white
    call SetTextColor
    GotoRC 4, 14
    call GetMseconds
    call PrintClock
    GotoRC 18, 0
    ret
ShowClockBig ENDP
; ==============================================================
;  ShowSmallClock : "Clock HH:MM:SS" at row 6 (stopwatch mode)
; ==============================================================
ShowSmallClock PROC
    mov  eax, lightGray
    call SetTextColor
    GotoRC 6, 11
    mov  edx, OFFSET msgClockLbl
    call WriteString
    call GetMseconds
    call PrintClock
    GotoRC 18, 0
    ret
ShowSmallClock ENDP
; ==============================================================
;  ShowRow6Hint / ClearRow6
; ==============================================================
ShowRow6Hint PROC
    mov  eax, lightGray
    call SetTextColor
    GotoRC 6, 7
    mov  edx, OFFSET msgHint
    call WriteString
    GotoRC 18, 0
    ret
ShowRow6Hint ENDP
ClearRow6 PROC
    GotoRC 6, 3
    mov  edx, OFFSET msgBlank
    call WriteString
    ret
ClearRow6 ENDP
ClearRow4 PROC
    GotoRC 4, 3
    mov  edx, OFFSET msgBlank
    call WriteString
    ret
ClearRow4 ENDP
; ==============================================================
;  DrawLaps : rows 9..13
; ==============================================================
DrawLaps PROC
    mov  eax, lightMagenta
    call SetTextColor
    mov  rowIdx, 0
DL_loop:
    mov  eax, rowIdx            ; clear the row first
    add  al, 9
    mov  dh, al
    mov  dl, 3
    call Gotoxy
    mov  edx, OFFSET msgBlank
    call WriteString
    mov  eax, rowIdx
    cmp  eax, lapTotal
    jae  DL_next                ; no lap for this row
    mov  eax, rowIdx
    add  al, 9
    mov  dh, al
    mov  dl, 3
    call Gotoxy
    mov  edx, OFFSET msgLapLbl
    call WriteString
    mov  eax, lapTotal          ; lap number = total - row
    sub  eax, rowIdx
    call WriteDec
    mov  al, ' '
    call WriteChar
    mov  al, ' '
    call WriteChar
    mov  esi, rowIdx
    mov  eax, laps[esi*4]
    call PrintTime
DL_next:
    inc  rowIdx
    cmp  rowIdx, 5
    jb   DL_loop
    GotoRC 18, 0
    ret
DrawLaps ENDP
; ==============================================================
;  PrintTime : EAX = milliseconds -> prints MM:SS.CC
; ==============================================================
PrintTime PROC
    pushad
    mov  edx, 0
    mov  ebx, 60000
    div  ebx                    ; EAX = minutes, EDX = remainder
    mov  tmpRem, edx
    call Print2
    mov  al, ':'
    call WriteChar

    mov  eax, tmpRem
    mov  edx, 0
    mov  ebx, 1000
    div  ebx                    ; EAX = seconds, EDX = ms
    mov  tmpRem, edx
    call Print2
    mov  al, '.'
    call WriteChar
    mov  eax, tmpRem
    mov  edx, 0
    mov  ebx, 10
    div  ebx                    ; EAX = hundredths
    call Print2
    popad
    ret
PrintTime ENDP
; ==============================================================
;  PrintClock : EAX = ms since midnight -> prints HH:MM:SS AM/PM
;               (12-hour format)
; ==============================================================
PrintClock PROC
    pushad
    mov  edx, 0
    mov  ebx, 3600000
    div  ebx                    ; EAX = hours (0-23), EDX = remainder
    mov  tmpRem, edx

    mov  pmFlag, 0              ; convert 24h -> 12h
    cmp  eax, 12
    jb   PC_am
    mov  pmFlag, 1              ; 12:00 - 23:59 is PM
    sub  eax, 12
PC_am:
    cmp  eax, 0
    jne  PC_hour
    mov  eax, 12                ; 0 -> 12 (midnight / noon)
PC_hour:
    call Print2
    mov  al, ':'
    call WriteChar

    mov  eax, tmpRem
    mov  edx, 0
    mov  ebx, 60000
    div  ebx                    ; EAX = minutes
    mov  tmpRem, edx
    call Print2
    mov  al, ':'
    call WriteChar
    mov  eax, tmpRem
    mov  edx, 0
    mov  ebx, 1000
    div  ebx                    ; EAX = seconds
    call Print2
    mov  al, ' '
    call WriteChar
    mov  al, 'A'
    cmp  pmFlag, 0
    je   PC_suffix
    mov  al, 'P'
PC_suffix:
    call WriteChar
    mov  al, 'M'
    call WriteChar
    popad
    ret
PrintClock ENDP
; ==============================================================
;  Print2 : print EAX with at least two digits
; ==============================================================
Print2 PROC
    cmp  eax, 10
    jae  P2_go
    push eax
    mov  al, '0'
    call WriteChar
    pop  eax
P2_go:
    call WriteDec
    ret
Print2 ENDP
END main
