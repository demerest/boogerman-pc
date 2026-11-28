# s98: scan the ROM for absolute-word writers of a work-RAM address, or for
# long-immediate occurrences (resume-pointer setup sites).
# -Addr 0248 : every occurrence of 00 FF 02 48, with the preceding opcode word.
# -Long 5062 : every occurrence of the big-endian long 00 00 50 62.
param(
    [string]$Addr = '',
    [string]$Long = '',
    [ValidateSet('US', 'EU')]
    [string]$Rom = 'US'
)
$ErrorActionPreference = 'Stop'
$path = if ($Rom -eq 'US') { 'S:\home\dev\boogerman-pc\Boogerman (U) [!].gen' } else { 'S:\home\dev\boogerman-pc\Boogerman (E) [!].gen' }
$r = [IO.File]::ReadAllBytes($path)
if ($Long) {
    $v = [Convert]::ToInt32($Long, 16)
    $b = @((($v -shr 24) -band 255), (($v -shr 16) -band 255), (($v -shr 8) -band 255), ($v -band 255))
    for ($p = 0; $p -lt $r.Length - 8; $p += 2) {
        if ($r[$p] -eq $b[0] -and $r[$p + 1] -eq $b[1] -and $r[$p + 2] -eq $b[2] -and $r[$p + 3] -eq $b[3]) {
            $op = $r[$p - 2] * 256 + $r[$p - 1]
            $ctx = ''
            for ($i = $p - 2; $i -lt $p + 8; $i += 2) { $ctx += '{0:X4} ' -f ($r[$i] * 256 + $r[$i + 1]) }
            'LONG {0:X6} op={1:X4} : {2}' -f $p, $op, $ctx
        }
    }
}
else {
    $a = [Convert]::ToInt32($Addr, 16)
    $hi = ($a -shr 8) -band 255; $lo = $a -band 255
    for ($p = 2; $p -lt $r.Length - 6; $p += 2) {
        if ($r[$p] -eq 0 -and $r[$p + 1] -eq 255 -and $r[$p + 2] -eq $hi -and $r[$p + 3] -eq $lo) {
            $op = $r[$p - 2] * 256 + $r[$p - 1]
            $ctx = ''
            for ($i = $p - 2; $i -lt $p + 6; $i += 2) { $ctx += '{0:X4} ' -f ($r[$i] * 256 + $r[$i + 1]) }
            'W {0:X6} op={1:X4} : {2}' -f $p, $op, $ctx
        }
    }
}
