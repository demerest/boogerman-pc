# s96: scan the whole ROM for BSR.W/JSR.L call sites of given targets.
param(
    [string]$Targets = '71E6,720E,7214,515A,13C6',
    [ValidateSet('US', 'EU')]
    [string]$Rom = 'US'
)
$ErrorActionPreference = 'Stop'
$path = if ($Rom -eq 'US') { 'S:\home\dev\boogerman-pc\Boogerman (U) [!].gen' } else { 'S:\home\dev\boogerman-pc\Boogerman (E) [!].gen' }
$r = [IO.File]::ReadAllBytes($path)
$t = @($Targets.Split(',') | ForEach-Object { [Convert]::ToInt32($_, 16) })
for ($p = 0; $p -lt $r.Length - 6; $p += 2) {
    if ($r[$p] -eq 0x61 -and $r[$p + 1] -eq 0x00) {
        $d = $r[$p + 2] * 256 + $r[$p + 3]
        if ($d -ge 32768) { $d -= 65536 }
        $tg = $p + 2 + $d
        if ($t -contains $tg) { 'BSR {0:X4} -> {1:X4}' -f $p, $tg }
    }
    elseif ($r[$p] -eq 0x61) {
        $d = $r[$p + 1]; if ($d -ge 128) { $d -= 256 }
        $tg = $p + 2 + $d
        if ($t -contains $tg) { 'BSR.S {0:X4} -> {1:X4}' -f $p, $tg }
    }
    elseif ($r[$p] -eq 0x4E -and $r[$p + 1] -eq 0xB9) {
        $a = $r[$p + 2] * 16777216 + $r[$p + 3] * 65536 + $r[$p + 4] * 256 + $r[$p + 5]
        if ($t -contains $a) { 'JSR {0:X4} -> {1:X4}' -f $p, $a }
    }
}
