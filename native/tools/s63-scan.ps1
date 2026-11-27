param([string]$Targets = '142C,1496', [string]$Rom = 'us')
$path = if ($Rom -eq 'us') { 'S:\home\dev\boogerman-pc\Boogerman (U) [!].gen' } else { 'S:\home\dev\boogerman-pc\Boogerman (E) [!].gen' }
$b = [System.IO.File]::ReadAllBytes($path)
$tg = @($Targets.Split(',') | ForEach-Object { [Convert]::ToInt32($_, 16) })
for ($i = 0; $i -lt $b.Length - 6; $i += 2) {
  $w = ($b[$i] * 256) + $b[$i + 1]
  if ($w -eq 0x4EB9 -or $w -eq 0x4EF9) {
    $a = ($b[$i + 2] * 16777216) + ($b[$i + 3] * 65536) + ($b[$i + 4] * 256) + $b[$i + 5]
    if ($tg -contains $a) { Write-Output ('{0:X6} {1} {2:X6}' -f $i, $(if ($w -eq 0x4EB9) { 'jsr' } else { 'jmp' }), $a) }
  } elseif ($w -eq 0x6100 -or $w -eq 0x6000) {
    $d = ($b[$i + 2] * 256) + $b[$i + 3]
    if ($d -ge 32768) { $d -= 65536 }
    $t = $i + 2 + $d
    if ($tg -contains $t) { Write-Output ('{0:X6} {1} {2:X6}' -f $i, $(if ($w -eq 0x6100) { 'bsr' } else { 'bra' }), $t) }
  } elseif (($w -band 0xFF00) -eq 0x6100 -and ($w -band 0xFF) -ne 0) {
    $d = $w -band 0xFF
    if ($d -ge 128) { $d -= 256 }
    $t = $i + 2 + $d
    if ($tg -contains $t) { Write-Output ('{0:X6} bsr.s {1:X6}' -f $i, $t) }
  } elseif ((($w -band 0xF1FF) -eq 0x41F9) -or (($w -band 0xF1FF) -eq 0x207C)) {
    $a = ($b[$i + 2] * 16777216) + ($b[$i + 3] * 65536) + ($b[$i + 4] * 256) + $b[$i + 5]
    if ($tg -contains $a) { Write-Output ('{0:X6} {1} {2:X6}' -f $i, $(if (($w -band 0xF1FF) -eq 0x41F9) { 'lea' } else { 'movea' }), $a) }
  }
}
