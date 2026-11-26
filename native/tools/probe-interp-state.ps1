param([int]$SleepMs = 25000, [int]$Frames = 6000, [switch]$TitleAssist)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$env:GENESIS_FORCE_INTERP='1'
if ($TitleAssist) { $env:GENESIS_TITLE_ASSIST='1' } else { Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue }
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\s52d"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$a='"'+$rom+'" --exit-at-frame '+$Frames+' --capture-out "'+$out+'" --capture-from '+($Frames-100)+' --capture-to '+$Frames+' --capture-every 100'
$p=Start-Process -FilePath $exe -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
Start-Sleep -Milliseconds $SleepMs
try {
  $c=$null
  for ($i=0; $i -lt 10 -and -not $c; $i++) {
    try { $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400) } catch { Start-Sleep -Milliseconds 3000 }
  }
  if (-not $c) { throw 'no cmd connection after retries' }
  $s=$c.GetStream()
  $s.ReadTimeout=3000; $s.WriteTimeout=3000
  $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
  $w.WriteLine('{"id":1,"cmd":"get_registers"}'); 'REGS: '+$r.ReadLine()
  foreach ($addr in @('0xFF0516','0xFF05D4','0xFF05D6','0xFF0A65','0xFF0284','0xFF02BA','0xFF025A','0xFF025E','0xFF0276','0xFF0278','0xFF0502','0xFF050C','0xFF0508','0xFF02B4','0xFF02B8','0xA00FAD','0xA00FC2','0xFF0514','0xFF0512')) {
    $w.WriteLine('{"id":2,"cmd":"read_memory","addr":"'+$addr+'","size":4}'); $addr+' '+$r.ReadLine()
  }
  $c.Close()
} catch { "input err: $_" }
if (-not $p.HasExited) { $p.WaitForExit(30000) | Out-Null }
if (-not $p.HasExited) { $p.Kill() }
"exit=$($p.ExitCode)"
