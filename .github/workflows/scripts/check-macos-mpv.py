#!/usr/bin/env python3
"""Reject libmpv artifacts that repeat the macOS 14 startup regression (#476)."""

import argparse
from pathlib import Path
import re
import subprocess


def inspect(binary):
    architectures = subprocess.check_output(
        ["lipo", "-archs", str(binary)], text=True,
    ).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise ValueError(f"Expected universal libmpv, got {architectures}: {binary}")
    for architecture in architectures:
        commands = subprocess.check_output(
            ["otool", "-arch", architecture, "-l", str(binary)], text=True,
        )
        versions = re.findall(r"^\s+(?:minos|version) (\d+\.\d+(?:\.\d+)?)$", commands, re.M)
        # LC_BUILD_VERSION's minos is authoritative on current builds. Older
        # Mach-O files instead contain LC_VERSION_MIN_MACOSX.
        minimum = re.search(r"^\s+minos (\S+)$", commands, re.M)
        if minimum:
            version = minimum.group(1)
        elif "LC_VERSION_MIN_MACOSX" in commands and versions:
            version = versions[0]
        else:
            raise ValueError(f"Missing macOS deployment target in {architecture}: {binary}")
        if tuple(map(int, version.split(".")[:2])) > (11, 0):
            raise ValueError(f"libmpv {architecture} requires macOS {version}, expected <=11.0")
        symbols = subprocess.check_output(
            ["nm", "-arch", architecture, "-m", "-u", str(binary)], text=True,
        )
        for line in symbols.splitlines():
            if "_$ss20__StaticArrayStorageCN" in line and "weak" not in line:
                raise ValueError(f"libmpv {architecture} requires a newer Swift runtime: {line.strip()}")
        print(f"PASS {architecture}: macOS {version}, no strong __StaticArrayStorage import ({binary})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="Extracted libmpv xcframework archive")
    args = parser.parse_args()
    binaries = sorted({path.resolve() for path in args.root.rglob("Mpv") if path.is_file()})
    if not binaries:
        parser.error(f"No Mpv framework binary under {args.root}")
    for binary in binaries:
        inspect(binary)


if __name__ == "__main__":
    main()
