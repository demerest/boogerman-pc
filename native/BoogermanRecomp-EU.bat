@echo off
rem BoogermanRecomp (EU/PAL) launcher - passes your owned EU dump.
rem Boot accommodations (M2): let the polling-driven Z80 run during brief bus
rem arbitration, and give the long boot sound-init V-int handler watchdog
rem headroom. Without these the boot stalls before the title screen.
set GENESIS_Z80_NO_BUS_HALT=1
set GENESIS_WATCHDOG_INSN=400000000
set GENESIS_WATCHDOG_BUS=100000000
start "" "%~dp0build\Release\BoogermanRecomp_eu.exe" "%~dp0..\Boogerman (E) [!].gen"
