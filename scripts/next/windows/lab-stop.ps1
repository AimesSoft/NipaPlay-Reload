$W = 'D:\nipaplay-next\win-next'
$pidFile = "$W\lab\winlab\logs\pid.txt"
if (Test-Path $pidFile) {
  $id = [int](Get-Content $pidFile)
  $p = Get-Process -Id $id -ErrorAction SilentlyContinue
  if ($p -and $p.Path -like "$W\repo\build\*") {
    # The programs it started (DSH, hooks) first, then the application.
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$id" | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(8000)) { $p.Kill() }
    "stopped $id"
  } else { 'not running' }
  Remove-Item $pidFile
}
schtasks /delete /tn nipa-lab-winlab /f 2>$null | Out-Null
