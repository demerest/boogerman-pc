param([int]$DelayMs = 1000)
$ErrorActionPreference = 'Stop'
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
    "probe ok: state=$($resp.Length) bytes ram=$($resp2.Length) bytes dump=$resp3"
    $c.Close()
} catch {
    "probe failed: $_"
}
if (-not $p.HasExited) { $p.WaitForExit(8000) | Out-Null }
if (-not $p.HasExited) { $p.Kill() }
"exit=$($p.ExitCode)"
