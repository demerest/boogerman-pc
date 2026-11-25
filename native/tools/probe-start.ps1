param([int]$StartMs = 1800, [int]$HoldMs = 1200)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\start"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --exit-at-frame 4000 --capture-out "'+$out+'" --capture-from 2600 --capture-to 4000 --capture-every 400'
$p=Start-Process -FilePath $exe -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
Start-Sleep -Milliseconds $StartMs
try {
  $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
  $s.ReadTimeout=2000; $s.WriteTimeout=2000
  $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
  $w.WriteLine('{"id":1,"cmd":"set_input","keys":128}'); $r.ReadLine() | Out-Null   # Start held
  Start-Sleep -Milliseconds $HoldMs
  $w.WriteLine('{"id":2,"cmd":"set_input","keys":8}'); $r.ReadLine() | Out-Null     # Right
  Start-Sleep -Milliseconds 800
  $w.WriteLine('{"id":3,"cmd":"set_input","keys":0}'); $r.ReadLine() | Out-Null
  $c.Close(); "input sent"
} catch { "input err: $_" }
if (-not $p.HasExited) { $p.WaitForExit(20000) | Out-Null }
if (-not $p.HasExited) { $p.Kill() }
"exit=$($p.ExitCode)"
