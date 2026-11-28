# s94: REAL-TIME (paced, windowed, audio on) probe of the replay bat's exact
# env + --input-script, to compare against turbo probes (s69). --measure-runtime
# forces turbo=0 without capture mode; OBJ-TL taps go to stderr.
param(
    [string]$Tag = 's94rt',
    [string]$InputScript = 'replay-best.input',
    [int]$Frames = 6500,
    [string]$Addrs = '244,254,1506,516,248,a65',
    [switch]$SplashAssist
)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue
if ($SplashAssist) { $env:GENESIS_SPLASH_ASSIST='1' } else { Remove-Item Env:GENESIS_SPLASH_ASSIST -ErrorAction SilentlyContinue }
$env:GENESIS_OBJ_TL='1'; $env:GENESIS_OBJ_TL_ADDRS=$Addrs
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --input-script "'+$root+'\native\tools\'+$InputScript+'" --measure-runtime '+$Frames
$p=Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
"exit=$($p.ExitCode)"
