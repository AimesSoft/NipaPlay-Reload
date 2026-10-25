@echo off
rem usage: vm.cmd <ext.nipaplay.nextui|ext.nipaplay.hostSettings> [k=v ...] -- drives the winlab instance
set PYTHONUTF8=1
python D:\nipaplay-next\win-next\scripts\vm.py D:\nipaplay-next\win-next\lab\winlab\logs\run.log %*
