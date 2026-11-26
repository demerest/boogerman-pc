param([int]$SleepMs = 15000, [string]$Tag = 's53c')
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue
Remove-Item Env:GENESIS_FORCE_INTERP -ErrorAction SilentlyContinue
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$p=Start-Process -FilePath $exe -ArgumentList ('"'+$rom+'"') -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
Start-Sleep -Milliseconds $SleepMs
try {
  $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
  $s.ReadTimeout=5000; $s.WriteTimeout=5000
  $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
  $w.WriteLine('{"id":2,"cmd":"read_memory","addr":"0xFF1A0E","size":2052}')
  $resp=$r.ReadLine() | ConvertFrom-Json
  $hex=$resp.hex
  $n=$hex.Length/2
  $b=New-Object byte[] $n
  for ($j=0; $j -lt $n; $j++) { $b[$j]=[Convert]::ToByte($hex.Substring($j*2,2),16) }
  $a=0xFF1A0E; $i=0; $seen=@{}
  while ($a -lt 0xFF220E -and $i -lt 80) {
    $off=$a-0xFF1A0E
    $w0=$b[$off]*256+$b[$off+1]; $w2=$b[$off+2]*256+$b[$off+3]; $w68=$b[$off+68]*256+$b[$off+69]
    $stride=$w0 -band 0x7FFF
    ('{0:D2} a={1:X6} w0={2:X4} w2={3:X4} w68={4:X4} stride={5:X4}' -f $i,$a,$w0,$w2,$w68,$stride)
    if ($seen.ContainsKey($a)) { 'CYCLE at entry '+$i; break }
    $seen[$a]=1
    if ($stride -eq 0) { 'SPIN at entry '+$i; break }
    $a+=$stride; $i++
  }
  if ($a -ge 0xFF220E) { 'chain reaches table end OK' }
  $c.Close()
} catch { "probe err: $_" }
if (-not $p.HasExited) { $p.Kill() }
'done'
