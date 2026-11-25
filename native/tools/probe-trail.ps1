param([int]$WarmMs = 26000)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$p=Start-Process -FilePath $exe -ArgumentList ('"'+$rom+'"') -PassThru -NoNewWindow -RedirectStandardError "$root\native\captures-us\trail-err.log" -RedirectStandardOutput "$root\native\captures-us\trail-out.log"
Start-Sleep -Milliseconds $WarmMs
try {
  $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
  $s.ReadTimeout=3000; $s.WriteTimeout=3000
  $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
  $w.WriteLine('{"id":1,"cmd":"crash_trail"}'); $line=$r.ReadLine()
  $c.Close()
  $line
} catch { "err: $_" }
if (-not $p.HasExited) { $p.Kill() }
