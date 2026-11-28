# s92: connect-only cmd-server probe for an ALREADY-RUNNING native runner
# (debug.ini port 4400). Samples the Z80/SMPS handshake state mid-stall:
# z80_state (PC/iff/irq/bus), Z80 RAM 0F00-0FFF (FAC cmd byte / FAD init /
# FC2), 68K service cells, crash_trail. Usage: s92-probe.ps1 -Tag s92a
param([string]$Tag = 's92a')
$ErrorActionPreference = 'Stop'
$out = 'S:\home\dev\boogerman-pc\native\captures-us'
$c = New-Object System.Net.Sockets.TcpClient('127.0.0.1', 4400)
$s = $c.GetStream()
$s.ReadTimeout = 5000; $s.WriteTimeout = 5000
$w = New-Object System.IO.StreamWriter($s)
$r = New-Object System.IO.StreamReader($s)
$w.AutoFlush = $true
function SendCmd([string]$json, [string]$name) {
    $w.WriteLine($json)
    $resp = $r.ReadLine()
    [System.IO.File]::WriteAllText("$out\$Tag-$name.json", $resp)
    "$name len=$($resp.Length)"
}
SendCmd '{"id":1,"cmd":"z80_state","include_ram":0}' 'z80state'
SendCmd '{"id":2,"cmd":"read_z80_ram","addr":3840,"len":256}' 'z80ram-0f00'
SendCmd '{"id":3,"cmd":"read_memory","addr":"0xFF051A","size":4}' '68k-051a'
SendCmd '{"id":4,"cmd":"read_memory","addr":"0xFF0520","size":32}' '68k-0520'
SendCmd '{"id":5,"cmd":"read_memory","addr":"0xFF0540","size":16}' '68k-0540'
SendCmd '{"id":6,"cmd":"read_memory","addr":"0xFF0244","size":4}' '68k-0244'
SendCmd '{"id":7,"cmd":"crash_trail"}' 'trail'
SendCmd '{"id":8,"cmd":"rdb_get_state"}' '68kstate'
SendCmd '{"id":9,"cmd":"read_memory","addr":"0xFF0212","size":2}' '68k-0212'
SendCmd '{"id":10,"cmd":"read_memory","addr":"0xFF0554","size":32}' '68k-0554'
SendCmd '{"id":11,"cmd":"read_memory","addr":"0xFF0AAA","size":4096}' 'objtable'
SendCmd '{"id":12,"cmd":"read_memory","addr":"0xFF02BC","size":2}' '68k-02bc'
SendCmd '{"id":13,"cmd":"read_memory","addr":"0xFF0624","size":2}' '68k-0624'
SendCmd '{"id":14,"cmd":"read_memory","addr":"0xFF1AAA","size":4096}' 'objtable2'
$c.Close()
"probe ok tag=$Tag"
