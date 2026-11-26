param([string]$LogA, [string]$LogB, [int]$SkipBelow = 0xFF0200)
$ErrorActionPreference = 'Stop'
function build($p, $skip) {
  $d = @{}
  $order = New-Object System.Collections.Generic.List[string]
  $lines = @{}
  foreach ($x in [System.IO.File]::ReadLines($p)) {
    if ($x.StartsWith('[OBJ-TL]')) {
      if ($x -match 'a=([0-9A-F]{6}) v=([0-9A-F]{6}) s=(\d)') {
        $a = [Convert]::ToUInt32($Matches[1], 16)
        if ($a -lt $skip) { continue }
        $k = $Matches[1]
        if (-not $d.ContainsKey($k)) { $d[$k] = New-Object System.Collections.Generic.List[string]; $order.Add($k); $lines[$k] = New-Object System.Collections.Generic.List[string] }
        $d[$k].Add($Matches[2]); $lines[$k].Add($x)
      }
    }
  }
  return ,@($d, $order, $lines)
}
$ra = build $LogA $SkipBelow; $rb = build $LogB $SkipBelow
$da = $ra[0]; $oa = $ra[1]; $la = $ra[2]
$db = $rb[0]; $ob = $rb[1]; $lb = $rb[2]
'addresses A='+$oa.Count+' B='+$ob.Count
foreach ($k in $oa) {
  if (-not $db.ContainsKey($k)) { 'addr '+$k+' only in A'; continue }
  $va = $da[$k]; $vb = $db[$k]
  $m = [Math]::Min($va.Count, $vb.Count)
  for ($j = 0; $j -lt $m; $j++) {
    if ($va[$j] -ne $vb[$j]) {
      'DIVERGE addr='+$k+' at write #'+$j
      $s = [Math]::Max(0, $j - 4)
      for ($q = $s; $q -lt [Math]::Min($m, $j + 6); $q++) {
        ('  A:{0}' -f $la[$k][$q]); ('  B:{0}' -f $lb[$k][$q])
      }
      exit 0
    }
  }
  if ($va.Count -ne $vb.Count) {
    'LENGTH DIVERGE addr='+$k+' A='+$va.Count+' B='+$vb.Count
    $s = [Math]::Max(0, $m - 4)
    for ($q = $s; $q -lt $m; $q++) { ('  A:{0}' -f $la[$k][$q]); ('  B:{0}' -f $lb[$k][$q]) }
    if ($va.Count -gt $m) { ('  A-extra:{0}' -f $la[$k][$m]) }
    if ($vb.Count -gt $m) { ('  B-extra:{0}' -f $lb[$k][$m]) }
    exit 0
  }
}
'no per-address divergence'
