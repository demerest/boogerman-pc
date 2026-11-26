param([string]$Cov = 'S:\home\dev\boogerman-pc\native\captures-us\s52c\cov.txt',
      [string]$Gen = 'S:\home\dev\boogerman-pc\native\build\generated\boogerman_us',
      [string]$Out = 'S:\home\dev\boogerman-pc\native\captures-us\s52c\unemitted-runs.txt',
      [int]$RomLimit = 0x300000)
$ErrorActionPreference = 'Stop'
$emitted = @{}
foreach ($f in (Get-ChildItem "$Gen\*part*.c")) {
  foreach ($mi in (Select-String -Path $f.FullName -Pattern 'rdb_on_insn\(0x([0-9A-Fa-f]+)u\)' -AllMatches)) {
    foreach ($m in $mi.Matches) { $emitted[[Convert]::ToUInt32($m.Groups[1].Value,16)] = $true }
  }
}
"emitted instruction PCs: $($emitted.Count)"
# cov.txt is ascending and unique by construction (interpreter coverage bitmap).
$covList = New-Object System.Collections.Generic.List[uint32]
foreach ($ln in @(Get-Content $Cov)) {
  if ($ln -match '^[0-9A-Fa-f]+$') {
    $v = [Convert]::ToUInt32($ln,16)
    if ($v -lt $RomLimit) { $covList.Add($v) }
  }
}
"covered ROM PCs: $($covList.Count)"
$un = New-Object System.Collections.Generic.List[uint32]
foreach ($v in $covList) {
  if (-not $emitted.ContainsKey($v)) { $un.Add($v) }
}
"unemitted executed PCs: $($un.Count)"
$runs = New-Object System.Collections.Generic.List[object]
$start = [uint32]0; $prev = [uint32]0; $have = $false
foreach ($a in $un) {
  if ($have -and $a -eq ($prev + 2)) { $prev = $a; continue }
  if ($have) { $runs.Add([pscustomobject]@{ Start=$start; End=$prev; N=[int](($prev-$start)/2+1) }) }
  $start = $a; $prev = $a; $have = $true
}
if ($have) { $runs.Add([pscustomobject]@{ Start=$start; End=$prev; N=[int](($prev-$start)/2+1) }) }
"runs: $($runs.Count)"
$sb = New-Object System.Text.StringBuilder
foreach ($r in $runs) { [void]$sb.AppendLine(('{0:X6} {1:X6} {2}' -f $r.Start, $r.End, $r.N)) }
[System.IO.File]::WriteAllText($Out, $sb.ToString())
"written $Out"
foreach ($r in ($runs | Sort-Object N -Descending | Select-Object -First 40)) {
  '{0:X6}..{1:X6} n={2}' -f $r.Start, $r.End, $r.N
}
