# patch-glue.ps1 - converts the Node-targeted romdev Emscripten glue into a
# browser classic script. Mechanical, asserted replacements only.
# Regenerate with: powershell -NoProfile -ExecutionPolicy Bypass -File tools\patch-glue.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src = Join-Path $root 'vendor\gpgx\genesis_plus_gx_libretro.js'
$dst = Join-Path $root 'vendor\gpgx\gpgx.web.js'
$t = [IO.File]::ReadAllText($src)

function ReplaceOnce([string]$text, [string]$old, [string]$new) {
    $i = $text.IndexOf($old)
    if ($i -lt 0) { throw "NOT FOUND: $old" }
    $j = $text.IndexOf($old, $i + $old.Length)
    if ($j -ge 0) { throw "MULTIPLE MATCHES: $old" }
    return $text.Substring(0, $i) + $new + $text.Substring($i + $old.Length)
}

# 1) Disable the hardcoded Node environment flag (all require()/process use is guarded by it).
$t = ReplaceOnce $t 'var ENVIRONMENT_IS_NODE=true;' 'var ENVIRONMENT_IS_NODE=false;'
# 2) Remove the Node createRequire bootstrap (contains import.meta / dynamic import).
$t = ReplaceOnce $t 'if(ENVIRONMENT_IS_NODE){const{createRequire}=await import("module");var require=createRequire(import.meta.url)}' ''
# 3) import.meta.url is invalid syntax in classic scripts; use the script tag URL instead.
$t = ReplaceOnce $t 'var _scriptName=import.meta.url;' 'var _scriptName=(typeof document!=="undefined"&&document.currentScript&&document.currentScript.src)||"";'
# 4) Same for the wasm locateFile fallback (unused: we always supply Module.wasmBinary).
$t = ReplaceOnce $t 'return new URL("genesis_plus_gx_libretro.wasm",import.meta.url).href' 'return "genesis_plus_gx_libretro.wasm"'
# 5) ES6 export -> global assignment (classic script, file:// friendly).
$t = ReplaceOnce $t 'export default create_genesis_plus_gx;' 'window.create_genesis_plus_gx=create_genesis_plus_gx;'

if ($t.Contains('import.meta')) { throw 'import.meta still present after patch' }
if ($t.Contains('import('))     { throw 'dynamic import still present after patch' }

$enc = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($dst, $t, $enc)
Write-Output ('Patched glue written: ' + $dst + ' (' + (Get-Item $dst).Length + ' bytes)')
