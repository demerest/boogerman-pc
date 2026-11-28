# s98: scan the whole ROM for BRA.W/BRA.S/JMP.L sites of given targets
# (callscan covers BSR/JSR; the commit tail 005062 has no long-immediate
# users, so its entries must be relative branches or fallthrough).
param([string]$Targets = '5062')
$ErrorActionPreference = 'Stop'
$r = [IO.File]::ReadAllBytes('S:\home\dev\boogerman-pc\Boogerman (U) [!].gen')
$t = @($Targets.Split(',') | ForEach-Object { [Convert]::ToInt32($_, 16) })
for ($p = 0; $p -lt $r.Length - 6; $p += 2) {
    if ($r[$p] -eq 0x60 -and $r[$p + 1] -eq 0x00) {
        $d = $r[$p + 2] * 256 + $r[$p + 3]
        if ($d -ge 32768) { $d -= 65536 }
        $tg = $p + 2 + $d
        if ($t -contains $tg) { 'BRA.W {0:X4} -> {1:X4}' -f $p, $tg }
    }
    elseif ($r[$p] -eq 0x60 -and $r[$p + 1] -ne 0x00) {
        $d = $r[$p + 1]; if ($d -ge 128) { $d -= 256 }
        $tg = $p + 2 + $d
        if ($t -contains $tg) { 'BRA.S {0:X4} -> {1:X4}' -f $p, $tg }
    }
    elseif ($r[$p] -eq 0x4E -and $r[$p + 1] -eq 0xF9) {
        $a = $r[$p + 2] * 16777216 + $r[$p + 3] * 65536 + $r[$p + 4] * 256 + $r[$p + 5]
        if ($t -contains $a) { 'JMP {0:X4} -> {1:X4}' -f $p, $a }
    }
}
