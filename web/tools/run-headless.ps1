# run-headless.ps1 - run the port (or its test harness) in headless Chrome.
# Chrome is a GUI-subsystem binary: Start-Process -Wait with redirected output
# is required (call-operator returns immediately and redirects read empty).
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-headless.ps1 -Url "file:///S:/home/dev/boogerman-pc/test/harness.html" -Out S:\home\dev\boogerman-pc\test\harness-dom.html -Mode dom -Budget 30000
#   powershell ... -Url "file:///S:/home/dev/boogerman-pc/index.html?shot=1" -Out shot.png -Mode shot -Budget 12000
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Out,
    [ValidateSet('dom', 'shot')][string]$Mode = 'dom',
    [int]$Budget = 30000,
    [int]$WindowW = 1280,
    [int]$WindowH = 800
)
$ErrorActionPreference = 'Stop'
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
if (-not (Test-Path $chrome)) { $chrome = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' }
$prof = Join-Path $env:TEMP ('bp-chrome-' + [guid]::NewGuid().ToString('N'))
$argList = @(
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    ('--user-data-dir=' + $prof),
    ('--window-size=' + $WindowW + ',' + $WindowH),
    '--autoplay-policy=no-user-gesture-required',
    '--mute-audio'
)
if ($Mode -eq 'dom') {
    $argList += ('--virtual-time-budget=' + $Budget)
    $argList += ('--timeout=' + ($Budget * 4))
    $argList += '--dump-dom'
} else {
    $argList += ('--virtual-time-budget=' + $Budget)
    $argList += ('--timeout=' + ($Budget * 4))
    $argList += ('--screenshot=' + $Out)
}
$argList += $Url
$so = $Out + '.stdout'
$se = $Out + '.stderr'
$p = Start-Process -FilePath $chrome -ArgumentList $argList -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
Write-Output ('chrome exit: ' + $p.ExitCode)
if ($Mode -eq 'dom') {
    $dom = [IO.File]::ReadAllText($so)
    [IO.File]::WriteAllText($Out, $dom, (New-Object System.Text.UTF8Encoding($false)))
    Write-Output ('dom written: ' + $Out + ' (' + $dom.Length + ' chars)')
} else {
    if (Test-Path $Out) { Write-Output ('screenshot written: ' + $Out + ' (' + (Get-Item $Out).Length + ' bytes)') }
    else { Write-Output 'SCREENSHOT MISSING' }
}
Remove-Item -Recurse -Force $prof -ErrorAction SilentlyContinue
