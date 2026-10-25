@echo off
rem usage: say.cmd <text>  -- says it to Nipa in the winlab instance, waits until the turn ends, prints the last turn
set PYTHONUTF8=1
python D:\nipaplay-next\win-next\scripts\say.py %*
