# s96: convert the recorded pad-mask log into the web harness press timeline
# ("lrId@frame:hold,..." ; MD A->LR.Y=1, MD B->LR.B=0, MD C->LR.A=8).
param([int]$To = 7300)
$ErrorActionPreference = 'Stop'
$map = @{ 'UP' = 4; 'DOWN' = 5; 'LEFT' = 6; 'RIGHT' = 7; 'B' = 0; 'C' = 8; 'A' = 1; 'START' = 3 }
$lines = Get-Content 'S:\home\dev\boogerman-pc\native\build\play-input.log'
$ev = @()
foreach ($l in $lines) {
    if ($l -match '^(\d+)\s+(.*)$') { $ev += , @([int]$Matches[1], $Matches[2]) }
}
$tl = @()
for ($i = 0; $i -lt $ev.Count; $i++) {
    $f = $ev[$i][0]; $m = $ev[$i][1]
    if ($f -ge $To) { break }
    $end = $To
    if ($i + 1 -lt $ev.Count) { $end = [Math]::Min($To, $ev[$i + 1][0]) }
    if ($m -ne '-') {
        foreach ($b in $m.Split('+')) { $tl += ('{0}@{1}:{2}' -f $map[$b], $f, ($end - $f)) }
    }
}
$text = $tl -join ','
Set-Content -Path 'S:\home\dev\boogerman-pc\native\tools\s96w-timeline.txt' -Value $text -Encoding ASCII -NoNewline
"presses=$($tl.Count) len=$($text.Length)"
