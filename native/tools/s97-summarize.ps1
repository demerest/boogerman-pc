param(
  [string]$Path = 'S:\home\dev\boogerman-pc\native\captures-us\s97a\fmwrites.txt',
  [int]$From = 1690,
  [int]$To = 2613
)
# Per-frame audio-write summary: YM key-on/off ($28 data), non-silence DAC
# bytes ($2A/$2B data != 80), PSG writes, and total FM write counts.
$re = [regex]'^f=(\d+) sl=(\d+) (FM|PSG)\s+(?:p(\d) )?\$([0-9A-Fa-f]{2}) mc=\d+ wf=\d+ pcz=\$([0-9A-Fa-f]{4})'
$lastAddr = @{}
$frames = @{}
foreach ($line in [System.IO.File]::ReadLines($Path)) {
  $m = $re.Match($line)
  if (-not $m.Success) { continue }
  $f = [int]$m.Groups[1].Value
  if ($f -lt $From -or $f -gt $To) { continue }
  $sl = [int]$m.Groups[2].Value
  $kind = $m.Groups[3].Value
  $port = $m.Groups[4].Value
  $val = [Convert]::ToInt32($m.Groups[5].Value, 16)
  $pcz = $m.Groups[6].Value
  if (-not $frames.ContainsKey($f)) {
    $frames[$f] = @{ fm = 0; keys = @(); dac = @(); psg = @() }
  }
  $e = $frames[$f]
  if ($kind -eq 'PSG') { $e.psg += ("sl{0}:{1:X2}" -f $sl, $val); continue }
  $e.fm++
  $p = [int]$port
  if ($p -eq 0 -or $p -eq 2) { $lastAddr[$p] = $val; continue }
  $reg = $lastAddr[$p - 1]
  if ($reg -eq 0x28) { $e.keys += ("sl{0}:{1:X2}@{2}" -f $sl, $val, $pcz) }
  elseif (($reg -eq 0x2A -or $reg -eq 0x2B) -and $val -ne 0x80) { $e.dac += ("sl{0}:{1:X2}" -f $sl, $val) }
}
foreach ($f in ($frames.Keys | Sort-Object)) {
  $e = $frames[$f]
  $interesting = ($e.keys.Count -gt 0) -or ($e.dac.Count -gt 0) -or ($e.psg.Count -gt 0)
  if ($interesting -or ($f % 100) -eq 0) {
    $ks = if ($e.keys.Count) { ' keys=' + ($e.keys -join ',') } else { '' }
    $ds = if ($e.dac.Count) { ' dacnz=' + ($e.dac.Count) + '[' + (($e.dac | Select-Object -First 6) -join ',') + ']' } else { '' }
    $ps = if ($e.psg.Count) { ' psg=' + ($e.psg -join ',') } else { '' }
    "f={0} fm={1}{2}{3}{4}" -f $f, $e.fm, $ks, $ds, $ps
  }
}