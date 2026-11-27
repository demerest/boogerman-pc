# s64-abscan.ps1 - find absolute-long operands (00FFxxxx) in the ROM and print
# the surrounding words so the referencing instruction can be decoded.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File s64-abscan.ps1 -Targets 1A56,1A14 -Rom us
param(
    [string]$Targets = '1A56,1A14',
    [ValidateSet('us', 'eu')][string]$Rom = 'us'
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc'
$path = if ($Rom -eq 'us') { Join-Path $root 'Boogerman (U) [!].gen' } else { Join-Path $root 'Boogerman (E) [!].gen' }
$r = [IO.File]::ReadAllBytes($path)
foreach ($t in $Targets.Split(',')) {
    $a = [Convert]::ToInt32($t.Trim(), 16)
    $b0 = 0; $b1 = 0xFF; $b2 = ($a -shr 8) -band 0xFF; $b3 = $a -band 0xFF
    'target {0:X4}:' -f $a
    for ($i = 0; $i -lt $r.Length - 4; $i += 2) {
        if ($r[$i] -eq $b0 -and $r[$i + 1] -eq $b1 -and $r[$i + 2] -eq $b2 -and $r[$i + 3] -eq $b3) {
            $s = [Math]::Max(0, $i - 6)
            $words = @()
            for ($j = $s; $j -lt [Math]::Min($r.Length - 1, $i + 10); $j += 2) {
                $words += ('{0:X6}:{1:X4}' -f $j, ($r[$j] * 256 + $r[$j + 1]))
            }
            ($words -join ' ')
        }
    }
}
