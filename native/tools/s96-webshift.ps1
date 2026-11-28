# s96: re-phase the recorded SCRIPT route (s95rec/rec.input) for the web
# oracle: global shift Delta (web title ~107f later), truncate at ledge stop.
param([int]$Delta = 107, [int]$To = 11368)
$ErrorActionPreference = 'Stop'
$map = @{ 'UP' = 4; 'DOWN' = 5; 'LEFT' = 6; 'RIGHT' = 7; 'B' = 0; 'C' = 8; 'A' = 1; 'START' = 3 }
$lines = Get-Content 'S:\home\dev\boogerman-pc\native\captures-us\s95rec\rec.input'
$ev = @()
foreach ($l in $lines) {
    if ($l -match '^(\d+)\s+(.*)$') { $ev += , @([int]$Matches[1], $Matches[2]) }
}
$tl = @()
for ($i = 0; $i -lt $ev.Count; $i++) {
    $f = $ev[$i][0] + $Delta; $m = $ev[$i][1]
    if ($f -ge $To + $Delta) { break }
    $end = $To + $Delta
    if ($i + 1 -lt $ev.Count) { $end = [Math]::Min($To + $Delta, $ev[$i + 1][0] + $Delta) }
    if ($m -ne '-') {
        foreach ($b in $m.Split('+')) { $tl += ('{0}@{1}:{2}' -f $map[$b], $f, ($end - $f)) }
    }
}
$text = $tl -join ','
Set-Content -Path 'S:\home\dev\boogerman-pc\native\tools\s96w2-timeline.txt' -Value $text -Encoding ASCII -NoNewline
"presses=$($tl.Count) len=$($text.Length)"
