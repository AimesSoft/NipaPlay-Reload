#!/usr/bin/env python3
"""Prepare X46 AOT only, reusing the unchanged X45 native library. No node launch."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile
import argparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--update', action='store_true', help='Explicitly refresh this previously prepared source, preserving build outputs')
args = parser.parse_args()

windows = os.name == 'nt'
base = Path('D:/nipaplay-next') if windows else Path.home()/'nipaplay-next'
archive = base/'x46-headless.zip' if windows else Path('/mnt/d/nipaplay-next/x46-headless.zip')
source = base/'x46-headless'
if source.exists() and not args.update:
    raise SystemExit('X46 source already exists; preserve it and choose an explicit update.')
source.mkdir(exist_ok=args.update)
with zipfile.ZipFile(archive) as bundle:
    bundle.extractall(source)
binary = source/'build/headless'
binary.mkdir(parents=True, exist_ok=args.update)
library = 'nipaplay_headless_native.dll' if windows else 'libnipaplay_headless_native.so'
shutil.copy2(base/'x45-headless/build/headless'/library, binary/library)
dart = base/'x43-tools/dart-sdk/bin'/('dart.exe' if windows else 'dart')
output = binary/('nipaplay-headless.exe' if windows else 'nipaplay-headless')
log = source/('build-windows.txt' if windows else 'build-linux.txt')
with log.open('w', encoding='utf-8') as handle:
    subprocess.run([str(dart), 'compile', 'exe', '--packages=.dart_tool/package_config.json',
        'bin/nipaplay_headless.dart', '-o', str(output)], cwd=source,
        stdout=handle, stderr=subprocess.STDOUT, check=True)
print(json.dumps({'compiledOnly': True, 'platform': 'windows-x64' if windows else 'linux-x64',
    'nativeReusedFromX45': True, 'log': str(log),
    'artifacts': [{'name': f.name, 'bytes': f.stat().st_size,
        'sha256': hashlib.file_digest(f.open('rb'), 'sha256').hexdigest()}
        for f in sorted(binary.iterdir()) if f.is_file()]}))
