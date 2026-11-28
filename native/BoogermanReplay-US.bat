@echo off
rem BoogermanRecomp (US/NTSC) WINDOWED REPLAY launcher.
rem Same boot accommodations as BoogermanRecomp-US.bat, plus --input-script:
rem the runner auto-plays native/tools/replay-best.input (the latest proven
rem alive route) in a VISIBLE, real-time window with sound. No --capture-out /
rem --exit-at-frame, so the window stays open after the script ends.
rem NO HOTKEY: auto-play starts at boot. First visible press is ~35 s in
rem (title Start); the level-1 route runs ~100 s+, the toilet flush ~175 s.
rem Touching keyboard/pad for >~0.3 s CANCELS auto-play (s94) so you can grab
rem the controls at any moment (arrows = D-pad, Z = A flick, X = B jump,
rem C = C burp, RETURN = Start; hold B or DOWN in the air to boost).
rem If you play manually FIRST, the auto-play cancels - relaunch to see it.
rem Evidence log: build\replay-err.log (script load, takeover, boot taps).
rem Close the window to quit.
set GENESIS_STDERR_LOG=%~dp0build\replay-err.log
set GENESIS_Z80_NO_BUS_HALT=1
set GENESIS_WATCHDOG_INSN=400000000
set GENESIS_WATCHDOG_BUS=100000000
set GENESIS_LOCKSTEP=1
set GENESIS_Z80_FULL_SYNC=1
set GENESIS_BOOT_ASSIST=1
start "" "%~dp0build\Release\BoogermanRecomp_us.exe" "%~dp0..\Boogerman (U) [!].gen" --input-script "%~dp0tools\replay-best.input"