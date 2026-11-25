; ============================================================
;  DIGITAL STOPWATCH  -  x86 MASM + Irvine32 library
; ------------------------------------------------------------
;  Controls:  S = Start / Stop
;             L = Lap (records up to 10 laps, with split times)
;             R = Reset
;             Q = Quit
;  Display :  HH:MM:SS.cc   (cc = hundredths of a second)
;  Timing  :  Irvine32 GetMseconds (real clock, so no drift
;             even if the loop runs slower than expected)
; ============================================================
INCLUDE Irvine32.inc

MAX_LAPS      = 10
MS_PER_DAY    = 86400000        ; GetMseconds wraps at midnight

.data
titleStr      BYTE "=====  DIGITAL STOPWATCH  =====",0
controlsStr   BYTE "[S] Start/Stop   [L] Lap   [R] Reset   [Q] Quit",0
lapHdrStr     BYTE "Laps:",0
statRun       BYTE "RUNNING ",0
statStop      BYTE "STOPPED ",0
lapLbl        BYTE "Lap ",0
totalStr      BYTE "  total ",0
splitStr      BYTE "  split ",0

state         BYTE  0           ; 0 = stopped, 1 = running
startTick     DWORD 0           ; GetMseconds value when last started
elapsedBase   DWORD 0           ; ms accumulated before last start
currentMs     DWORD 0           ; ms currently shown
lapCount      DWORD 0
laps          DWORD MAX_LAPS DUP(0)   ; cumulative ms for each lap

.code
; ------------------------------------------------------------
main PROC
    call Clrscr
    call DrawUI

mainLoop:
    call ReadKey                ; non-blocking: ZF=1 if no key
    jz   updateScreen
    and  al, 0DFh               ; force upper case
    cmp  al, 'S'
    je   doToggle
    cmp  al, 'L'
    je   doLap
    cmp  al, 'R'
    je   doReset
    cmp  al, 'Q'
    je   quit
    jmp  updateScreen

doToggle:
    call ToggleState
    jmp  updateScreen
doLap:
    call RecordLap
    jmp  updateScreen
doReset:
    call ResetAll

updateScreen:
    call GetElapsed             ; EAX = elapsed ms
    mov  currentMs, eax
    call ShowClock
    call ShowStatus
    call ShowLaps
    mov  eax, 10                ; ~100 refreshes per second
    call Delay
    jmp  mainLoop

quit:
    mov  eax, lightGray + (black * 16)
    call SetTextColor
    mov  dh, 24
    mov  dl, 0
    call Gotoxy
    exit
main ENDP

; ------------------------------------------------------------
; DrawUI : draws the static text
; ------------------------------------------------------------
DrawUI PROC USES eax edx
    mov  eax, cyan + (black * 16)
    call SetTextColor
    mov  dh, 1
    mov  dl, 20
    call Gotoxy
    mov  edx, OFFSET titleStr
    call WriteString

    mov  eax, lightGray + (black * 16)
    call SetTextColor
    mov  dh, 9
    mov  dl, 12
    call Gotoxy
    mov  edx, OFFSET controlsStr
    call WriteString

    mov  eax, white + (black * 16)
    call SetTextColor
    mov  dh, 11
    mov  dl, 10
    call Gotoxy
    mov  edx, OFFSET lapHdrStr
    call WriteString
    ret
DrawUI ENDP

; ------------------------------------------------------------
; GetElapsed : returns total elapsed ms in EAX
; ------------------------------------------------------------
GetElapsed PROC
    mov  eax, elapsedBase
    cmp  state, 0
    je   done
    call GetMseconds
    sub  eax, startTick
    jnc  noWrap                 ; carry => clock wrapped past midnight
    add  eax, MS_PER_DAY
noWrap:
    add  eax, elapsedBase
done:
    ret
GetElapsed ENDP

; ------------------------------------------------------------
; ToggleState : Start <-> Stop
; ------------------------------------------------------------
ToggleState PROC
    cmp  state, 0
    jne  stopIt
    call GetMseconds            ; --- start ---
    mov  startTick, eax
    mov  state, 1
    ret
stopIt:                         ; --- stop ---
    call GetElapsed
    mov  elapsedBase, eax
    mov  state, 0
    ret
ToggleState ENDP

; ------------------------------------------------------------
; RecordLap : stores current time (only while running)
; ------------------------------------------------------------
RecordLap PROC USES eax ebx
    cmp  state, 0
    je   skip
    cmp  lapCount, MAX_LAPS
    jae  skip
    call GetElapsed
    mov  ebx, lapCount
    mov  laps[ebx*4], eax
    inc  lapCount
skip:
    ret
RecordLap ENDP

; ------------------------------------------------------------
; ResetAll : zero everything and redraw
; ------------------------------------------------------------
ResetAll PROC
    mov  state, 0
    mov  elapsedBase, 0
    mov  startTick, 0
    mov  lapCount, 0
    call Clrscr
    call DrawUI
    ret
ResetAll ENDP

; ------------------------------------------------------------
; ShowClock : big time display
; ------------------------------------------------------------
ShowClock PROC USES eax edx
    mov  eax, yellow + (black * 16)
    call SetTextColor
    mov  dh, 4
    mov  dl, 30
    call Gotoxy
    mov  eax, currentMs
    call DisplayTime
    ret
ShowClock ENDP

; ------------------------------------------------------------
; ShowStatus : RUNNING (green) / STOPPED (red)
; ------------------------------------------------------------
ShowStatus PROC USES eax edx
    mov  dh, 6
    mov  dl, 32
    call Gotoxy
    cmp  state, 0
    jne  running
    mov  eax, lightRed + (black * 16)
    call SetTextColor
    mov  edx, OFFSET statStop
    call WriteString
    ret
running:
    mov  eax, lightGreen + (black * 16)
    call SetTextColor
    mov  edx, OFFSET statRun
    call WriteString
    ret
ShowStatus ENDP

; ------------------------------------------------------------
; ShowLaps : prints every recorded lap (total + split)
; ------------------------------------------------------------
ShowLaps PROC USES eax edx esi
    mov  eax, white + (black * 16)
    call SetTextColor
    xor  esi, esi
lapLoop:
    cmp  esi, lapCount
    jae  finished

    mov  eax, esi               ; row = 12 + index
    add  eax, 12
    mov  dh, al
    mov  dl, 10
    call Gotoxy

    mov  edx, OFFSET lapLbl
    call WriteString
    mov  eax, esi
    inc  eax
    call PrintTwo

    mov  edx, OFFSET totalStr
    call WriteString
    mov  eax, laps[esi*4]
    call DisplayTime

    mov  edx, OFFSET splitStr
    call WriteString
    mov  eax, laps[esi*4]
    cmp  esi, 0
    je   showSplit              ; first lap: split = total
    sub  eax, laps[esi*4 - 4]
showSplit:
    call DisplayTime

    inc  esi
    jmp  lapLoop
finished:
    ret
ShowLaps ENDP

; ------------------------------------------------------------
; DisplayTime : EAX = milliseconds -> prints HH:MM:SS.cc
; ------------------------------------------------------------
DisplayTime PROC USES eax ebx edx
    xor  edx, edx
    mov  ebx, 3600000           ; ms per hour
    div  ebx                    ; EAX = hours, EDX = remainder
    call PrintTwo
    mov  al, ':'
    call WriteChar

    mov  eax, edx
    xor  edx, edx
    mov  ebx, 60000             ; ms per minute
    div  ebx                    ; EAX = minutes
    call PrintTwo
    mov  al, ':'
    call WriteChar

    mov  eax, edx
    xor  edx, edx
    mov  ebx, 1000
    div  ebx                    ; EAX = seconds, EDX = ms
    call PrintTwo
    mov  al, '.'
    call WriteChar

    mov  eax, edx
    xor  edx, edx
    mov  ebx, 10
    div  ebx                    ; EAX = hundredths
    call PrintTwo
    ret
DisplayTime ENDP

; ------------------------------------------------------------
; PrintTwo : prints EAX as at least two digits (leading zero)
; ------------------------------------------------------------
PrintTwo PROC USES eax
    cmp  eax, 10
    jae  printIt
    push eax
    mov  al, '0'
    call WriteChar
    pop  eax
printIt:
    call WriteDec
    ret
PrintTwo ENDP

END main
