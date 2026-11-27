# s65: catch the non-deterministic guest freeze live. Launch the assisted US
# runner, poll crash_trail every 4s; a trail whose recent blocks lack the
# V-int handler (004DF0) means the guest stopped servicing frames => frozen.
# Prints the frozen ring and the last alive ring for comparison.
param([int]$MaxSec = 60, [switch]$TitleAssist, [switch]$SplashAssist)
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
if ($TitleAssist) { $env:GENESIS_TITLE_ASSIST='1' } else { Remove-Item Env:GENESIS_TITLE_ASSIST -ErrorAction SilentlyContinue }
if ($SplashAssist) { $env:GENESIS_SPLASH_ASSIST='1' } else { Remove-Item Env:GENESIS_SPLASH_ASSIST -ErrorAction SilentlyContinue }
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\s65probe"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$p=Start-Process -FilePath $exe -ArgumentList ('"'+$rom+'" --exit-at-frame 4600 --input-script "'+$root+'\native\tools\s64-play.input"') -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
$lastAlive=''
$sw=[Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $MaxSec -and -not $p.HasExited) {
    Start-Sleep -Milliseconds 4000
    try {
        $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
        $s.ReadTimeout=3000; $s.WriteTimeout=3000
        $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
        $w.WriteLine('{"id":1,"cmd":"crash_trail"}'); $line=$r.ReadLine()
        $c.Close()
        $t=[int]$sw.Elapsed.TotalSeconds
        if ($line -match '004DF0') {
            $lastAlive=$line
            "t=$t ALIVE"
        } else {
            "t=$t FROZEN trail:"
            $line
            "last alive trail:"
            $lastAlive
            $tally=@{}
            try {
                $c2=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s2=$c2.GetStream()
                $s2.ReadTimeout=2000; $s2.WriteTimeout=2000
                $w2=New-Object System.IO.StreamWriter($s2); $r2=New-Object System.IO.StreamReader($s2); $w2.AutoFlush=$true
                for ($i=0;$i -lt 16;$i++) {
                    $w2.WriteLine('{"id":1,"cmd":"rdb_get_state"}'); $st=$r2.ReadLine()
                    if ($i -eq 0) { "raw state: $st" }
                    $m=[regex]::Match($st,'"func":"0x([0-9A-Fa-f]+)"')
                    if ($m.Success) { $f=$m.Groups[1].Value; if ($tally.ContainsKey($f)){$tally[$f]++}else{$tally[$f]=1} }
                    Start-Sleep -Milliseconds 25
                }
                $c2.Close()
            } catch { "state probe err: $_" }
            "func tally at freeze:"
            $tally.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object { "$($_.Value)  $($_.Name)" }
            break
        }
    } catch { "t=$([int]$sw.Elapsed.TotalSeconds) probe err: $_" }
}
if (-not $p.HasExited) { $p.Kill() }
"done"
