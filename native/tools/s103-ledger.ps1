# s103: per-frame aligned X/Y/velocity ledger native OBJ-TL vs web trace, by stream idx (2b6).
# -Detail appends native store-level pc=a:v pairs for the velocity/position words.
param(
    [string]$NativeTag = 's102c',
    [string]$WebTag = 's102w',
    [int]$IdxLo = 0x08,
    [int]$IdxHi = 0x20,
    [switch]$Detail
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native\captures-us'
$stateAddrs = @(0x286,0x2b6,0x2b8,0x1a2e,0x1a32,0x1a40,0x1a44,0x1a46,0x1a48)
$detailAddrs = @(0x1a2e,0x1a32,0x1a34,0x1a40,0x1a44,0x1a46)
$nat = @{}
foreach ($line in [IO.File]::ReadAllLines("$root\$NativeTag\err.log")) {
    if ($line -notmatch '^\[OBJ-TL\] f=(\d+) pc=([0-9A-F]+) a=FF([0-9A-F]+) v=([0-9A-F]+)') { continue }
    $f = [int]$Matches[1]; $pc = $Matches[2]; $a = [Convert]::ToInt32($Matches[3],16); $v = [Convert]::ToInt32($Matches[4],16)
    if ($f -lt 1800 -or $f -gt 2800) { continue }
    if (-not $nat.ContainsKey($f)) { $nat[$f] = @{ s = @{}; d = (New-Object System.Collections.ArrayList) } }
    if ($stateAddrs -contains $a) { $nat[$f].s[$a] = $v }
    if ($Detail -and $detailAddrs -contains $a) { [void]$nat[$f].d.Add(('{0}={1:x4}:{2:x4}' -f $pc,$a,$v)) }
}
$web = @{}
foreach ($line in [IO.File]::ReadAllLines("$root\$WebTag\trace-web.txt")) {
    $p = $line -split ' '
    $f = [int]$p[0]; $h = @{}
    for ($i=1;$i -lt $p.Count;$i++) { $kv=$p[$i] -split '='; $h[[Convert]::ToInt32($kv[0],16)] = [Convert]::ToInt32($kv[1],16) }
    $web[$f] = $h
}
function series($map, [switch]$Running, [switch]$IsNat) {
    $rows = New-Object System.Collections.ArrayList
    $prevIdx = -1; $tick = 0; $state = @{}
    foreach ($f in ($map.Keys | Sort-Object)) {
        $h = $map[$f]
        if ($IsNat) { $st = $h.s; $dd = $h.d } else { $st = $h; $dd = $null }
        if ($Running) { foreach ($k in $st.Keys) { $state[$k] = $st[$k] }; $st = $state }
        if (-not $st.ContainsKey(0x2b6)) { continue }
        $idx = $st[0x2b6]
        if ($idx -ne $prevIdx) { $tick = 0; $prevIdx = $idx } else { $tick++ }
        if ($idx -lt $IdxLo -or $idx -gt $IdxHi) { continue }
        $g = { param($a) if ($st.ContainsKey($a)) { '{0:x4}' -f $st[$a] } else { '----' } }
        $row = ('{0,5} idx={1:x2} t={2,2} X={3} Y={4} v40={5} v44={6} v46={7} c286={8}' -f $f,$idx,$tick,(& $g 0x1a32),(& $g 0x1a2e),(& $g 0x1a40),(& $g 0x1a44),(& $g 0x1a46),(& $g 0x286))
        if ($IsNat -and $dd -and $dd.Count -gt 0) { $row += ' | ' + ($dd -join ' ') }
        [void]$rows.Add($row)
    }
    return $rows
}
"=== NATIVE ==="; series $nat -Running -IsNat
"=== WEB ==="; series $web -Running