# embed-assets.ps1 - embeds the WASM core and the cartridge dump as base64 JS
# so the port runs from file:// with zero network access and zero dependencies.
# Regenerate with: powershell -NoProfile -ExecutionPolicy Bypass -File tools\embed-assets.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$enc = New-Object System.Text.UTF8Encoding($false)

$wasmPath = Join-Path $root 'vendor\gpgx\genesis_plus_gx_libretro.wasm'
$w = [IO.File]::ReadAllBytes($wasmPath)
$b64 = [Convert]::ToBase64String($w)
[IO.File]::WriteAllText((Join-Path $root 'vendor\gpgx\gpgx.wasm.js'), "window.BP_WASM_B64='" + $b64 + "';", $enc)
Write-Output ('Embedded wasm: ' + $w.Length + ' bytes -> ' + $b64.Length + ' base64 chars')

$romPath = Join-Path $root 'Boogerman (E) [!].gen'
if (-not (Test-Path -LiteralPath $romPath)) {
    $romPath = Join-Path (Split-Path -Parent $root) 'Boogerman (E) [!].gen'
}
$r = [IO.File]::ReadAllBytes($romPath)
$b64r = [Convert]::ToBase64String($r)
$romDir = Join-Path $root 'rom'
New-Item -ItemType Directory -Force $romDir | Out-Null
[IO.File]::WriteAllText((Join-Path $romDir 'boogerman.gen.js'), "window.BP_ROM_B64='" + $b64r + "';window.BP_ROM_NAME='Boogerman (E) [!].gen';", $enc)
Write-Output ('Embedded ROM: ' + $r.Length + ' bytes -> ' + $b64r.Length + ' base64 chars')

# Header facts for the docs / sanity check.
function Ascii($off, $len) {
    $s = [Text.Encoding]::ASCII.GetString($r, $off, $len)
    -join ($s.ToCharArray() | ForEach-Object { if ([int]$_ -ge 32 -and [int]$_ -le 126) { $_ } else { '.' } })
}
$romEnd = ($r[0x1A4] * 16777216) + ($r[0x1A5] * 65536) + ($r[0x1A6] * 256) + $r[0x1A7]
Write-Output ('Title(overseas): [' + (Ascii 0x150 48).Trim() + ']')
Write-Output ('Serial:          [' + (Ascii 0x180 14).Trim() + ']')
Write-Output ('Region:          [' + (Ascii 0x1F0 16).Trim() + ']')
Write-Output ('Header ROM end:  0x' + ('{0:X6}' -f $romEnd))
Write-Output ('SRAM signature:  [' + (Ascii 0x1B0 12) + ']')
