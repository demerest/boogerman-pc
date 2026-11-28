# s105: aligned X / sub-resume-PC / grounded / pad ledger, native carry vs web sample.
param(
    [string]$NativeTag = 's105m',
    [string]$WebTag = 's105w',
    [int]$Lo = 2020,
    [int]$Hi = 2140
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native\captures-us'
$keys = @('0286', '02B6', '1A16', '1A32', '1A34', '1A44', '1A58', '0502', '050C')
$cur = @{}
$nat = @{}
foreach ($ln in [IO.File]::ReadAllLines("$root\$NativeTag\err.log")) {
    $m = [regex]::Match($ln, '\[OBJ-TL\] f=(\d+) pc=([0-9A-Fa-f]+) a=FF([0-9A-Fa-f]+) v=([0-9A-Fa-f]+)')
    if (-not $m.Success) { continue }
    $f = [int]$m.Groups[1].Value
    $a = '{0:X4}' -f [Convert]::ToInt32($m.Groups[3].Value, 16)
    if ($a -in $keys) { $cur[$a] = $m.Groups[4].Value.ToUpper() }
    if ($f -ge $Lo -and $f -le $Hi) { $nat[$f] = $cur.Clone() }
}
$web = @{}
foreach ($ln in [IO.File]::ReadAllLines("$root\$WebTag\trace-web.txt")) {
    $p = $ln.Split(' ')
    if ($p.Count -lt 2) { continue }
    $f = [int]$p[0]
    if ($f -lt $Lo -or $f -gt $Hi) { continue }
    $h = @{}
    foreach ($t in $p[1..($p.Count - 1)]) { $k, $v = $t.Split('='); $h[('{0:X4}' -f [Convert]::ToInt32($k, 16))] = $v.ToUpper() }
    $web[$f] = $h
}
'    f  c286 idx | natX  webX  | natSub webSub | n16 w16 | n502 w502 | n50c w50c'
for ($f = $Lo; $f -le $Hi; $f++) {
    $a = $nat[$f]; $b = $web[$f]
    if ($null -eq $a -or $null -eq $b) { continue }
    $g = { param($h, $k) if ($h.ContainsKey($k)) { $h[$k] } else { '----' } }
    '{0,5} {1,4} {2,4} | {3,5} {4,5} | {5,6} {6,6} | {7,3} {8,3} | {9,4} {10,4} | {11,4} {12,4}' -f `
        $f, (& $g $a '0286'), (& $g $a '02B6'), (& $g $a '1A32'), (& $g $b '1A32'), (& $g $a '1A58'), (& $g $b '1A58'), `
        (& $g $a '1A16'), (& $g $b '1A16'), (& $g $a '0502'), (& $g $b '0502'), (& $g $a '050C'), (& $g $b '050C')
}
