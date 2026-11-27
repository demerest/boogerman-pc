# s72: localize the field direction-input bug — same as s69-native but with
# GENESIS_FORCE_INTERP=1 (if RIGHT works here, the emitted IO path is at fault).
param([string]$Tag = 's72n3', [string]$InputScript = 's72-right.input', [int]$Frames = 9000)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$env:GENESIS_SPLASH_ASSIST='1'; $env:GENESIS_FORCE_INTERP='1'
$env:GENESIS_OBJ_TL='1'; $env:GENESIS_OBJ_TL_ADDRS='502,222,698,244'
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\$Tag"; New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --exit-at-frame '+$Frames+' --input-script "'+$root+'\native\tools\'+$InputScript+'" --capture-out "'+$out+'" --capture-from 7000 --capture-to '+$Frames+' --capture-every 400'
$p=Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
"exit=$($p.ExitCode)"
