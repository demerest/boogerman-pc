# s70: parse ram-shot WT timeline (frame:addr=value hex) from a s67-web shot dom.
# Prints change events for -Addrs; -Tick addr prints sampled values every -Every frames.
param(
    [string]$Tag = 's70wR',
    [string]$Addrs = '244,254,1506,632',
    [string]$Tick = '6d0',
    [int]$Every = 200,
    [string]$Tick2 = '632',
    [int]$Every2 = 150
)
$ErrorActionPreference = 'Stop'
$dom = [IO.File]::ReadAllText("S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html")
$m = [regex]::Match($dom, 'WT ([^V]*) VID')
if (-not $m.Success) { "NO WT"; exit 1 }
$want = @{}; foreach ($a in $Addrs.Split(',')) { $want[$a.Trim()] = $true }
$lastTick = -1; $lastTick2 = -1
foreach ($e in $m.Groups[1].Value.Split(',')) {
    $e = $e.Trim(); if (-not $e) { continue }
    $p = $e.IndexOf(':'); $q = $e.IndexOf('=')
    if ($p -lt 0 -or $q -lt 0) { continue }
    $f = [int]$e.Substring(0, $p); $a = $e.Substring($p + 1, $q - $p - 1); $v = $e.Substring($q + 1)
    if ($want.ContainsKey($a)) { "f=$f $a=$v" }
    elseif ($a -eq $Tick -and $f - $lastTick -ge $Every) { "f=$f $a=$v"; $lastTick = $f }
    elseif ($a -eq $Tick2 -and $f - $lastTick2 -ge $Every2) { "f=$f $a=$v"; $lastTick2 = $f }
}