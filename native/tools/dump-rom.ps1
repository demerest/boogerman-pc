# dumps ROM words (big-endian) for a hex offset range; manual-decode aid for
# unemitted regions (jump tables, interior waits). Usage:
#   powershell -File dump-rom.ps1 -Offset 98000 -Length 100 [-Rom us|eu]
param(
  [string]$Offset = '98000',
  [int]$Length = 128,
  [string]$Rom = 'us'
)
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc'
$path = if ($Rom -eq 'eu') { "$root\Boogerman (E) [!].gen" } else { "$root\Boogerman (U) [!].gen" }
$b = [System.IO.File]::ReadAllBytes($path)
$start = [Convert]::ToInt32($Offset, 16)
for ($i = 0; $i -lt $Length; $i += 2) {
  $a = $start + $i
  if ($a + 1 -ge $b.Length) { break }
  $w = ([int]$b[$a] -shl 8) -bor [int]$b[$a + 1]
  '{0:X6}: {1:X4}' -f $a, $w
}