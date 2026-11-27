# s68: native gameplay probe with multi-frame capture + mode-write tap.
# Same assist/lockstep base as s67-native.ps1; adds -CaptureFrom/-Every so the
# framebuffer trail (not just the last frame) shows where title/level diverges.
param(
    [string]$Tag = 's68a',
    [string]$InputScript = 's68-probe.input',
    [int]$Frames = 4200,
    [int]$CaptureFrom = 2600,
    [int]$Every = 200,
    [string]$Addrs = '516,244,254,1506,284,a65,2ba,246,6d0,632,1a14,1a5a,5d4,5d6',
    [switch]$NoTitleAssist,
    [switch]$NoSplashAssist
)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
if ($NoTitleAssist) { Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue } else { $env:GENESIS_TITLE_ASSIST='1' }
if ($NoSplashAssist) { Remove-Item Env:GENESIS_SPLASH_ASSIST -ErrorAction SilentlyContinue } else { $env:GENESIS_SPLASH_ASSIST='1' }
$env:GENESIS_OBJ_TL='1'; $env:GENESIS_OBJ_TL_ADDRS=$Addrs
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --exit-at-frame '+$Frames+' --input-script "'+$root+'\native\tools\'+$InputScript+'" --capture-out "'+$out+'" --capture-from '+$CaptureFrom+' --capture-to '+$Frames+' --capture-every '+$Every
$p=Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
"exit=$($p.ExitCode)"
