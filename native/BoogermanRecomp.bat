@echo off
rem BoogermanRecomp launcher - passes your owned dump to the native port.
rem Current state: boots and renders the PAL boot screen, then halts (M2 blocker).
start "" "%~dp0build\Release\BoogermanRecomp.exe" "%~dp0..\Boogerman (E) [!].gen"
