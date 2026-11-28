# s101: align native OBJ-TL vs web per-frame trace by stream idx (2b6), diff X/Y/pad.
param(
    [string]$NativeTag = 's101a',
    [string]$WebTag = 's101w',
    [int]$IdxLo = 0x1C,
    [int]$IdxHi = 0x48
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native\captures-us'
$addrs = @(0x286,0x2b4,0x2b6,0x2b8,0x1a2e,0x1a30,0x1a32,0x1a34)
# native: last store per frame wins
$nat = @{}
foreach ($line in [IO.File]::ReadAllLines("$root\$NativeTag\err.log")) {
    if ($line -notmatch '^\[OBJ-TL\] f=(\d+) pc=([0-9A-F]+) a=FF([0-9A-F]+) v=([0-9A-F]+)') { continue }
    $f = [int]$Matches[1]; $a = [Convert]::ToInt32($Matches[3],16); $v = [Convert]::ToInt32($Matches[4],16)
    if ($f -lt 1800 -or $f -gt 2800) { continue }
    if ($addrs -notcontains $a) { continue }
    if (-not $nat.ContainsKey($f)) { $nat[$f] = @{} }
    $nat[$f][$a] = $v
}
# web: per-frame sample
$web = @{}
foreach ($line in [IO.File]::ReadAllLines("$root\$WebTag\trace-web.txt")) {
    $p = $line -split ' '
    $f = [int]$p[0]; $h = @{}
    for ($i=1;$i -lt $p.Count;$i++) { $kv=$p[$i] -split '='; $h[[Convert]::ToInt32($kv[0],16)] = [Convert]::ToInt32($kv[1],16) }
    $web[$f] = $h
}
function series($map, [switch]$Running) {
    $rows = New-Object System.Collections.ArrayList
    $prevIdx = -1; $tick = 0; $state = @{}
    foreach ($f in ($map.Keys | Sort-Object)) {
        $h = $map[$f]
        if ($Running) { foreach ($k in $h.Keys) { $state[$k] = $h[$k] }; $h = $state }
        if (-not $h.ContainsKey(0x2b6)) { continue }
        $idx = $h[0x2b6]
        if ($idx -ne $prevIdx) { $tick = 0; $prevIdx = $idx } else { $tick++ }
        if ($idx -lt $IdxLo -or $idx -gt $IdxHi) { continue }
        $g = { param($a) if ($h.ContainsKey($a)) { '{0:x4}' -f $h[$a] } else { '----' } }
        [void]$rows.Add(('{0,5} idx={1:x2} t={2,2} X={3} Y={4} pad={5} c286={6}' -f $f,$idx,$tick,(& $g 0x1a32),(& $g 0x1a2e),(& $g 0x2b8),(& $g 0x286)))
    }
    return $rows
}
"=== NATIVE ==="; series $nat -Running
"=== WEB ==="; series $web -Running