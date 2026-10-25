# NipaPlay Next on Windows: build, test and acceptance scripts

These are the scripts the Windows acceptance of Next ran with (workstation `D:\nipaplay-next\win-next`; the
paths are written into them). Nothing here touches the user's own NipaPlay data: the instance is a lab profile.

- `setup1.cmd`, `env.cmd`, `pubget.cmd`, `build.cmd debug|release`: the code arrives as a `git bundle`, Flutter is
  `dsh-platforms\flutter-win\flutter` (3.44.6), Visual Studio 2022 does the C++.
- `t.cmd <flutter test arguments>`: `flutter test` with the build's DLLs (quickjs_c_bridge.dll) and the Rust
  tools (cargo) on the path. The mesh tests need `cargo build` in `rust`, `server\nipaplay-mesh-coordinator` and
  `rust\mesh --examples` first.
- A **lab profile on Windows** (Debug builds only): `NIPAPLAY_PROFILE=<name>` and `NIPAPLAY_LAB_ROOT=<dir>`; the
  profile is `<dir>\<name>`. APPDATA and LOCALAPPDATA are pointed into it by `lab-run.cmd`, every path the app asks
  for is redirected, credentials are a file in the profile. `lab-seed.ps1` writes the two Labs preferences (the
  Next consent and the Next interface), `lab-start.ps1` starts it in the user's interactive session through a
  one-shot scheduled task (`nipa-lab-winlab`, removed by `lab-stop.ps1`): the window starts under the others,
  without activation and without a taskbar entry. `lab-start-cim.ps1` starts it in session 0 (nothing on the
  desktop, and no GPU there).
- Driving it: `vm.cmd ext.nipaplay.hostSettings op=installDsh|runtime|setModel|checkModel` and
  `nx.cmd <op>` (`ext.nipaplay.nextui`) call the Dart VM service extensions (the URL is read from
  `lab\winlab\logs\run.log`); `nipa.cmd`, `call.cmd ACTION [json]` call the harness actions of the instance;
  `say.cmd text` says it to Nipa and waits for the turn.
- The model: the key is never in a script. Set it with `vm.cmd ext.nipaplay.hostSettings op=setModel
  choice=@file.json --delete-files` (`{"source":"nipaplay","provider":..,"baseUrl":..,"model":..,"apiKey":..,
  "api":"responses"}`; the file is deleted after the call, the lab keeps the key in memory only).
- `accept-windows.cmd`: the one-click acceptance (kernels, hook, awkward paths, app.restart is `call.cmd
  app.restart`); `accept-kernels.py`, `open-awkward.py`, `mk-longpath.py`, `live-hook.py`, `mem-test.py` are its parts.
- Media: `media\library` holds a 75 s 720p excerpt of Sintel with its embedded subtitles (ffmpeg `-ss 90 -t 75`),
  `Sintel.2010.720p.zh-Hans.srt` shifted by -90 s, a `Sintel.2010.720p.xml` danmaku file and Big Buck Bunny.
