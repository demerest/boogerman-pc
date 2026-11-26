# diff-ram.ps1 - phase-matched work-RAM diff: native DUMP_RAM (canonical byte
# order) vs web ram-dump (BP.core.ram(), little-endian per word -> swap pairs).
# Usage: powershell -File diff-ram.ps1 -NativeBin <path> -WebBin <path> [-Skip <hex ranges>]
param(
  [string]$NativeBin = 'S:\home\dev\boogerman-pc\native\captures-us\s57d\ram1200.bin',
  [string]$WebBin = 'S:\home\dev\boogerman-pc\native\captures-us\web-s57-ram1900.bin',
  [int]$MaxRanges = 60,
  [string]$Filter = ''
)
$ErrorActionPreference = 'Stop'
$n = [System.IO.File]::ReadAllBytes($NativeBin)
$w = [System.IO.File]::ReadAllBytes($WebBin)
$len = [Math]::Min($n.Length, $w.Length)
for ($i = 0; $i + 1 -lt $len; $i += 2) { $t = $w[$i]; $w[$i] = $w[$i+1]; $w[$i+1] = $t }
$ranges = @(); $start = -1
for ($i = 0; $i -lt $len; $i++) {
  if ($n[$i] -ne $w[$i]) { if ($start -lt 0) { $start = $i } }
  else { if ($start -ge 0) { $ranges += ,@($start, ($i - 1)); $start = -1 } }
}
if ($start -ge 0) { $ranges += ,@($start, ($len - 1)) }
"native=$($n.Length) web=$($w.Length) diffranges=$($ranges.Count)"
$filters = @()
if ($Filter) { foreach ($f in $Filter.Split(',')) { $p = $f.Split('-'); $filters += ,@([Convert]::ToInt32($p[0],16), [Convert]::ToInt32($p[1],16)) } }
$shown = 0
foreach ($r in $ranges) {
  if ($shown -ge $MaxRanges) { '... (truncated)'; break }
  $a = $r[0]; $b = $r[1]
  if ($filters.Count) { $ok = $false; foreach ($f in $filters) { if ($a -le $f[1] -and $b -ge $f[0]) { $ok = $true } }; if (-not $ok) { continue } }
  $ns = ''; $ws = ''
  for ($i = $a; $i -le [Math]::Min($b, $a + 15); $i++) { $ns += '{0:X2} ' -f $n[$i]; $ws += '{0:X2} ' -f $w[$i] }
  'FF{0:X4}-FF{1:X4} ({2}b) N: {3}| W: {4}' -f $a, $b, ($b - $a + 1), $ns.Trim(), $ws.Trim()
  $shown++
}