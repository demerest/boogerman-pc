# s67: word-diff two web RAMDUMP dom captures (same frame, different inputs).
# Values printed big-endian (byte-swapped per word, matching WT conventions).
param(
    [string]$A = 'S:\home\dev\boogerman-pc\native\captures-us\s67w1p-dom.html',
    [string]$B = 'S:\home\dev\boogerman-pc\native\captures-us\s67w2-dom.html',
    [int]$Max = 400
)
$ErrorActionPreference = 'Stop'
function Ram([string]$p) {
    $d = [IO.File]::ReadAllText($p)
    $m = [regex]::Match($d, 'RAMDUMP ([A-Za-z0-9+/=]{1000,})')
    if (-not $m.Success) { throw "no RAMDUMP in $p" }
    return [Convert]::FromBase64String($m.Groups[1].Value)
}
[byte[]]$a = Ram $A; [byte[]]$b = Ram $B
"lenA=$($a.Length) lenB=$($b.Length)"
$n = [Math]::Min($a.Length, $b.Length)
$diffs = @()
for ($o = 0; $o -lt $n; $o += 2) {
    # buffer is little-endian per word: swap to big-endian game values
    $wa = [int]$a[$o + 1] * 256 + [int]$a[$o]
    $wb = [int]$b[$o + 1] * 256 + [int]$b[$o]
    if ($wa -ne $wb) { $diffs += ('{0:X4}: {1:X4}->{2:X4}' -f $o, $wa, $wb) }
}
"diff words: $($diffs.Count)"
$diffs | Select-Object -First $Max
