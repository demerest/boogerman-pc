# s64-webdump.ps1 - parse a ram-shot dump-dom capture: MODES / GATES / filtered WT / VID.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File s64-webdump.ps1 -Dom <path> [-Addrs 244,254,1506]
param(
    [string]$Dom = 'S:\home\dev\boogerman-pc\native\captures-us\s64webA-dom.html',
    [string]$Addrs = '244,254,1506,2ba,a62,284,2b4',
    [switch]$Vid
)
$ErrorActionPreference = 'Stop'
$h = Get-Content -Raw -LiteralPath $Dom
$i = $h.IndexOf('SHOTDONE')
if ($i -lt 0) {
    $e = $h.IndexOf('ERR ')
    if ($e -ge 0) { 'ERR: ' + $h.Substring($e, [Math]::Min(300, $h.Length - $e)) } else { 'NO SHOTDONE (first 300 chars): ' + $h.Substring(0, [Math]::Min(300, $h.Length)) }
    exit 1
}
$s = $h.Substring($i)
$j = $s.IndexOf(' VID ')
$head = $s.Substring(0, $j)
$k = $head.IndexOf(' MODES ')
$g = $head.IndexOf(' GATES ')
$w = $head.IndexOf(' WT ')
$wEnd = if ($w -ge 0) { $w } else { $head.Length }
'MODES ' + $head.Substring($k + 7, $g - $k - 7)
'GATES ' + $head.Substring($g + 7, $wEnd - $g - 7)
if ($w -ge 0) {
    $wt = $head.Substring($w + 4).Split(',')
    'WT total entries: ' + $wt.Count
    $set = @{}
    foreach ($a in $Addrs.Split(',')) { $set[$a.Trim()] = $true }
    foreach ($e in $wt) {
        $m = [regex]::Match($e, '^(\d+):([0-9a-f]+)=(.*)$')
        if ($m.Success -and $set.ContainsKey($m.Groups[2].Value)) { $e }
    }
}
if ($Vid) { 'VID ' + $s.Substring($j + 5, [Math]::Min(1300, $s.Length - $j - 5)) }
