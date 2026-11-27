# s68: native DUMP_RAM bin reader/differ. Bins are 64KB work RAM in guest bus
# order (big-endian per word: high byte at even offset), offset = addr & FFFF.
# -Show lists word addrs (hex, no FF prefix) and prints values from A (and B).
# Without -Show, prints word diffs A->B (big-endian values).
param(
    [string]$A = '',
    [string]$B = '',
    [string]$Show = '',
    [int]$Max = 400
)
$ErrorActionPreference = 'Stop'
function Ram([string]$p) {
    $b = [System.IO.File]::ReadAllBytes($p)
    if ($b.Length -ne 0x10000) { throw "bad bin length $($b.Length): $p" }
    return ,$b
}
function Word([byte[]]$b, [int]$o) { return ([int]$b[$o] * 256 + [int]$b[$o + 1]) }
if (-not $A) { throw 'need -A' }
$ba = Ram $A
if ($Show) {
    $bb = $null
    if ($B) { $bb = Ram $B }
    foreach ($t in $Show.Split(',')) {
        $t = $t.Trim(); if (-not $t) { continue }
        $o = [Convert]::ToInt32($t, 16)
        $va = Word $ba $o
        if ($bb) {
            $vb = Word $bb $o
            '{0:X4}: A={1:X4} B={2:X4}' -f $o, $va, $vb
        } else {
            '{0:X4}: {1:X4}' -f $o, $va
        }
    }
    return
}
if (-not $B) { throw 'need -B or -Show' }
$bb = Ram $B
$n = 0
for ($o = 0; $o -lt 0x10000; $o += 2) {
    $wa = Word $ba $o; $wb = Word $bb $o
    if ($wa -ne $wb) {
        $n++
        if ($n -le $Max) { '{0:X4}: {1:X4}->{2:X4}' -f $o, $wa, $wb }
    }
}
"diff words: $n"
