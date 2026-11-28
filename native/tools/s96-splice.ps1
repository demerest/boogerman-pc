# s96: splice the user's recorded sewers crossing (play-input.log 6849..9600,
# rebased by Delta) onto the proven replay-best prefix (cut before its flush).
param(
    [int]$Delta = 3482,
    [int]$From = 6849,
    [int]$To = 9600
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native'
$best = Get-Content "$root\tools\replay-best.input"
$idx = -1
for ($i = 0; $i -lt $best.Count; $i++) {
    if ($best[$i] -like '# --- s91 genuine flush*') { $idx = $i; break }
}
if ($idx -lt 0) { throw 'flush marker not found' }
$prefix = $best[0..($idx - 1)]
$log = Get-Content "$root\build\play-input.log"
$seg = @()
foreach ($line in $log) {
    if ($line -match '^(\d+)\s+(.*)$') {
        $f = [int]$Matches[1]
        if ($f -ge $From -and $f -le $To) {
            $seg += ('{0} {1}' -f ($f + $Delta), $Matches[2])
        }
    }
}
$out = $prefix + $seg + @('RELEASE', 'WAIT 300')
Set-Content -Path "$root\tools\s96c.input" -Value $out -Encoding ASCII
"prefix=$($prefix.Count) seg=$($seg.Count) total=$($out.Count)"
