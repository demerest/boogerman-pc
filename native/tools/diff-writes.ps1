param([string]$LogA, [string]$LogB, [int]$Before = 8, [int]$After = 14)
$ErrorActionPreference = 'Stop'
function seq($p) {
  $k = New-Object System.Collections.Generic.List[string]
  $f = New-Object System.Collections.Generic.List[string]
  foreach ($x in [System.IO.File]::ReadLines($p)) {
    if ($x.StartsWith('[OBJ-TL]')) {
      if ($x -match 'a=([0-9A-F]{6}) v=([0-9A-F]{6}) s=(\d)') {
        $k.Add($Matches[1]+' '+$Matches[2]+' '+$Matches[3]); $f.Add($x)
      }
    }
  }
  return ,@($k,$f)
}
$ra = seq $LogA; $rb = seq $LogB
$ka = $ra[0]; $fa = $ra[1]; $kb = $rb[0]; $fb = $rb[1]
'A='+$ka.Count+' B='+$kb.Count
$m = [Math]::Min($ka.Count, $kb.Count); $d = -1
for ($j = 0; $j -lt $m; $j++) { if ($ka[$j] -ne $kb[$j]) { $d = $j; break } }
'first divergence at '+$d
if ($d -lt 0) { 'identical prefix'; exit 0 }
$s = [Math]::Max(0, $d - $Before)
for ($j = $s; $j -lt [Math]::Min($m, $d + $After); $j++) {
  ('{0,6} A:{1}' -f $j, $fa[$j])
  ('       B:{0}' -f $fb[$j])
}
