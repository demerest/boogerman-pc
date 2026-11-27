# s71: windowed ram-shot WT parser (frame:addr=value hex). Like s70-wt but
# -From/-To restrict the frame window (pause/spawn-span analysis without the
# per-frame 0516 oscillation flood).
param(
    [string]$Tag = 's71wP',
    [string]$Addrs = '244,6d0,632,222',
    [int]$From = 0,
    [int]$To = 1000000
)
$ErrorActionPreference = 'Stop'
$dom = [IO.File]::ReadAllText("S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html")
$m = [regex]::Match($dom, 'WT ([^V]*) VID')
if (-not $m.Success) { "NO WT"; exit 1 }
$want = @{}; foreach ($a in $Addrs.Split(',')) { $want[$a.Trim()] = $true }
foreach ($e in $m.Groups[1].Value.Split(',')) {
    $e = $e.Trim(); if (-not $e) { continue }
    $p = $e.IndexOf(':'); $q = $e.IndexOf('=')
    if ($p -lt 0 -or $q -lt 0) { continue }
    $f = [int]$e.Substring(0, $p)
    if ($f -lt $From -or $f -gt $To) { continue }
    $a = $e.Substring($p + 1, $q - $p - 1); $v = $e.Substring($q + 1)
    if ($want.ContainsKey($a)) { "f=$f $a=$v" }
}