param([int]$StartMs = 1800)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\joy"; New-Item -ItemType Directory -Force -Path $out|Out-Null
$p=Start-Process -FilePath $exe -ArgumentList ('"'+$rom+'" --exit-at-frame 4000') -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
Start-Sleep -Milliseconds $StartMs
try {
  $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
  $s.ReadTimeout=2000; $s.WriteTimeout=2000
  $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
  $w.WriteLine('{"id":1,"cmd":"set_input","keys":128}'); $r.ReadLine()|Out-Null
  Start-Sleep -Milliseconds 400
  $w.WriteLine('{"id":2,"cmd":"read_memory","addr":"0xFF0500","size":8}'); $j=$r.ReadLine()
  $w.WriteLine('{"id":3,"cmd":"read_memory","addr":"0xFF0516","size":2}'); $m=$r.ReadLine()
  $w.WriteLine('{"id":5,"cmd":"read_memory","addr":"0xFF05B4","size":2}'); $t=$r.ReadLine()
  $w.WriteLine('{"id":6,"cmd":"read_memory","addr":"0xFF050C","size":4}'); $j2=$r.ReadLine()
  $w.WriteLine('{"id":4,"cmd":"set_input","keys":0}'); $r.ReadLine()|Out-Null
  $c.Close()
  "joy0502: $j"
  "joy050C: $j2"
  "mode: $m"
  "timer5B4: $t"
} catch { "err: $_" }
if (-not $p.HasExited) { $p.WaitForExit(15000)|Out-Null }
if (-not $p.HasExited) { $p.Kill() }
