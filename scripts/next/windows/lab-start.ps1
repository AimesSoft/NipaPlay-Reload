# Starts the Debug NipaPlay build as the lab profile "winlab" in the user's interactive session,
# through a one-shot scheduled task (nipa-lab-winlab, deleted again by lab-stop.ps1).
# All of its files are under D:\nipaplay-next\win-next\lab\winlab: APPDATA / LOCALAPPDATA point there and
# NIPAPLAY_LAB_ROOT redirects every path the app asks for; the user's own NipaPlay data is never touched.
# The window starts without activation at the bottom of the stack and has no taskbar entry.
$ErrorActionPreference = 'Stop'
$W = 'D:\nipaplay-next\win-next'
New-Item -ItemType Directory -Force "$W\lab\winlab\logs" | Out-Null
Remove-Item "$W\lab\winlab\logs\run.log" -ErrorAction SilentlyContinue
schtasks /create /tn nipa-lab-winlab /tr "$W\scripts\lab-run.cmd" /sc once /st 23:59 /it /f | Out-Null
schtasks /run /tn nipa-lab-winlab | Out-Null
$deadline = (Get-Date).AddSeconds(40)
do { Start-Sleep 1; $app = Get-Process NipaPlay -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$W\repo\build\*" } } until ($app -or (Get-Date) -gt $deadline)
if (-not $app) { throw 'NipaPlay did not start' }
$app.Id | Set-Content "$W\lab\winlab\logs\pid.txt"
"started app $($app.Id), session $($app.SessionId)"
