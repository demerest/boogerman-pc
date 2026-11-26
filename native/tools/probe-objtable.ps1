param([int]$SleepMs = 15000, [switch]$TitleAssist)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
if ($TitleAssist) { $env:GENESIS_TITLE_ASSIST='1' } else { Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue }
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\s52h"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$p=Start-Process -FilePath $exe -ArgumentList ('"'+$rom+'"') -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
Start-Sleep -Milliseconds $SleepMs
try {
  $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
  $s.ReadTimeout=3000; $s.WriteTimeout=3000
  $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
  foreach ($addr in @('0xFF1A0E','0xFF1A10','0xFF1A12','0xFF1A14','0xFF2212','0xFF045E','0xFF045A','0xFF0260','0xFF0516')) {
    $w.WriteLine('{"id":2,"cmd":"read_memory","addr":"'+$addr+'","size":8}'); $addr+' '+$r.ReadLine()
  }
  $c.Close()
} catch { "probe err: $_" }
if (-not $p.HasExited) { $p.Kill() }
"done"
