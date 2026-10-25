# Starts the winlab instance through WMI (no job object, session 0, nothing on the user's desktop).
# Used where the instance must outlive a relaunch (app.restart): a scheduled task's job kills what it started.
$ErrorActionPreference = 'Stop'
$W = 'D:\nipaplay-next\win-next'
$root = "$W\lab\winlab"
$dir = "$W\repo\build\windows\x64\runner\Debug"
New-Item -ItemType Directory -Force "$root\appdata\roaming", "$root\appdata\local", "$root\logs" | Out-Null
$log = "$root\logs\run-cim.log"
Remove-Item $log -ErrorAction SilentlyContinue
$sets = "set NIPAPLAY_PROFILE=winlab&& set NIPAPLAY_LAB_ROOT=$W\lab&& set APPDATA=$root\appdata\roaming&& set LOCALAPPDATA=$root\appdata\local&& set NIPAPLAY_LAB_DHT=0&&"
$cmd = "cmd.exe /c ""$sets cd /d $dir&& NipaPlay.exe > $log 2>&1"""
$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd; CurrentDirectory = $dir }
Start-Sleep 8
$app = Get-CimInstance Win32_Process -Filter "Name='NipaPlay.exe'" | Where-Object { $_.ParentProcessId -eq $r.ProcessId }
"started app $($app.ProcessId)"
