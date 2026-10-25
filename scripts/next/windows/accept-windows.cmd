@echo off
rem One-click acceptance of the Next experience on the Windows workstation: starts the Debug build as the lab
rem profile "winlab" (a window under the user's other windows, no focus taken, files only under
rem D:\nipaplay-next\win-next\lab), plays the library's Sintel excerpt on each of the four kernels (seek, pause,
rem subtitle track, danmaku, ui.capture and playback.capture, screenshots of the application window only into
rem lab\winlab\shots), checks a hook, the long-path scan and app.restart, then closes it.
rem Prepared once: the Debug build (build.cmd debug), media\library with Sintel.2010.720p.mkv / .zh-Hans.srt / .xml
rem and BigBuckBunny.mp4 (see README.md). The lab keeps the model key in memory only; chat is not part of this script.
set S=D:\nipaplay-next\win-next\scripts
set L=D:\nipaplay-next\win-next\lab\winlab
echo === stop what runs, seed the preferences, start
powershell -NoProfile -ExecutionPolicy Bypass -File %S%\lab-stop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File %S%\lab-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File %S%\lab-start.ps1 || goto :end
timeout /t 15 /nobreak >nul
echo {"path":"D:\\nipaplay-next\\win-next\\media\\library\\Sintel.2010.720p.mkv"}> %L%\accept-open.json
call %S%\call.cmd playback.open @%L%\accept-open.json | findstr /c:"\"status\""
timeout /t 5 /nobreak >nul
echo === four kernels
call %S%\accept-kernels.cmd mdk media_kit erika video_player > %L%\accept-kernels.json
type %L%\accept-kernels.json
echo === a Python hook on playback.started, long and awkward paths
python %S%\live-hook.py
python %S%\open-awkward.py
echo === log
findstr /i /c:"main isolate" /c:"Unhandled" /c:"MissingPlugin" %L%\logs\run.log
echo (no lines above: the main isolate did not block, nothing unhandled)
:end
powershell -NoProfile -ExecutionPolicy Bypass -File %S%\lab-stop.ps1
