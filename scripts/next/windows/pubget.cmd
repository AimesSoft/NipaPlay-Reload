@echo off
call D:\nipaplay-next\win-next\env.cmd
if exist %PUB_CACHE%\git rmdir /s /q %PUB_CACHE%\git
if exist %PUB_CACHE%\active_roots rmdir /s /q %PUB_CACHE%\active_roots
call flutter pub get 2>&1
echo PUBGET_EXIT %ERRORLEVEL%
