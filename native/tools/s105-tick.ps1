# s105: sub-layer tick-rate ledger. Native OBJ-TL 1A5A stores (pc=00498A decrement)
# and 1A56/1A44 events vs web per-frame 1a5a/1a56/1a44 transitions, aligned by 0286.
param(
    [string]$NativeTag = 's104s',
    [string]$WebTag = 's104x',
    [int]$Lo = 1800,
    [int]$Hi = 2800,
    [int]$Show = 100
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native\captures-us'

# native: per-frame event lists
$nf = @{}
foreach ($ln in [IO.File]::ReadAllLines("$root\$NativeTag\err.log")) {
    $m = [regex]::Match($ln, '\[OBJ-TL\] f=(\d+) pc=([0-9A-Fa-f]+) a=FF([0-9A-Fa-f]+) v=([0-9A-Fa-f]+)')
    if (-not $m.Success) { continue }
    $f = [int]$m.Groups[1].Value
    if ($f -lt $Lo -or $f -gt $Hi) { continue }
    $a = $m.Groups[3].Value.ToUpper()
    if ($a -notin @('0286', '1A5A', '1A56', '1A44', '1A10')) { continue }
    if (-not $nf.ContainsKey($f)) { $nf[$f] = @{ c = -1; e = (New-Object System.Collections.ArrayList) } }
    $v = $m.Groups[4].Value.ToUpper()
    $pc = $m.Groups[2].Value.ToUpper()
    if ($a -eq '0286') { $nf[$f].c = [Convert]::ToInt32($v, 16); continue }
    [void]$nf[$f].e.Add(('{0}:{1}={2}' -f $pc, $a, $v))
}
# web: per-frame samples, transition detection
$wf = @{}
$prev = @{}
foreach ($ln in [IO.File]::ReadAllLines("$root\$WebTag\trace-web.txt")) {
    $p = $ln.Split(' ')
    if ($p.Count -lt 2) { continue }
    $f = [int]$p[0]
    if ($f -lt $Lo -or $f -gt $Hi) { continue }
    $kv = @{}
    foreach ($t in $p[1..($p.Count - 1)]) { $k, $v = $t.Split('='); $kv[$k] = $v }
    $e = New-Object System.Collections.ArrayList
    foreach ($k in @('1a5a', '1a56', '1a44', '1a10')) {
        if (-not $kv.ContainsKey($k)) { continue }
        if ($prev.ContainsKey($k) -and $prev[$k] -ne $kv[$k]) { [void]$e.Add(('{0}:{1}={2}' -f $k, $k, $kv[$k])) }
        $prev[$k] = $kv[$k]
    }
    $wf[$f] = @{ c = [Convert]::ToInt32($kv['286'], 16); e = $e }
}

"--- native (f c286 events) ---"
$n = 0
foreach ($f in ($nf.Keys | Sort-Object)) {
    if ($nf[$f].e.Count -eq 0) { continue }
    '{0,5} {1,4:X} | {2}' -f $f, $nf[$f].c, ($nf[$f].e -join ' ')
    if (++$n -ge $Show) { break }
}
"--- web (f c286 transitions) ---"
$n = 0
foreach ($f in ($wf.Keys | Sort-Object)) {
    if ($wf[$f].e.Count -eq 0) { continue }
    '{0,5} {1,4:X} | {2}' -f $f, $wf[$f].c, ($wf[$f].e -join ' ')
    if (++$n -ge $Show) { break }
}
"--- per c286: native 498A decrements / 1A56 writes / 1A44 writes | web 1a5a changes / 1a56 changes / 1a44 changes ---"
$nc = @{}; $wc = @{}
foreach ($f in $nf.Keys) {
    $c = $nf[$f].c
    if (-not $nc.ContainsKey($c)) { $nc[$c] = @(0, 0, 0) }
    foreach ($ev in $nf[$f].e) {
        if ($ev -match '^00498A:1A5A') { $nc[$c][0]++ }
        elseif ($ev -match ':1A56=') { $nc[$c][1]++ }
        elseif ($ev -match ':1A44=') { $nc[$c][2]++ }
    }
}
foreach ($f in $wf.Keys) {
    $c = $wf[$f].c
    if (-not $wc.ContainsKey($c)) { $wc[$c] = @(0, 0, 0) }
    foreach ($ev in $wf[$f].e) {
        if ($ev -match ':1a5a=') { $wc[$c][0]++ }
        elseif ($ev -match ':1a56=') { $wc[$c][1]++ }
        elseif ($ev -match ':1a44=') { $wc[$c][2]++ }
    }
}
$cs = @($nc.Keys) + @($wc.Keys) | Sort-Object -Unique
foreach ($c in $cs) {
    $a = if ($nc.ContainsKey($c)) { $nc[$c] } else { @(0, 0, 0) }
    $b = if ($wc.ContainsKey($c)) { $wc[$c] } else { @(0, 0, 0) }
    $mark = if ($a[0] -ne $b[0] -or $a[1] -ne $b[1] -or $a[2] -ne $b[2]) { ' <<<' } else { '' }
    'c={0:X4} nat={1}/{2}/{3} web={4}/{5}/{6}{7}' -f $c, $a[0], $a[1], $a[2], $b[0], $b[1], $b[2], $mark
}
