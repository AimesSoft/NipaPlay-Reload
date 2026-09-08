#!/usr/bin/env python3
"""Launch the actual app on a CI desktop and retain startup/crash evidence."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import time


def capture(path, command):
    with path.open("w") as output:
        try:
            subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=20)
        except (OSError, subprocess.TimeoutExpired) as error:
            output.write(str(error))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=int, default=45)
    args = parser.parse_args()
    if args.seconds < 10:
        parser.error("--seconds must be at least 10")
    app = args.app.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with (app / "Contents/Info.plist").open("rb") as info:
        executable_name = plistlib.load(info)["CFBundleExecutable"]
    executable = app / "Contents/MacOS" / executable_name
    capture(output / "system.txt", ["sw_vers"])
    capture(output / "architecture.txt", ["uname", "-m"])
    mpv = app / "Contents/Frameworks/Mpv.framework/Mpv"
    capture(output / "mpv-load-commands.txt", ["otool", "-l", str(mpv)])
    capture(output / "mpv-symbols.txt", ["nm", "-u", str(mpv)])
    capture(output / "mpv-libraries.txt", ["otool", "-L", str(mpv)])
    start = time.time()
    process = None
    survived = False
    try:
        with (output / "startup.log").open("w") as log:
            process = subprocess.Popen(
                [str(executable)], stdout=log, stderr=subprocess.STDOUT,
                env={**os.environ, "DYLD_PRINT_LIBRARIES": "1"},
            )
            deadline = time.monotonic() + args.seconds
            while process.poll() is None and time.monotonic() < deadline:
                time.sleep(1)
            survived = process.poll() is None
            if survived:
                capture(output / "sample.txt", ["sample", str(process.pid), "1", "1"])
            result = {
                "app": str(app), "pid": process.pid,
                "survived": survived, "exit_code": process.poll(),
                "duration_seconds": round(time.time() - start, 1),
            }
            (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps(result), flush=True)
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        capture(output / "unified.log", [
            "log", "show", "--last", "3m", "--style", "compact",
            "--predicate", f'process == "{executable_name}"',
        ])
        reports = Path.home() / "Library/Logs/DiagnosticReports"
        for report in reports.glob(f"{executable_name}*"):
            if report.is_file() and report.stat().st_mtime >= start:
                shutil.copy2(report, output / report.name)
    if not survived:
        print((output / "startup.log").read_text(errors="replace")[-12000:])
        raise SystemExit("App exited before the startup observation period completed")


if __name__ == "__main__":
    main()
