param([int]$DelayMs = 1000, [switch]$NoBusHalt)
$ErrorActionPreference = 'Stop'
if ($NoBusHalt) { $env:GENESIS_Z80_NO_BUS_HALT = '1' }
$env:GENESIS_WATCHDOG_INSN = '400000000'; $env:GENESIS_WATCHDOG_BUS = '100000000'
$root = 'S:\home\dev\boogerman-pc'
$exe  = "$root\native\build\Release\BoogermanRecomp_us.exe"
$rom  = "$root\Boogerman (U) [!].gen"
$out  = "$root\native\captures-us"
$argline = "`"$rom`" --exit-at-frame 120"
$p = Start-Process -FilePath $exe -ArgumentList $argline -PassThru -NoNewWindow `
     -RedirectStandardError "$out\probe-stderr.log" -RedirectStandardOutput "$out\probe-stdout.log"
Start-Sleep -Milliseconds $DelayMs
try {
    $c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4400)
    $s = $c.GetStream()
    $s.ReadTimeout = 3000; $s.WriteTimeout = 3000
    $w = New-Object System.IO.StreamWriter($s)
    $r = New-Object System.IO.StreamReader($s)
    $w.AutoFlush = $true
    $w.WriteLine('{"id":1,"cmd":"z80_state","include_ram":1}')
    $resp = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\z80-state.json", $resp)
    $w.WriteLine('{"id":2,"cmd":"read_z80_ram","addr":3072,"len":512}')
    $resp2 = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\z80-ram-0c00.json", $resp2)
    $w.WriteLine('{"id":3,"cmd":"snd_dump","prefix":"S:\\home\\dev\\boogerman-pc\\native\\captures-us\\boot-"}')
    $resp3 = $r.ReadLine()
    $w.WriteLine('{"id":4,"cmd":"rdb_get_state"}')
    $resp4 = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\68k-state.json", $resp4)
    $w.WriteLine('{"id":5,"cmd":"read_memory","addr":"0xFF0500","size":96}')
    $resp5 = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\68k-ram-ff0500.json", $resp5)
    $w.WriteLine('{"id":6,"cmd":"read_memory","addr":"0xFF0A70","size":32}')
    $resp6 = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\68k-ram-ff0a70.json", $resp6)
    $w.WriteLine('{"id":7,"cmd":"read_memory","addr":"0xFF0210","size":16}')
    $resp7 = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\68k-ram-ff0210.json", $resp7)
    "probe ok: state=$($resp.Length) ram=$($resp2.Length) 68k=$($resp4.Length) dump=$resp3"
    $c.Close()
} catch {
    "probe failed: $_"
}
if (-not $p.HasExited) { $p.WaitForExit(8000) | Out-Null }
if (-not $p.HasExited) { $p.Kill() }
"exit=$($p.ExitCode)"
