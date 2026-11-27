# s64-headerdiff.ps1 - diff the level header 0A50..0AD6 between the web-US oracle
# (ram-shot dump-dom WT log, word values) and native (OBJ-TL byte/word writes).
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File s64-headerdiff.ps1 -Web <dom.html> -Native <err.log>
param(
    [string]$Web = 'S:\home\dev\boogerman-pc\native\captures-us\s64webB-dom.html',
    [string]$Native = 'S:\home\dev\boogerman-pc\native\captures-us\s64a\err.log',
    [int]$From = 0xA50,
    [int]$To = 0xAD6
)
$ErrorActionPreference = 'Stop'
$h = Get-Content -Raw -LiteralPath $Web
$s = $h.Substring($h.IndexOf('SHOTDONE'))
$head = $s.Substring(0, $s.IndexOf(' VID '))
$w = $head.IndexOf(' WT ')
$webv = @{}
foreach ($e in $head.Substring($w + 4).Split(',')) {
    $m = [regex]::Match($e, '^(\d+):([0-9a-f]+)=(.*)$')
    if ($m.Success) {
        $k = [Convert]::ToInt32($m.Groups[2].Value, 16)
        $webv[$k] = [Convert]::ToInt32($m.Groups[3].Value, 16)
    }
}
$bytes = @{}
$depMin = -1; $depMax = -1
foreach ($line in [IO.File]::ReadLines($Native)) {
    $m = [regex]::Match($line, '\[OBJ-TL\] f=(\d+) pc=([0-9A-Fa-f]+) a=([0-9A-Fa-f]+) v=([0-9A-Fa-f]+) s=(\d)')
    if (-not $m.Success) { continue }
    $f = [int]$m.Groups[1].Value
    $a = [Convert]::ToInt32($m.Groups[3].Value, 16) -band 0xFFFF
    $v = [Convert]::ToInt32($m.Groups[4].Value, 16)
    $sz = [int]$m.Groups[5].Value
    if ($a -ge $From -and $a -le $To + 1) {
        if ($depMin -lt 0) { $depMin = $f }
        $depMax = $f
    }
    if ($sz -eq 2) {
        $bytes[$a] = ($v -shr 8) -band 0xFF
        $bytes[$a + 1] = $v -band 0xFF
    } else {
        $bytes[$a] = $v -band 0xFF
    }
}
'native header deposit frames: {0}..{1}' -f $depMin, $depMax
$diffs = 0
for ($a = $From; $a -le $To; $a += 2) {
    $wv = 0; if ($webv.ContainsKey($a)) { $wv = $webv[$a] }
    $nv = 0
    if ($bytes.ContainsKey($a)) { $nv += $bytes[$a] * 256 }
    if ($bytes.ContainsKey($a + 1)) { $nv += $bytes[$a + 1] }
    $tag = 'OK  '
    if ($wv -ne $nv) { $tag = 'DIFF'; $diffs++ }
    '{0} {1:x4} web={2:x4} nat={3:x4}' -f $tag, $a, $wv, $nv
}
'diffs: {0}' -f $diffs
