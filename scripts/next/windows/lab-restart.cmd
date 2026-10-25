@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File D:\nipaplay-next\win-next\scripts\lab-stop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\nipaplay-next\win-next\scripts\lab-start.ps1 %*
