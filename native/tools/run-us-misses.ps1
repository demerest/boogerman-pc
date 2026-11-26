param([int]$Frames = 4000, [int]$StartFrame = 0, [switch]$TitleAssist, [switch]$SplashAssist, [switch]$ForceInterp, [switch]$StateTl, [switch]$ObjTl, [switch]$CallTl, [switch]$InsnTl, [string]$Tag = 's52', [ValidateSet('us','eu')][string]$Rom = 'us')
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
if ($TitleAssist) { $env:GENESIS_TITLE_ASSIST='1' } else { Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue }
if ($SplashAssist) { $env:GENESIS_SPLASH_ASSIST='1' } else { Remove-Item Env:GENESIS_SPLASH_ASSIST -ErrorAction SilentlyContinue }
if ($ForceInterp) { $env:GENESIS_FORCE_INTERP='1' } else { Remove-Item Env:GENESIS_FORCE_INTERP -ErrorAction SilentlyContinue }
if ($StateTl) { $env:GENESIS_STATE_TL='1' } else { Remove-Item Env:GENESIS_STATE_TL -ErrorAction SilentlyContinue }
if ($ObjTl) { $env:GENESIS_OBJ_TL='1' } else { Remove-Item Env:GENESIS_OBJ_TL -ErrorAction SilentlyContinue }
if ($CallTl) { $env:GENESIS_CALL_TL='1' } else { Remove-Item Env:GENESIS_CALL_TL -ErrorAction SilentlyContinue }
if ($InsnTl) { $env:GENESIS_INSN_TL='1' } else { Remove-Item Env:GENESIS_INSN_TL -ErrorAction SilentlyContinue }
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_$Rom.exe"; $romPath="$root\Boogerman ($(if ($Rom -eq 'eu') {'E'} else {'U'})) [!].gen"
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$cf = $Frames-100; $ce = 100
if ($StateTl) { $cf = 0; $ce = 600 }
$a='"'+$romPath+'" --exit-at-frame '+$Frames+' --capture-out "'+$out+'" --capture-from '+$cf+' --capture-to '+$Frames+' --capture-every '+$ce
if ($StartFrame -gt 0) { $a += ' --script-start '+$StartFrame }
if ($ForceInterp) { $a += ' --exec-coverage-out "'+$out+'\cov.txt"' }
$p=Start-Process -FilePath $exe -ArgumentList $a -Wait -PassThru -NoNewWindow `
   -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
"exit=$($p.ExitCode)"
