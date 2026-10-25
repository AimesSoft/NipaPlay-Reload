@echo off
rem Stops the winlab instance, rebuilds Debug, starts it again (seed + start).
powershell -NoProfile -ExecutionPolicy Bypass -File D:\nipaplay-next\win-next\scripts\lab-stop.ps1
call D:\nipaplay-next\win-next\build.cmd debug > D:\nipaplay-next\win-next\build-debug3.log 2>&1
findstr /c:BUILD_EXIT /c:"error " D:\nipaplay-next\win-next\build-debug3.log
