#!/usr/bin/env bash
set -euo pipefail
entitlements_file=$(mktemp)
trap 'rm -f "$entitlements_file"' EXIT
codesign -d --entitlements - --xml "$1" > "$entitlements_file"
python3 - "$entitlements_file" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as source:
    entitlements = plistlib.load(source)
if 'com.apple.security.app-sandbox' in entitlements:
    raise SystemExit('GitHub macOS builds must not contain app-sandbox')
if entitlements.get('com.apple.security.cs.allow-jit') is not True:
    raise SystemExit('Flutter requires allow-jit under hardened runtime')
print('PASS: macOS entitlements contain allow-jit and no app-sandbox')
PY
