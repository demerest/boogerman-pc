# s69: native gameplay probe, CLEAN config by default (TITLE_ASSIST OFF — s68
# proved it causes the title/level hybrid). -TitleAssist re-enables for repro.
param(
    [string]$Tag = 's69a',
    [string]$InputScript = 's69-pause-start.input',
    [int]$Frames = 4200,
    [int]$CaptureFrom = 2600,
    [int]$Every = 200,
    [string]$Addrs = '516,244,254,1506,6d0,632,698,69a,222,224,24c,276,284,a65',
    [switch]$TitleAssist,
    [switch]$NoSplashAssist,
    [string]$ExecCov = '',
    [string]$Rom = 'US'
)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
if ($TitleAssist) { $env:GENESIS_TITLE_ASSIST='1' } else { Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue }
if ($NoSplashAssist) { Remove-Item Env:GENESIS_SPLASH_ASSIST -ErrorAction SilentlyContinue } else { $env:GENESIS_SPLASH_ASSIST='1' }
$env:GENESIS_OBJ_TL='1'; $env:GENESIS_OBJ_TL_ADDRS=$Addrs
$root='S:\home\dev\boogerman-pc'
if ($Rom -eq 'EU') { $exe="$root\native\build\Release\BoogermanRecomp_eu.exe"; $rom="$root\Boogerman (E) [!].gen" }
else { $exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen" }
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --exit-at-frame '+$Frames+' --input-script "'+$root+'\native\tools\'+$InputScript+'" --capture-out "'+$out+'" --capture-from '+$CaptureFrom+' --capture-to '+$Frames+' --capture-every '+$Every
if ($ExecCov) { $a += ' --exec-coverage-out "'+$out+'\'+$ExecCov+'"' }
$p=Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
"exit=$($p.ExitCode)"