# s101: web-EU oracle per-frame word trace (cosim vs native OBJ-TL).
param(
    [int]$Frames = 2800,
    [int]$From = 1800,
    [int]$To = 2800,
    [string]$Tag = 's101w',
    [int]$Budget = 120000,
    [string]$Trace = '284,286,2b4,2b6,2b8,500,502,50c,1a2e,1a30,1a32,1a34,244,248,22e',
    [string]$Rom = 'EU'
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$romq = if ($Rom -eq 'US') { '&rom=us' } else { '' }
$url = "file:///S:/home/dev/boogerman-pc/web/test/ram-trace.html?frames=${Frames}&from=${From}&to=${To}&trace=${Trace}${romq}"
$tmp = "$env:TEMP\chrome-s101-$Tag"
$out = "S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=$Budget --timeout=300000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\s101-$Tag-err.txt"
$dom = [IO.File]::ReadAllText($out)
$m = [regex]::Match($dom, 'TRACEDUMP ([A-Za-z0-9+/=]{100,})')
if (-not $m.Success) { "NO TRACEDUMP: " + ([regex]::Match($dom, '<div id="out">([^<]*)').Groups[1].Value); exit 1 }
$txt = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Groups[1].Value))
$dir = "S:\home\dev\boogerman-pc\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[IO.File]::WriteAllText("$dir\trace-web.txt", $txt)
$ls = $txt -split "`n"
"trace-web.txt lines=$($ls.Count)"
"first: " + $ls[0]
"last:  " + $ls[$ls.Count - 1]