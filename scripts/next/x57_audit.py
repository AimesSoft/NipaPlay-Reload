#!/usr/bin/env python3
"""Read-only owned-process and retained-evidence audit; never output secrets."""
import json
import os
from pathlib import Path
import re
import subprocess

from x52_experiment import credentials

WORKSPACE = Path(__file__).resolve().parents[2]
OUT = WORKSPACE / "docs/next/evidence/x57"


def main():
    _, _, key = credentials()
    records = [json.loads(p.read_text()) for p in OUT.glob("*/summary.json")]
    profiles = {row["profile"] for row in records}
    pids = {row["appPid"] for row in records}
    pids.update(pid for row in records for pid in row.get("ownedPids", []))
    live = []
    for pid in sorted(pids):
        try:
            os.kill(pid, 0)
            live.append(pid)
        except ProcessLookupError:
            pass
    # Only emit PIDs whose cwd is one of this experiment's owned profiles.
    listing = subprocess.run(["/usr/sbin/lsof", "-n", "-P", "-Fpn", "-d", "cwd"],
                             capture_output=True, text=True).stdout
    current = None
    cwd_pids = []
    for line in listing.splitlines():
        if line.startswith("p"):
            current = int(line[1:])
        if line.startswith("n") and any("/" + name + "/" in line or line.endswith("/" + name)
                                        for name in profiles):
            cwd_pids.append(current)
    files = [p for p in OUT.rglob("*") if p.is_file()]
    key_paths = [str(p.relative_to(OUT)) for p in files if key.encode() in p.read_bytes()]
    patterns = {
        "privateKey": rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
        "authenticatedUrl": rb"https?://[^\s/\"']+:[^\s/\"']+@",
        "bearerValue": rb"\bBearer\s+[A-Za-z0-9_+/=.-]{20,}",
    }
    matches = {name: [str(p.relative_to(OUT)) for p in files if re.search(pattern, p.read_bytes())]
               for name, pattern in patterns.items()}
    result = {
        "ownedAppPids": [row["appPid"] for row in records], "allRecordedPids": sorted(pids),
        "liveRecordedPids": live, "ownedCwdPids": cwd_pids,
        "profiles": [{"profile": name, "removed": not (Path.home() /
            "Library/Application Support/NipaPlay/LabProfiles" / name).exists()} for name in sorted(profiles)],
        "evidenceFiles": len(files), "modelKeyMatches": len(key_paths), "modelKeyPaths": key_paths,
        "highConfidenceSecretPatterns": matches,
        "experimentFileScans": [{"profile": row["profile"], **row["modelSecretScan"]} for row in records],
    }
    result["ok"] = (not live and not cwd_pids and not key_paths and not any(matches.values()) and
                    all(row["removed"] for row in result["profiles"]) and
                    all(row["leaks"] == 0 for row in result["experimentFileScans"]))
    (OUT / "final-audit.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"ok": result["ok"], "profiles": len(profiles), "evidenceFiles": len(files),
                      "liveOwnedProcesses": len(live) + len(cwd_pids), "modelKeyMatches": len(key_paths),
                      "patternMatches": {name: len(paths) for name, paths in matches.items()}}))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
