param([int]$Frames = 40, [switch]$SyncTrace, [switch]$InterleaveIrq, [int]$Quantum = -1)
$ErrorActionPreference = 'Stop'
if ($SyncTrace) { $env:GENESIS_Z80_SYNC_TRACE = '1' }
if ($InterleaveIrq) { $env:GENESIS_INTERLEAVE_IRQ = '1' }
if ($Quantum -ge 0) { $env:GENESIS_Z80_BUS_QUANTUM = "$Quantum" }
$root = 'S:\home\dev\boogerman-pc'
$exe  = "$root\native\build\Release\BoogermanRecomp_us.exe"
$rom  = "$root\Boogerman (U) [!].gen"
$out  = "$root\native\captures-us"
$argline = "`"$rom`" --exit-at-frame $Frames --capture-out `"$out`" --capture-from 20 --capture-to $Frames --capture-every 40"
$p = Start-Process -FilePath $exe -ArgumentList $argline `
     -Wait -PassThru -NoNewWindow `
     -RedirectStandardError "$out\hs-stderr.log" -RedirectStandardOutput "$out\hs-stdout.log"
"exit=$($p.ExitCode)"
