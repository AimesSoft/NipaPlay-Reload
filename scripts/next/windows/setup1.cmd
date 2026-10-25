@echo off
cd /d D:\nipaplay-next\win-next
if not exist repo git clone --branch next/win-next win-next.bundle repo
cd repo
git log --oneline -1
if not exist third_party\media-kit-upstream\libs tar -xzf ..\mku-win.tgz -C third_party
xcopy /E /I /Q /Y D:\nipaplay-next\win-teardown\pub-cache D:\nipaplay-next\win-next\pub-cache >nul
dir /b third_party\media-kit-upstream
echo done
