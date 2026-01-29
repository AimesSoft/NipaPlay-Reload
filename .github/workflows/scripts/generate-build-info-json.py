#!/usr/bin/env python3
import datetime
import json
import os
import platform
import subprocess
import sys


def _run(cmd):
    try:
        output = subprocess.check_output(
            cmd, stderr=subprocess.DEVNULL, text=True, errors="ignore"
        )
        return output.strip()
    except Exception:
        return ""


def _run_first(commands):
    for cmd in commands:
        output = _run(cmd)
        if output:
            return output
    return ""


def _read_file(path):
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as handle:
            return handle.read()
    except Exception:
        return ""


def _parse_key_value_lines(text, separator=":"):
    result = {}
    for line in text.splitlines():
        if separator not in line:
            continue
        key, value = line.split(separator, 1)
        result[key.strip()] = value.strip()
    return result


def _detect_cpu():
    system = platform.system().lower()
    if system == "linux":
        cpuinfo = _read_file("/proc/cpuinfo")
        for key in ("model name", "hardware", "processor"):
            for line in cpuinfo.splitlines():
                if line.lower().startswith(key):
                    return line.split(":", 1)[1].strip()
        return ""
    if system == "darwin":
        return _run_first(
            [
                ["sysctl", "-n", "machdep.cpu.brand_string"],
                ["sysctl", "-n", "hw.model"],
            ]
        )
    if system == "windows":
        return _run_first(
            [
                [
                    "powershell",
                    "-NoProfile",
                    "-Command",
                    "(Get-CimInstance Win32_Processor | Select -First 1 -ExpandProperty Name)",
                ],
                ["wmic", "cpu", "get", "Name", "/value"],
                ["wmic", "cpu", "get", "Name"],
            ]
        ).replace("Name=", "").strip()
    return platform.processor() or ""


def _detect_memory_bytes():
    system = platform.system().lower()
    if system == "linux":
        meminfo = _read_file("/proc/meminfo")
        for line in meminfo.splitlines():
            if line.lower().startswith("memtotal"):
                parts = line.split()
                if len(parts) >= 2 and parts[1].isdigit():
                    return int(parts[1]) * 1024
        return 0
    if system == "darwin":
        output = _run(["sysctl", "-n", "hw.memsize"])
        return int(output) if output.isdigit() else 0
    if system == "windows":
        output = _run_first(
            [
                [
                    "powershell",
                    "-NoProfile",
                    "-Command",
                    "(Get-CimInstance Win32_ComputerSystem | Select -First 1 -ExpandProperty TotalPhysicalMemory)",
                ],
                ["wmic", "computersystem", "get", "TotalPhysicalMemory", "/value"],
            ]
        )
        output = output.replace("TotalPhysicalMemory=", "").strip()
        return int(output) if output.isdigit() else 0
    return 0


def _detect_os():
    system = platform.system()
    lower = system.lower()
    if lower == "linux":
        os_release = _read_file("/etc/os-release")
        data = _parse_key_value_lines(os_release, "=")
        pretty = data.get("PRETTY_NAME", "").strip().strip('"')
        if pretty:
            return pretty
        return f"{system} {platform.release()}".strip()
    if lower == "darwin":
        name = _run(["sw_vers", "-productName"])
        version = _run(["sw_vers", "-productVersion"])
        if name and version:
            return f"{name} {version}"
        return f"{system} {platform.release()}".strip()
    if lower == "windows":
        caption = _run_first(
            [
                [
                    "powershell",
                    "-NoProfile",
                    "-Command",
                    "(Get-CimInstance Win32_OperatingSystem | Select -First 1 -ExpandProperty Caption)",
                ],
                ["wmic", "os", "get", "Caption", "/value"],
            ]
        )
        caption = caption.replace("Caption=", "").strip()
        if caption:
            return caption
        return f"{system} {platform.release()}".strip()
    return f"{system} {platform.release()}".strip()


def _normalize_arch(machine):
    if not machine:
        return ""
    lower = machine.lower()
    if lower in ("x86_64", "amd64"):
        return "x86_64"
    if lower in ("aarch64", "arm64"):
        return "arm64"
    if lower in ("armv7l", "armv7"):
        return "armv7"
    if lower in ("armv6l", "armv6"):
        return "armv6"
    if lower in ("i386", "i686", "x86"):
        return "x86"
    return machine


def _build_payload():
    now = datetime.datetime.utcnow()
    return {
        "build_time": now.strftime("%Y-%m-%d %H:%M:%S UTC"),
        "build_time_epoch": int(now.timestamp()),
        "cpu": _detect_cpu(),
        "memory_bytes": _detect_memory_bytes(),
        "os": _detect_os(),
        "arch": _normalize_arch(platform.machine()),
    }


def main():
    output_path = "assets/build_info.json"
    if len(sys.argv) > 1:
        output_path = sys.argv[1]
    output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    payload = _build_payload()
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True, ensure_ascii=True)
        handle.write("\n")

    print(f"Wrote build info to {output_path}")


if __name__ == "__main__":
    main()
