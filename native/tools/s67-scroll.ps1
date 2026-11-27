# s67: RAM-write timelines from web WT or native OBJ-TL, per address.
# Prints 100f samples, min/max, first-max frame, last change, change count.
# Addresses normalized to lowercase hex without leading zeros (web WT convention).
param(
    [string]$WebDom = '',
    [string]$Native = '',
    [int]$From = 2000,
    [string]$Addrs = '698,69a'
)
$ErrorActionPreference = 'Stop'
$want = @{}
foreach ($t in $Addrs.Split(',')) { $want[([Convert]::ToInt32($t.Trim(), 16)).ToString('x')] = $true }
function Norm([string]$a) { return ([Convert]::ToInt32($a, 16)).ToString('x') }
function Series([string]$src) {
    $s = @{}
    foreach ($k in $want.Keys) { $s[$k] = @() }
    if ($src -eq 'web') {
        $dom = [IO.File]::ReadAllText($WebDom)
        $w0 = $dom.IndexOf(' WT '); $w1 = $dom.IndexOf(' VID ')
        if ($w0 -lt 0) { return $s }
        $wEnd = if ($w1 -ge 0) { $w1 } else { $dom.Length }
        foreach ($e in $dom.Substring($w0 + 4, $wEnd - $w0 - 4).Split(',')) {
            if ($e -match '^(\d+):([0-9a-f]+)=([0-9a-f]+)$') {
                $a = Norm $Matches[2]
                if ($want.ContainsKey($a)) { $s[$a] += ,@([int]$Matches[1], [Convert]::ToInt32($Matches[3], 16)) }
            }
        }
    } else {
        foreach ($line in [IO.File]::ReadAllLines($Native)) {
            if ($line -match '^\[OBJ-TL\] f=(\d+) pc=[0-9A-Fa-f]+ a=([0-9A-Fa-f]+) v=([0-9A-Fa-f]+) s=\d') {
                $a = Norm $Matches[2].Substring(2)
                if ($want.ContainsKey($a)) { $s[$a] += ,@([int]$Matches[1], [Convert]::ToInt32($Matches[3], 16)) }
            }
        }
    }
    return $s
}
function Report($s, [string]$label) {
    "== $label =="
    foreach ($addr in $Addrs.Split(',')) {
        $addr = Norm $addr
        $ev = @($s[$addr] | Where-Object { $_[0] -ge $From })
        if (-not $ev.Count) { "$addr : none"; continue }
        $vals = $ev | ForEach-Object { $_[1] }
        $min = [int]($vals | Measure-Object -Minimum).Minimum
        $max = [int]($vals | Measure-Object -Maximum).Maximum
        $last = $ev[-1]
        $firstMax = @($ev | Where-Object { $_[1] -eq $max })[0][0]
        $samples = @(); $next = $From
        foreach ($e in $ev) { if ($e[0] -ge $next) { $samples += ('{0}:{1:X4}' -f $e[0], $e[1]); $next += 100 } }
        "$addr min=$($min.ToString('X4')) max=$($max.ToString('X4')) firstMax@$firstMax last=$($last[0]):$($last[1].ToString('X4')) changes=$($ev.Count)"
        '  ' + ($samples -join ' ')
    }
}
if ($WebDom) { Report (Series 'web') "WEB $WebDom" }
if ($Native) { Report (Series 'native') "NATIVE $Native" }
