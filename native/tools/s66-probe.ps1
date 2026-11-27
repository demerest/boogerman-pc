# s66: reproduce the wide-tap freeze and catch the stuck gate. Same launcher
# combo as s65-probe plus the wide OBJ-TL HI=2400 tap (the s65 freeze coupling).
# On FROZEN (trail lacks V-int 004DF0): full trail, live registers, driver-flag
# RAM dumps, bus regs, Z80 mailbox, and the last OBJ-TL writes before the freeze.
param([int]$MaxSec = 180, [string]$Tag = 's66probe', [string]$InputScript = 's65-trans.input')
$ErrorActionPreference = 'Stop'
$env:GENESIS_BOOT_ASSIST='1'; $env:GENESIS_LOCKSTEP='1'; $env:GENESIS_Z80_FULL_SYNC='1'
$env:GENESIS_Z80_NO_BUS_HALT='1'; $env:GENESIS_WATCHDOG_INSN='400000000'; $env:GENESIS_WATCHDOG_BUS='100000000'
$env:GENESIS_TITLE_ASSIST='1'; $env:GENESIS_SPLASH_ASSIST='1'
$env:GENESIS_OBJ_TL='1'; $env:GENESIS_OBJ_TL_HI='2400'
$root='S:\home\dev\boogerman-pc'
$exe="$root\native\build\Release\BoogermanRecomp_us.exe"; $rom="$root\Boogerman (U) [!].gen"
$out="$root\native\captures-us\$Tag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$p=Start-Process -FilePath $exe -ArgumentList ('"'+$rom+'" --exit-at-frame 4600 --input-script "'+$root+'\native\tools\'+$InputScript+'"') -PassThru -NoNewWindow -RedirectStandardError "$out\err.log" -RedirectStandardOutput "$out\out.log"
function Cmd($w,$r,$json){ $w.WriteLine($json); return $r.ReadLine() }
$lastAlive=''
$sw=[Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt $MaxSec -and -not $p.HasExited) {
    Start-Sleep -Milliseconds 4000
    try {
        $c=New-Object System.Net.Sockets.TcpClient('127.0.0.1',4400); $s=$c.GetStream()
        $s.ReadTimeout=3000; $s.WriteTimeout=3000
        $w=New-Object System.IO.StreamWriter($s); $r=New-Object System.IO.StreamReader($s); $w.AutoFlush=$true
        $line=Cmd $w $r '{"id":1,"cmd":"crash_trail"}'
        $t=[int]$sw.Elapsed.TotalSeconds
        # s66 correction: a trail lacking the V-int block is NOT a freeze — during
        # the boot sound-upload the last 64 blocks are all 98xxx while frames still
        # advance. Liveness = vblank_info frame_count delta over 1.5s.
        $f1=[regex]::Match((Cmd $w $r '{"id":1,"cmd":"vblank_info"}'),'"frame_count":(\d+)').Groups[1].Value
        Start-Sleep -Milliseconds 1500
        $f2=[regex]::Match((Cmd $w $r '{"id":1,"cmd":"vblank_info"}'),'"frame_count":(\d+)').Groups[1].Value
        if ($line -match '004DF0' -or $f2 -ne $f1) {
            $lastAlive=$line
            "t=$t ALIVE (frame $f1->$f2)"
        } else {
            "t=$t FROZEN full trail:"
            $line
            "last alive trail:"
            $lastAlive
            "REGS: $(Cmd $w $r '{"id":1,"cmd":"get_registers"}')"
            "STATE: $(Cmd $w $r '{"id":1,"cmd":"rdb_get_state"}')"
            "SCHED: $(Cmd $w $r '{"id":1,"cmd":"sched_state"}')"
            "VBLANK: $(Cmd $w $r '{"id":1,"cmd":"vblank_info"}')"
            "FRAMEINFO: $(Cmd $w $r '{"id":1,"cmd":"frame_info"}')"
            "Z80: $(Cmd $w $r '{"id":1,"cmd":"z80_state"}')"
            Start-Sleep -Milliseconds 1500
            "SCHED+1.5s: $(Cmd $w $r '{"id":1,"cmd":"sched_state"}')"
            "VBLANK+1.5s: $(Cmd $w $r '{"id":1,"cmd":"vblank_info"}')"
            "FRAMEINFO+1.5s: $(Cmd $w $r '{"id":1,"cmd":"frame_info"}')"
            foreach ($q in @(
                @('0xFF0510',96), @('0xFF05B0',32), @('0xFF0280',64),
                @('0xFF0A60',16), @('0xFF1A10',96), @('0xA11100',4),
                @('0xA00FE0',32), @('0xA00000',64)
            )) {
                "RAM $($q[0]): $(Cmd $w $r ('{"id":1,"cmd":"read_memory","addr":"'+$q[0]+'","size":'+$q[1]+'}'))"
            }
            $c.Close()
            break
        }
        $c.Close()
    } catch { "t=$([int]$sw.Elapsed.TotalSeconds) probe err: $_" }
}
if (-not $p.HasExited) { $p.Kill() }
"--- last 40 err.log lines (OBJ-TL tail at freeze):"
Get-Content "$out\err.log" -Tail 40
"done"