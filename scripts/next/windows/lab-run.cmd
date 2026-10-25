@echo off
rem Runs inside the user's interactive session (started by the scheduled task nipa-lab-winlab).
rem Everything the instance writes goes under lab\winlab; APPDATA / LOCALAPPDATA are redirected there.
set W=D:\nipaplay-next\win-next
set NIPAPLAY_PROFILE=winlab
set NIPAPLAY_LAB_ROOT=%W%\lab
set APPDATA=%W%\lab\winlab\appdata\roaming
set LOCALAPPDATA=%W%\lab\winlab\appdata\local
set NIPAPLAY_LAB_DHT=0
if exist %W%\lab\winlab\extra-env.cmd call %W%\lab\winlab\extra-env.cmd
if not exist %APPDATA% mkdir %APPDATA%
if not exist %LOCALAPPDATA% mkdir %LOCALAPPDATA%
if not exist %W%\lab\winlab\logs mkdir %W%\lab\winlab\logs
cd /d %W%\repo\build\windows\x64\runner\%BUILD_DIR%
if "%BUILD_DIR%"=="" cd /d %W%\repo\build\windows\x64\runner\Debug
NipaPlay.exe > %W%\lab\winlab\logs\run.log 2>&1
