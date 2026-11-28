@echo off
rem BoogermanRecomp (US/NTSC) launcher - passes your owned US dump.
rem Boot accommodations (M2): let the polling-driven Z80 run during brief bus
rem arbitration, and give the long boot sound-init V-int handler watchdog
rem headroom. Without these the boot stalls before the title screen.
set GENESIS_Z80_NO_BUS_HALT=1
set GENESIS_WATCHDOG_INSN=400000000
set GENESIS_WATCHDOG_BUS=100000000
rem Lockstep 68K/Z80 interleave + concurrent sync + boot sound-init assist:
rem together these let the boot reach the interactive title (M2/M3).
set GENESIS_LOCKSTEP=1
set GENESIS_Z80_FULL_SYNC=1
set GENESIS_BOOT_ASSIST=1
rem s94: keep a stderr log so boot/script problems are diagnosable after the
rem detached window closes (build\play-err.log).
set GENESIS_STDERR_LOG=%~dp0build\play-err.log
start "" "%~dp0build\Release\BoogermanRecomp_us.exe" "%~dp0..\Boogerman (U) [!].gen"
