param([int]$Frames = 40, [switch]$SyncTrace, [switch]$InterleaveIrq, [int]$Quantum = -1, [switch]$InsnTrace,
      [long]$WatchdogInsn = -1, [long]$WatchdogBus = -1, [switch]$MboxTrace, [switch]$NoBusHalt, [switch]$BootAssist)
$ErrorActionPreference = 'Stop'
if ($BootAssist) { $env:GENESIS_BOOT_ASSIST = '1' }
if ($MboxTrace) { $env:GENESIS_MBOX_TRACE = '1' }
if ($NoBusHalt) { $env:GENESIS_Z80_NO_BUS_HALT = '1' }
if ($SyncTrace) { $env:GENESIS_Z80_SYNC_TRACE = '1' }
if ($InterleaveIrq) { $env:GENESIS_INTERLEAVE_IRQ = '1' }
if ($InsnTrace) { $env:GENESIS_Z80_INSN_TRACE = '1' }
if ($Quantum -ge 0) { $env:GENESIS_Z80_BUS_QUANTUM = "$Quantum" }
if ($WatchdogInsn -ge 0) { $env:GENESIS_WATCHDOG_INSN = "$WatchdogInsn" }
if ($WatchdogBus -ge 0) { $env:GENESIS_WATCHDOG_BUS = "$WatchdogBus" }
$root = 'S:\home\dev\boogerman-pc'
$exe  = "$root\native\build\Release\BoogermanRecomp_us.exe"
$rom  = "$root\Boogerman (U) [!].gen"
$out  = "$root\native\captures-us"
$argline = "`"$rom`" --exit-at-frame $Frames --capture-out `"$out`" --capture-from 20 --capture-to $Frames --capture-every 40"
$p = Start-Process -FilePath $exe -ArgumentList $argline `
     -Wait -PassThru -NoNewWindow `
     -RedirectStandardError "$out\hs-stderr.log" -RedirectStandardOutput "$out\hs-stdout.log"
"exit=$($p.ExitCode)"
