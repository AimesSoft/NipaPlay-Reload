@echo off
rem usage: nx.cmd <op> [k=v ...]   -- drives the winlab instance (Dart VM service extension)
set PYTHONUTF8=1
python D:\nipaplay-next\win-next\scripts\nx.py D:\nipaplay-next\win-next\lab\winlab\logs\run.log %*
