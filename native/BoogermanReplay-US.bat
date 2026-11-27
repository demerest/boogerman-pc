@echo off
rem BoogermanRecomp (US/NTSC) WINDOWED REPLAY launcher.
rem Same boot accommodations as BoogermanRecomp-US.bat, plus --input-script:
rem the runner auto-plays native/tools/replay-best.input (the latest proven
rem alive route) in a VISIBLE, real-time window with sound. No --capture-out /
rem --exit-at-frame, so the window stays open after the script ends.
rem Script pads MERGE with the live keyboard: you can grab the controls at any
rem moment (arrows = D-pad, Z = A flick, X = B jump, C = C burp, RETURN = Start;
rem hold B or DOWN in the air to boost). Close the window to quit.
set GENESIS_Z80_NO_BUS_HALT=1
set GENESIS_WATCHDOG_INSN=400000000
set GENESIS_WATCHDOG_BUS=100000000
set GENESIS_LOCKSTEP=1
set GENESIS_Z80_FULL_SYNC=1
set GENESIS_BOOT_ASSIST=1
start "" "%~dp0build\Release\BoogermanRecomp_us.exe" "%~dp0..\Boogerman (U) [!].gen" --input-script "%~dp0tools\replay-best.input"