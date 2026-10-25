@echo off
rem usage: log.cmd [lines]  -- tail of the winlab run.log
powershell -NoProfile -Command "Get-Content D:\nipaplay-next\win-next\lab\winlab\logs\run.log -Tail %1"
