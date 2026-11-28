# s104: player-coroutine resume cadence, native OBJ-TL vs web per-frame samples.
param(
    [string]$NativeTag = 's104m',
    [string]$WebTag = 's104w',
    [int]$Lo = 1800,
    [int]$Hi = 2800,
    [int]$Show = 60
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native\captures-us'

# native: carry last word per addr; a resume step = frame-flush change of (1a12<<16)|1a14
$cur = @{}
$nsteps = New-Object System.Collections.ArrayList
$nc286 = @{}
$pf = -1; $ppc = ''; $nlast = $null
function Flush-Native([int]$f, [string]$pc) {
    if ($f -lt $Lo -or $f -gt $Hi) { return }
    if (-not ($cur.ContainsKey('1A12') -and $cur.ContainsKey('1A14'))) { return }
    $r = ($cur['1A12'] -shl 16) -bor $cur['1A14']
    if ($null -eq $script:nlast -or $r -ne $script:nlast) {
        [void]$nsteps.Add([pscustomobject]@{ f = $f; pc = $pc; r = $r })
        $script:nlast = $r
    }
}
foreach ($ln in [IO.File]::ReadAllLines("$root\$NativeTag\err.log")) {
    $m = [regex]::Match($ln, '\[OBJ-TL\] f=(\d+) pc=([0-9A-Fa-f]+) a=FF([0-9A-Fa-f]+) v=([0-9A-Fa-f]+)')
    if (-not $m.Success) { continue }
    $f = [int]$m.Groups[1].Value
    $a = $m.Groups[3].Value.ToUpper()
    $v = [Convert]::ToInt32($m.Groups[4].Value, 16)
    $pc = $m.Groups[2].Value.ToUpper()
    if ($f -ne $pf) { Flush-Native $pf $ppc; $pf = $f; $ppc = $pc }
    if ($a -eq '0286') { $nc286[$f] = $v; continue }
    if ($a -in @('1A12', '1A14')) { $cur[$a] = $v; $ppc = $pc }
}
Flush-Native $pf $ppc
# attach c286 (carry)
$c = 0; $ni = 0
foreach ($s in $nsteps) {
    for ($f = $s.f; $f -ge 0; $f--) { if ($nc286.ContainsKey($f)) { $c = $nc286[$f]; break } }
    $s | Add-Member -NotePropertyName c -NotePropertyValue $c
}

# web: per-frame samples
$wsteps = New-Object System.Collections.ArrayList
$wlast = $null
foreach ($ln in [IO.File]::ReadAllLines("$root\$WebTag\trace-web.txt")) {
    $p = $ln.Split(' ')
    if ($p.Count -lt 2) { continue }
    $f = [int]$p[0]
    $kv = @{}
    foreach ($t in $p[1..($p.Count - 1)]) { $k, $v = $t.Split('='); $kv[$k] = $v }
    if ($f -lt $Lo -or $f -gt $Hi) { continue }
    $r = ([Convert]::ToInt32($kv['1a12'], 16) -shl 16) -bor [Convert]::ToInt32($kv['1a14'], 16)
    if ($null -eq $wlast -or $r -ne $wlast) {
        [void]$wsteps.Add([pscustomobject]@{ f = $f; c = [Convert]::ToInt32($kv['286'], 16); r = $r })
        $wlast = $r
    }
}

"native steps=$($nsteps.Count) web steps=$($wsteps.Count) (window $Lo-$Hi)"
"--- native (f c286 resume pc) ---"
$nsteps | Select-Object -First $Show | ForEach-Object { '{0,5} {1,4:X} {2:X8} {3}' -f $_.f, $_.c, $_.r, $_.pc }
"--- web (f c286 resume) ---"
$wsteps | Select-Object -First $Show | ForEach-Object { '{0,5} {1,4:X} {2:X8}' -f $_.f, $_.c, $_.r }
"--- steps per c286 (native | web) ---"
$lo = [Math]::Min(($nsteps | Measure-Object c -Minimum).Minimum, ($wsteps | Measure-Object c -Minimum).Minimum)
$hi = [Math]::Max(($nsteps | Measure-Object c -Maximum).Maximum, ($wsteps | Measure-Object c -Maximum).Maximum)
for ($x = $lo; $x -le $hi; $x++) {
    $nn = @($nsteps | Where-Object { $_.c -eq $x }).Count
    $ww = @($wsteps | Where-Object { $_.c -eq $x }).Count
    if ($nn -ne $ww) { 'c={0:X4} native={1} web={2}  <<<' -f $x, $nn, $ww }
}
