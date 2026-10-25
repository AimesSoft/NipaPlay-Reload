@echo off
call D:\nipaplay-next\win-next\env.cmd
set MODE=%1
echo === build %MODE% %DATE% %TIME%
call flutter build windows --%MODE% 2>&1
echo BUILD_EXIT %ERRORLEVEL% %TIME%
