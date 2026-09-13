param([string]$PlayerPath = (Join-Path $PSScriptRoot 'NipaPlay.exe'))
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PlayerPath -PathType Leaf)) {
    throw 'Put this script next to NipaPlay.exe, or pass -PlayerPath with the executable path.'
}
$player = (Resolve-Path -LiteralPath $PlayerPath).Path
if (Get-Process -Name NipaPlay -ErrorAction SilentlyContinue) {
    throw 'Please close the existing NipaPlay window before starting this diagnostic session.'
}
$traceDir = Join-Path ([IO.Path]::GetDirectoryName($player)) 'dfm-traces'
New-Item -ItemType Directory -Path $traceDir -Force | Out-Null
$tracePath = Join-Path $traceDir ('dfm-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.jsonl')
$previousTrace = $env:NIPAPLAY_DFM_TRACE
try {
    $env:NIPAPLAY_DFM_TRACE = $tracePath
    Write-Host "Trace file: $tracePath"
    Write-Host 'Play a DFM+ segment for 30-60 seconds, note the approximate stutter time, then close the player.'
    $process = Start-Process -FilePath $player -WorkingDirectory ([IO.Path]::GetDirectoryName($player)) -WindowStyle Normal -PassThru
    $process.WaitForExit()
} finally {
    $env:NIPAPLAY_DFM_TRACE = $previousTrace
}
if (Test-Path -LiteralPath $tracePath) {
    Write-Host "Send this file for analysis: $tracePath"
} else {
    Write-Warning 'No trace created. Use the diagnostic build, select DFM+, and ensure the folder is writable.'
}
