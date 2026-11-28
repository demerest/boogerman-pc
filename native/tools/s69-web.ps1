# s69: web-US oracle full-RAM dump saved as native-order bin (word byte-swap),
# so s68-diffbin.ps1 can read/compare it directly. Usage:
#   s69-web.ps1 -Frames 4000 -Script '3@2450:40' -Tag s69w1
param(
    [int]$Frames = 4000,
    [string]$Script = '3@2450:40',
    [string]$Tag = 's69w1',
    [int]$Budget = 60000,
    [string]$Wr = ''
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = "file:///S:/home/dev/boogerman-pc/web/test/ram-dump.html?rom=us&frames=${Frames}&script=${Script}"
if ($Wr) { $url += "&wr=$Wr" }
$tmp = "$env:TEMP\chrome-s69-$Tag"
$out = "S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=$Budget --timeout=300000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\s69-$Tag-err.txt"
$dom = [IO.File]::ReadAllText($out)
$m = [regex]::Match($dom, 'RAMDUMP ([A-Za-z0-9+/=]{1000,})')
if (-not $m.Success) { "NO RAMDUMP: " + ([regex]::Match($dom, '<div id="out">([^<]*)').Groups[1].Value); exit 1 }
$b = [Convert]::FromBase64String($m.Groups[1].Value)
if ($b.Length -ne 0x10000) { "bad len $($b.Length)"; exit 1 }
for ($i = 0; $i -lt $b.Length; $i += 2) { $t = $b[$i]; $b[$i] = $b[$i+1]; $b[$i+1] = $t }
$dir = "S:\home\dev\boogerman-pc\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[IO.File]::WriteAllBytes("$dir\web.bin", $b)
"web.bin ok " + ([regex]::Match($dom, 'COUNTER [0-9a-f]+').Value)