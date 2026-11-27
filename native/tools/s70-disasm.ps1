# s70: minimal 68k disassembler over the US ROM via headless Chrome.
# -Scan: find MOVE.W #imm,(addr) writers of the mode/timer words.
# else disassemble [Start,End) hex. Usage: s70-disasm.ps1 -Start 154C0 -End 15780 -Tag s70d1
param(
    [string]$Start = '154C0',
    [string]$End = '15780',
    [switch]$Scan,
    [string]$Tag = 's70d1'
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = "file:///S:/home/dev/boogerman-pc/native/tools/s70-disasm.html?start=$Start&end=$End"
if ($Scan) { $url += '&scan=1' }
$tmp = "$env:TEMP\chrome-s70-$Tag"
$out = "S:\home\dev\boogerman-pc\native\captures-us\$Tag-disasm.txt"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=20000 --timeout=60000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\s70-$Tag-dom.html" -RedirectStandardError "$env:TEMP\s70-$Tag-err.txt"
$dom = [IO.File]::ReadAllText("$env:TEMP\s70-$Tag-dom.html")
$m = [regex]::Match($dom, '(?s)<pre id="out">(.*?)</pre>')
if (-not $m.Success -or $m.Groups[1].Value -eq 'waiting') { "NO DISASM"; exit 1 }
$txt = $m.Groups[1].Value -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>'
[IO.File]::WriteAllText($out, $txt)
"disasm ok lines=" + ($txt.Split("`n").Count) + " -> $out"