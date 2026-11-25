param([int]$Frames = 2)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = "file:///S:/home/dev/boogerman-pc/web/test/ram-dump.html?frames=$Frames"
$tmp = "$env:TEMP\chrome-ramprobe-$Frames"
$out = "$env:TEMP\ramprobe-dom-$Frames.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=20000 --timeout=40000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\ramprobe-err-$Frames.txt"
$dom = [System.IO.File]::ReadAllText($out)
$m = [regex]::Match($dom, 'RAMDUMP ([A-Za-z0-9+/=]{1000,})')
if (-not $m.Success) { "NO RAMDUMP (title/err): " + ([regex]::Match($dom,'<div id="out">([^<]*)').Groups[1].Value); exit 1 }
$b = [Convert]::FromBase64String($m.Groups[1].Value)
function w($o) { return ('{0:X4}' -f ([int]$b[$o] * 256 + [int]$b[$o+1])) }
"frames=$Frames len=$($b.Length)"
"0288(vint_count)=$(w 0x288) 0516(vint_routine)=$(w 0x516) 051A(ptr)=$(w 0x51A)$(w 0x51C)"
"0216=$(w 0x216) 0218=$(w 0x218) 0A78=$(w 0xA78) 0A7A=$(w 0xA7A)"
"06D2=$(w 0x6D2) 069A=$(w 0x69A) 054C=$(w 0x54C) 0520=$(w 0x520)"
