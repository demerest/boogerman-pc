# s96: promote the proven splice (s96c.input) to replay-best.input with a new
# header; body copied verbatim (no retyping).
$ErrorActionPreference = 'Stop'
$root = 'S:\home\dev\boogerman-pc\native'
$lines = Get-Content "$root\tools\s96c.input"
$start = 0
while ($start -lt $lines.Count -and ($lines[$start] -like '#*' -or $lines[$start] -eq '')) { $start++ }
$body = $lines[$start..($lines.Count - 1)]
$header = @(
    '# replay-best.input — the latest PROVEN alive route, auto-played by',
    '# BoogermanReplay-US.bat in a VISIBLE, real-time window with sound.',
    '# Current best (s96): boot -> title -> Start -> FLATULENT SWAMPS LEVEL 1 ->',
    '# s90h proven prefix (thorns / spitter / slope / bridge red-walker kill /',
    '# trunk-walls / leech-trap lunge-whiff bypass / ledge / FIRST toilet top) ->',
    '# s96 SEWERS CROSSING = the user''s recorded manual play (s95 recorder,',
    '# build\play-input.log 6849..9600) rebased +3482 onto the prefix: flush',
    '# @~10411 -> SEWERS -> jump/boost cadence onto the UPPER PIPE platform,',
    '# traverse right ABOVE the slime pool (pool = DEATH), drop to the exit',
    '# toilet -> short DOWN press -> flush @~12707 back to LEVEL 1 (second',
    '# toilet) -> STOP ALIVE there. Zero life loss verified (s96c/s96d).',
    '# HUD bottom bar renders in level 1; still absent in sewers (s96 RE).',
    '# Audio in sewers is assist-idle (M3).',
    '# NO EXIT op: pads release at the end and the window stays open — grab the',
    '# keyboard and play on (arrows D-pad, Z flick, X jump, hold X/DOWN in air = boost).',
    '# s94: NO HOTKEY — auto-play runs from boot; first press ~35 s (title Start).',
    '# Any live keyboard/pad press >~0.3 s CANCELS auto-play (human takeover), so',
    '# playing manually first means the route will not run — relaunch to watch it.',
    '# Start is a bounded PRESS (s94).'
)
$out = New-Object System.Collections.Generic.List[string]
$out.AddRange([string[]]$header)
$inserted = $false
foreach ($l in $body) {
    if (-not $inserted -and $l -match '^\d+ ') {
        $out.Add('# --- s96: user-recorded crossing, rebased +3482 (flush @~10411, exit @~12707) ---')
        $inserted = $true
    }
    $out.Add($l)
}
Set-Content -Path "$root\tools\replay-best.input" -Value $out -Encoding ASCII
"total=$($out.Count)"
