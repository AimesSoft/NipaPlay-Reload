@echo off
rem usage: grep-log.cmd <text>  -- lines of the winlab run.log containing the text
findstr /i /c:%1 D:\nipaplay-next\win-next\lab\winlab\logs\run.log
