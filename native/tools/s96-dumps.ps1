# s96: native dump scripts — sewers RAM+VRAM @~7300 (s96w) and level-1
# RAM+VRAM @~3000 (s96v), replaying the user's recorded inputs verbatim.
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native'
$log = Get-Content "$root\build\play-input.log"
$w = @(); $v = @()
foreach ($l in $log) {
    if ($l -match '^(\d+)\s+') {
        $f = [int]$Matches[1]
        if ($f -le 7300) { $w += $l }
        if ($f -le 3000) { $v += $l }
    }
}
$w += 'DUMP_RAM S:/home/dev/boogerman-pc/native/captures-us/s96w/native.bin'
$w += 'DUMP_VRAM S:/home/dev/boogerman-pc/native/captures-us/s96w/sewers.vram'
$w += 'EXIT'
$v += 'DUMP_VRAM S:/home/dev/boogerman-pc/native/captures-us/s96v/level1.vram'
$v += 'DUMP_RAM S:/home/dev/boogerman-pc/native/captures-us/s96v/level1.bin'
$v += 'EXIT'
Set-Content -Path "$root\tools\s96w.input" -Value $w -Encoding ASCII
Set-Content -Path "$root\tools\s96v.input" -Value $v -Encoding ASCII
"w=$($w.Count) v=$($v.Count)"
