#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
from pathlib import Path


def test_files():
    return sorted(
        str(Path(directory, name))
        for directory, _, names in os.walk("test", followlinks=False, onerror=raise_error)
        for name in names
        if name.endswith("_test.dart") and Path(directory, name).is_file()
    )


def raise_error(error):
    if not (isinstance(error, FileNotFoundError) and error.filename == "test"):
        raise error


def main():
    parser = argparse.ArgumentParser(description="Run one file-level Flutter test shard.")
    parser.add_argument("index", type=int)
    parser.add_argument("total", type=int)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if not 0 <= args.index < args.total or not args.command:
        parser.error("expected 0 <= index < total and a Flutter test command")

    files = test_files()[args.index::args.total]
    print(f"Shard {args.index + 1}/{args.total}: {len(files)} files", flush=True)
    for path in files:
        print(path)
    if not files:
        return 0

    sys.stdout.flush()
    environment = os.environ.copy()
    for key in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        environment.pop(key, None)
    return subprocess.call([*args.command, *files], env=environment)


if __name__ == "__main__":
    raise SystemExit(main())
