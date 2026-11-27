# s67: region-matched US oracle runs for phase-matched gameplay validation.
# -Kind dump: ram-dump.html (full 64KB RAMDUMP at frame N, ?rom=us&script=).
# -Kind shot: ram-shot.html (WT write-change timeline + VID luminance + MODES).
# Web runs are deterministic under virtual time; fixed-frame scripts are exact
# on this side. Native side uses WAIT_RAM16 phase-locked scripts instead.
param(
    [int]$Frames = 2800,
    [string]$Script = '3@2100:40',
    [string]$Tag = 's67w1p',
    [ValidateSet('dump', 'shot')][string]$Kind = 'dump',
    [switch]$Wt,
    [string]$Wtx = ''
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$page = if ($Kind -eq 'dump') { 'ram-dump.html' } else { 'ram-shot.html' }
$url = "file:///S:/home/dev/boogerman-pc/web/test/${page}?rom=us&frames=${Frames}&script=${Script}"
if ($Wt) { $url += '&wt=1' }
if ($Wtx) { $url += '&wtx=' + $Wtx }
$tmp = "$env:TEMP\chrome-s67-$Tag"
$out = "S:\home\dev\boogerman-pc\native\captures-us\$Tag-dom.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=40000 --timeout=90000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\s67-$Tag-err.txt"
$dom = [IO.File]::ReadAllText($out)
if ($Kind -eq 'dump') {
    $m = [regex]::Match($dom, 'RAMDUMP ([A-Za-z0-9+/=]{1000,})')
    if (-not $m.Success) { "NO RAMDUMP: " + ([regex]::Match($dom, '<div id="out">([^<]*)').Groups[1].Value); exit 1 }
    $b = [Convert]::FromBase64String($m.Groups[1].Value)
    "dump ok len=$($b.Length) " + ([regex]::Match($dom, 'COUNTER [0-9a-f]+').Value)
} else {
    if ($dom.IndexOf('SHOTDONE') -lt 0) { "NO SHOTDONE: " + ([regex]::Match($dom, '<div id="out">([^<]*)').Groups[1].Value); exit 1 }
    "shot ok wtEntries=" + ([regex]::Match($dom, 'WT ([^V]*) VID').Groups[1].Value.Split(',').Count)
}
