@echo off
rem BoogermanRecomp (US/NTSC) TRACE launcher - play exactly like
rem BoogermanRecomp-US.bat, but leaves frame-stamped evidence for bug reports:
rem   build\trace-input.log  your inputs (a replayable .input script)
rem   build\trace-err.log    RAM-write taps: mode 244, fades 248/212, level 258,
rem                            lives 22E, HUD gate A65/246 - each write logged
rem                            with frame + guest PC - plus boot/script logs.
rem Play normally; when the HUD disappears or an audio effect sticks, note the
rem approximate moment (or just quit right after) and send both logs.
set GENESIS_Z80_NO_BUS_HALT=1
set GENESIS_WATCHDOG_INSN=400000000
set GENESIS_WATCHDOG_BUS=100000000
set GENESIS_LOCKSTEP=1
set GENESIS_Z80_FULL_SYNC=1
set GENESIS_BOOT_ASSIST=1
set GENESIS_STDERR_LOG=%~dp0build\trace-err.log
set GENESIS_INPUT_RECORD=%~dp0build\trace-input.log
set GENESIS_OBJ_TL=1
set GENESIS_OBJ_TL_ADDRS=244,248,212,258,22e,a65,246
start "" "%~dp0build\Release\BoogermanRecomp_us.exe" "%~dp0..\Boogerman (U) [!].gen"
