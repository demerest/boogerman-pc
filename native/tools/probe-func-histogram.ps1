param([int]$WarmMs = 3000, [int]$Samples = 80, [int]$Overclock = -1, [switch]$BootAssist, [switch]$FullSync, [switch]$Accurate)
$ErrorActionPreference = 'Stop'
$env:GENESIS_Z80_NO_BUS_HALT = '1'
if ($Overclock -ge 1) { $env:GENESIS_Z80_OVERCLOCK = "$Overclock" }
if ($BootAssist) { $env:GENESIS_BOOT_ASSIST = '1' }
if ($FullSync) { $env:GENESIS_Z80_FULL_SYNC = '1' }
$pacing = if ($Accurate) { ' --pacing=accurate' } else { '' }
$env:GENESIS_WATCHDOG_INSN = '400000000'; $env:GENESIS_WATCHDOG_BUS = '100000000'
$root = 'S:\home\dev\boogerman-pc'
$exe = "$root\native\build\Release\BoogermanRecomp_us.exe"
$rom = "$root\Boogerman (U) [!].gen"
$p = Start-Process -FilePath $exe -ArgumentList ('"' + $rom + '"' + $pacing) -PassThru -NoNewWindow `
     -RedirectStandardError "$root\native\captures-us\hist-err.log" -RedirectStandardOutput "$root\native\captures-us\hist-out.log"
Start-Sleep -Milliseconds $WarmMs
$tally = @{}
try {
  $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4400)
  $s = $c.GetStream(); $s.ReadTimeout = 2000; $s.WriteTimeout = 2000
  $w = New-Object System.IO.StreamWriter($s); $r = New-Object System.IO.StreamReader($s); $w.AutoFlush = $true
  for ($i = 0; $i -lt $Samples; $i++) {
    $w.WriteLine('{"id":1,"cmd":"rdb_get_state"}')
    $line = $r.ReadLine()
    $m = [regex]::Match($line, '"func":"0x([0-9A-Fa-f]+)"')
    if ($m.Success) { $f = $m.Groups[1].Value; if ($tally.ContainsKey($f)) { $tally[$f]++ } else { $tally[$f] = 1 } }
    Start-Sleep -Milliseconds 25
  }
  $c.Close()
} catch { "probe err: $_" }
if (-not $p.HasExited) { $p.Kill() }
"top functions at title:"
$tally.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 12 | ForEach-Object { "$($_.Value)  $($_.Name)" }
