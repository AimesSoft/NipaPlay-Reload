@echo off
call D:\nipaplay-next\win-next\env.cmd
call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
set CARGO_HOME=D:\nipaplay-next\win-next\cargo-home
set PATH=%USERPROFILE%\.cargo\bin;D:\nipaplay-next\win-next\repo\build\windows\x64\runner\Debug;%PATH%
cd /d D:\nipaplay-next\win-next\repo
call flutter test --no-pub --reporter expanded %* 2>&1
echo TEST_EXIT %ERRORLEVEL% %TIME%
