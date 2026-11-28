# s99: web-EU oracle full-RAM dump (native-order bin) + title-flag words.
param(
    [int]$Frames = 12000,
    [string]$Script = '',
    [string]$Tag = 's99w',
    [int]$Budget = 120000
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = "file:///S:/home/dev/boogerman-pc/web/test/ram-dump.html?frames=${Frames}&script=${Script}"
$tmp = "$env:TEMP\chrome-s99-$Tag"
$out = "S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=$Budget --timeout=300000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\s99-$Tag-err.txt"
$dom = [IO.File]::ReadAllText($out)
$m = [regex]::Match($dom, 'RAMDUMP ([A-Za-z0-9+/=]{1000,})')
if (-not $m.Success) { "NO RAMDUMP: " + ([regex]::Match($dom, '<div id="out">([^<]*)').Groups[1].Value); exit 1 }
$b = [Convert]::FromBase64String($m.Groups[1].Value)
if ($b.Length -ne 0x10000) { "bad len $($b.Length)"; exit 1 }
for ($i = 0; $i -lt $b.Length; $i += 2) { $t = $b[$i]; $b[$i] = $b[$i+1]; $b[$i+1] = $t }
$dir = "S:\home\dev\boogerman-pc\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[IO.File]::WriteAllBytes("$dir\web.bin", $b)
function w($o) { '{0:X4}' -f ([int]$b[$o] * 256 + [int]$b[$o + 1]) }
"web.bin ok " + ([regex]::Match($dom, 'COUNTER [0-9a-f]+').Value)
"0244=" + (w 0x244) + " 0284=" + (w 0x284) + " 02BA=" + (w 0x2BA) + " 0A65=" + (w 0xA65) + " 05D4=" + (w 0x5D4)
$s = ''; for ($o = 0xA50; $o -le 0xA66; $o += 2) { $s += (w $o) + ' ' }; "HDR " + $s
