# s72: web-US oracle long-run with configurable virtual-time budget (s67's fixed
# 40000ms starves runs beyond ~2400 frames). -Kind shot => ram-shot WT timeline.
param(
    [int]$Frames = 12000,
    [string]$Script = '3@2450:40,5@2900:4',
    [string]$Tag = 's72wA',
    [string]$Wtx = '244,222,698,6d0',
    [int]$Budget = 250000
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = "file:///S:/home/dev/boogerman-pc/web/test/ram-shot.html?rom=us&frames=${Frames}&script=${Script}&wt=1&wtx=${Wtx}"
$tmp = "$env:TEMP\chrome-s72-$Tag"
$out = "S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=$Budget --timeout=120000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\s72-$Tag-err.txt"
$dom = [IO.File]::ReadAllText($out)
if ($dom.IndexOf('SHOTDONE') -lt 0) { "NO SHOTDONE: " + ([regex]::Match($dom, '<div id="out">([^<]*)').Groups[1].Value); exit 1 }
"shot ok wtEntries=" + ([regex]::Match($dom, 'WT ([^V]*) VID').Groups[1].Value.Split(',').Count)
