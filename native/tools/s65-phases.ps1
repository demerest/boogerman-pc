# s65: extract level-pipeline phase timelines from native OBJ-TL and web WT.
# Native: [OBJ-TL] f=N pc=XXXXXX a=XXXXXX v=XXXXXX s=1|2 (full 24-bit addr).
# Web:    SHOTDONE ... WT n:addr=val,... VID ...
# Prints cont (1A14) transitions, 1A5A=FFFF releases, 0698 scroll changes,
# spawn-table (2322+) write counts; web side same minus scroll (not watched).
param(
    [string]$Native = 'S:\home\dev\boogerman-pc\native\captures-us\s64d\err.log',
    [string]$WebDom = 'S:\home\dev\boogerman-pc\native\captures-us\s64webE-dom.html',
    [int]$NFrom = 2400,
    [int]$WFrom = 0,
    [switch]$Detail
)

$nl = [IO.File]::ReadAllLines($Native)
$cont = @(); $cont1 = @(); $ffff = @(); $scr = @(); $spawn = @{}
$tim = @(); $t24 = @()
$lastC = ''; $lastC1 = ''; $lastS = ''; $lastT = ''; $lastT24 = ''
foreach ($line in $nl) {
    if ($line -notmatch '^\[OBJ-TL\] f=(\d+) pc=([0-9A-Fa-f]+) a=([0-9A-Fa-f]+) v=([0-9A-Fa-f]+) s=(\d)') { continue }
    $f = [int]$Matches[1]; $a = $Matches[3]; $v = $Matches[4]; $s = [int]$Matches[5]
    if ($a -eq 'FF1A14') {
        if ($v -ne $lastC) { $cont += ,@($f, $v); $lastC = $v }
    } elseif ($a -eq 'FF19DE') {
        if ($v -ne $lastC1) { $cont1 += ,@($f, $v); $lastC1 = $v }
    } elseif ($a -eq 'FF1A5A') {
        if ($v -eq '00FFFF') { $ffff += $f }
        if ($v -ne $lastT) { $tim += ,@($f, $v); $lastT = $v }
    } elseif ($a -eq 'FF1A24') {
        if ($v -ne $lastT24) { $t24 += ,@($f, $v); $lastT24 = $v }
    } elseif ($a -eq 'FF0698') {
        if ($v -ne $lastS) { $scr += ,@($f, $v); $lastS = $v }
    } elseif ($a -match '^FF23[2-9A-Fa-f][0-9A-Fa-f]$' -and $s -eq 2) {
        if (-not $spawn.ContainsKey($f)) { $spawn[$f] = 0 }
        $spawn[$f]++
    }
}
Write-Output "== NATIVE $Native (from $NFrom) =="
Write-Output ('cont transitions: ' + (($cont | Where-Object { $_[0] -ge $NFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
Write-Output ('obj1 cont (19DE): ' + (($cont1 | Where-Object { $_[0] -ge $NFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
Write-Output ('1A5A=FFFF: ' + ($ffff -join ' '))
Write-Output ('0698: ' + (($scr | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
$sp = $spawn.GetEnumerator() | Sort-Object Name
Write-Output ('spawn frames(count): ' + (($sp | ForEach-Object { $_.Name.ToString() + '(' + $_.Value + ')' }) -join ' '))
if ($Detail) {
    Write-Output ('1A5A seq: ' + (($tim | Where-Object { $_[0] -ge $NFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
    Write-Output ('1A24 seq: ' + (($t24 | Where-Object { $_[0] -ge $NFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
}

$dom = [IO.File]::ReadAllText($WebDom)
$w0 = $dom.IndexOf(' WT '); $w1 = $dom.IndexOf(' VID ')
if ($w0 -lt 0) { Write-Output '== WEB: no WT =='; exit 0 }
$wEnd = if ($w1 -ge 0) { $w1 } else { $dom.Length }
$wt = $dom.Substring($w0 + 4, $wEnd - $w0 - 4).Split(',')
$wc = @(); $wc1 = @(); $wf = @(); $wtim = @(); $wt24 = @(); $wscr = @(); $modes = ''
$lastW1 = ''; $lastWT = ''; $lastWT24 = ''; $lastWS = ''
$m0 = $dom.IndexOf(' MODES '); $m1 = $dom.IndexOf(' GATES ')
if ($m0 -ge 0 -and $m1 -gt $m0) { $modes = $dom.Substring($m0 + 7, $m1 - $m0 - 7) }
$lastW = ''
$first = @{}
foreach ($e in $wt) {
    if ($e -notmatch '^(\d+):([0-9a-f]+)=([0-9a-f]+)$') { continue }
    $f = [int]$Matches[1]; $a = $Matches[2]; $v = $Matches[3]
    if ($a -eq '1a14') { if ($v -ne $lastW) { $wc += ,@($f, $v); $lastW = $v } }
    elseif ($a -eq '19de') { if ($v -ne $lastW1) { $wc1 += ,@($f, $v); $lastW1 = $v } }
    elseif ($a -eq '1a5a') {
        if ($v -eq 'ffff') { $wf += $f }
        if ($v -ne $lastWT) { $wtim += ,@($f, $v); $lastWT = $v }
    } elseif ($a -eq '1a24') {
        if ($v -ne $lastWT24) { $wt24 += ,@($f, $v); $lastWT24 = $v }
    } elseif ($a -eq '698') {
        if ($v -ne $lastWS) { $wscr += ,@($f, $v); $lastWS = $v }
    } elseif ($a -in @('244','254','1506','5b4','5d4','5d6')) {
        if (-not $first.ContainsKey($a + '=' + $v)) { $first[$a + '=' + $v] = $f }
    }
}
Write-Output "== WEB $WebDom (from $WFrom) =="
Write-Output ('MODES: ' + $modes)
Write-Output ('first writes: ' + (($first.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Name + '@' + $_.Value }) -join ' '))
Write-Output ('cont transitions: ' + (($wc | Where-Object { $_[0] -ge $WFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
Write-Output ('obj1 cont (19DE): ' + (($wc1 | Where-Object { $_[0] -ge $WFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
Write-Output ('1A5A=FFFF: ' + ($wf -join ' '))
Write-Output ('0698: ' + (($wscr | Where-Object { $_[0] -ge $WFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
if ($Detail) {
    Write-Output ('1a5a seq: ' + (($wtim | Where-Object { $_[0] -ge $WFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
    Write-Output ('1a24 seq: ' + (($wt24 | Where-Object { $_[0] -ge $WFrom } | ForEach-Object { $_[0].ToString() + ':' + $_[1] }) -join ' '))
}
