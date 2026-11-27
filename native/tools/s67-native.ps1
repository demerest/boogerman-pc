# s67: phase-locked native gameplay runs. Input scripts use WAIT_RAM16 to anchor
# to the game-commit phase (0244=1) instead of absolute frames, removing boot-pace
# host variance. OBJ-TL ADDRS tap records the watched RAM writes to err.log.
param(
    [string]$Tag = 's67nscroll',
    [string]$InputScript = 's67-scroll.input',
    [int]$Frames = 5000,
    [string]$Addrs = '698,69a,690,686,688,64e,650,652,654,656,658,65a,65c,666,668,66a,66c,66e,670,672,674,6d0,632,244,288,1a14,1a5a,692,694,696,69c,69e,6a0,6a2,6a4,6a6,6a8,6aa,6ac,6ae'
)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$env:GENESIS_TITLE_ASSIST='1'; $env:GENESIS_SPLASH_ASSIST='1'
$env:GENESIS_OBJ_TL='1'; $env:GENESIS_OBJ_TL_ADDRS=$Addrs
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --exit-at-frame '+$Frames+' --input-script "'+$root+'\native\tools\'+$InputScript+'" --capture-out "'+$out+'" --capture-from '+($Frames-100)+' --capture-to '+$Frames+' --capture-every 100'
$p=Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
"exit=$($p.ExitCode)"
