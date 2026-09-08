#!/usr/bin/env python3
"""Reject the known macOS mpv Swift build regressions (#476, #520, #633).

Accept an Mpv binary, framework/xcframework directory, extracted archive, or app.
This is a static release gate, not a replacement for testing on older macOS.
"""

import argparse
from pathlib import Path
import re
import subprocess
import sys


def run_tool(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)


def find_binaries(path):
    if path.is_file():
        return [path.resolve()]
    return sorted({p.resolve() for p in path.rglob("Mpv") if p.is_file()})


def inspect_binary(binary, max_macos="11.0"):
    """Return architectures and diagnostics, inspecting every Mach-O slice."""
    architectures = set(run_tool("xcrun", "lipo", "-archs", str(binary)).split())
    errors = []
    max_version = tuple(int(v) for v in max_macos.split("."))
    max_version += (0,) * (3 - len(max_version))
    for arch in sorted(architectures):
        prefix = f"{binary} [{arch}]"
        build = run_tool("xcrun", "vtool", "-arch", arch, "-show-build", str(binary))
        if "LC_VERSION_MIN_MACOSX" not in build and not re.search(r"^\s*platform\s+MACOS\s*$", build, re.M):
            errors.append(f"{prefix}: not a macOS binary")
        versions = re.findall(r"^\s*(?:minos|version)\s+(\d+(?:\.\d+)+)\s*$", build, re.M)
        # 'version' also labels the linker version; only use it for legacy
        # LC_VERSION_MIN_MACOSX commands, which have no minos field.
        if "LC_BUILD_VERSION" in build:
            versions = re.findall(r"^\s*minos\s+(\d+(?:\.\d+)+)\s*$", build, re.M)
        if not versions:
            errors.append(f"{prefix}: missing macOS deployment target")
        for version in versions:
            parts = tuple(int(v) for v in version.split("."))
            parts += (0,) * (3 - len(parts))
            if parts > max_version:
                errors.append(f"{prefix}: deployment target {version} exceeds macOS {max_macos}")

        # minos can still say 11.0 when a newer Swift object was linked into
        # the C library. Check imports as well as the load command.
        undefined = run_tool("xcrun", "nm", "-arch", arch, "-um", str(binary))
        for line in undefined.splitlines():
            if "(undefined)" not in line:
                continue
            if "StaticArrayStorage" in line and "weak external" not in line:
                errors.append(f"{prefix}: Swift runtime unavailable on older macOS: {line.strip()}")
            if re.search(r"_OBJC_(?:META)?CLASS_\$__TtC5swift", line):
                errors.append(f"{prefix}: missing mpv Swift class: {line.strip()}")
    return architectures, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--require-arch", action="append", default=[], choices=["arm64", "x86_64"])
    parser.add_argument("--max-macos", default="11.0")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+(?:\.\d+){0,2}", args.max_macos):
        parser.error("--max-macos must be a version such as 11.0")
    binaries = find_binaries(args.path)
    if not binaries:
        parser.error(f"no Mpv binary found under {args.path}")
    errors = []
    found_architectures = set()
    for binary in binaries:
        try:
            architectures, diagnostics = inspect_binary(binary, args.max_macos)
            found_architectures.update(architectures)
            errors.extend(diagnostics)
            if not diagnostics:
                print(f"PASS: {binary} ({', '.join(sorted(architectures))})")
        except (OSError, subprocess.CalledProcessError) as exc:
            errors.append(f"{binary}: inspection failed: {getattr(exc, 'output', str(exc))}")
    for arch in sorted(set(args.require_arch) - found_architectures):
        errors.append(f"required architecture missing: {arch}")
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
