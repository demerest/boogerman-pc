# web-oracle object-table / splash-gate probe at a given gx frame count.
# Usage: powershell -ExecutionPolicy Bypass -File web-obj-probe.ps1 -Frames 150
param([int]$Frames = 150)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
$url = "file:///S:/home/dev/boogerman-pc/web/test/ram-dump.html?frames=$Frames"
$tmp = "$env:TEMP\chrome-objprobe-$Frames"
$out = "$env:TEMP\objprobe-dom-$Frames.html"
$argline = "--headless=new --disable-gpu --no-first-run --user-data-dir=`"$tmp`" --virtual-time-budget=20000 --timeout=40000 --dump-dom `"$url`""
$p = Start-Process -FilePath $chrome -ArgumentList $argline -Wait -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError "$env:TEMP\objprobe-err-$Frames.txt"
$dom = [System.IO.File]::ReadAllText($out)
$m = [regex]::Match($dom, 'RAMDUMP ([A-Za-z0-9+/=]{1000,})')
if (-not $m.Success) { "NO RAMDUMP (title/err): " + ([regex]::Match($dom,'<div id="out">([^<]*)').Groups[1].Value); exit 1 }
$b = [Convert]::FromBase64String($m.Groups[1].Value)
function w($o) { return ([int]$b[$o+1] * 256 + [int]$b[$o]) }
function l($o) { return ([long](w $o)) * 65536 + (w ($o+2)) }
"frames=$Frames len=$($b.Length)"
"mode0516={0:X4} vint0288={1:X4}" -f (w 0x516), (w 0x288)
"0A58={0:X4} 0A5A={1:X4} 0A5C={2:X4} 0A90={3:X4} 0A92={4:X4} 0A94={5:X4} 0A96={6:X4}" -f (w 0xA58),(w 0xA5A),(w 0xA5C),(w 0xA90),(w 0xA92),(w 0xA94),(w 0xA96)
"0252={0:X4} 0254={1:X4} 0258={2:X4} 0242={3:X4} 0244={4:X4} 0284={5:X4} 0212={6:X4}" -f (w 0x252),(w 0x254),(w 0x258),(w 0x242),(w 0x244),(w 0x284),(w 0x212)
"0686={0:X4} 0688={1:X4} 0698={2:X4} 069A={3:X4}" -f (w 0x686),(w 0x688),(w 0x698),(w 0x69A)
"ram200: {0:X4} {1:X4} {2:X4} {3:X4} {4:X4} {5:X4}" -f (w 0x200),(w 0x202),(w 0x204),(w 0x206),(w 0x208),(w 0x20A)
"stack1EC: {0:X6} {1:X6} {2:X6} {3:X6} {4:X6} {5:X6} {6:X6} {7:X6}" -f (l 0x1EC),(l 0x1F0),(l 0x1F4),(l 0x1F8),(l 0x1FC),(l 0x200),(l 0x204),(l 0x208)
"sound: 025A={0:X4} 0518={1:X2} 0519={2:X2} 054C={3:X4} 0524={4:X4} 0548={5:X4} 0264={6:X2}" -f (w 0x25A),($b[0x518]),($b[0x519]),(w 0x54C),(w 0x524),(w 0x548),($b[0x264])
"gate: 5D4={0:X2} A65={1:X2} 2BA={2:X4} 284={3:X4}" -f ($b[0x5D4]),($b[0xA65]),(w 0x2BA),(w 0x284)
$a = 0x1A0E
for ($i = 0; $i -lt 10; $i++) {
  $w0 = w $a
  $stride = $w0 -band 0x7FFF
  if ($stride -eq 0 -or $w0 -eq 0xFFFF -or $stride -gt 0x700) { "end/free slot"; break }
  $w2 = w ($a+2); $h = l ($a+4); $w68 = w ($a+68); $w10 = w ($a+10); $w16 = w ($a+16)
  try {
    "obj@{0:X6}: w0={1:X4} w2={2:X4} handler={3:X6} +10={4:X4} +16={5:X4} +68={6:X4} +40={7:X4} +42={8:X4} +48={9:X6} +4C={10:X4}" -f (0xFF0000+$a), $w0, $w2, $h, $w10, $w16, $w68, (w ($a+40)), (w ($a+42)), (l ($a+48)), (w ($a+76))
  } catch {
    "obj@{0:X6}: w0={1:X4} w2={2:X4} (raw) +10={3} +16={4} +68={5} +40={6} +42={7} +48={8} +4C={9}" -f (0xFF0000+$a), $w0, $w2, $w10, $w16, $w68, (w ($a+40)), (w ($a+42)), (l ($a+48)), (w ($a+76))
  }
  $a += $stride
  if ($a -ge 0x2212) { "end of table"; break }
}