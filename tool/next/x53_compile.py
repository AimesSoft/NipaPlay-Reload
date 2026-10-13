"""Compile the transferred public Dart graph, without starting any node."""
import hashlib
import json
from pathlib import Path
import subprocess
import zipfile
import os

windows = os.name == 'nt'
base = Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next'
source = base / 'x53-headless'
source.mkdir(exist_ok=True)
bundle = base / 'x53-headless.zip' if windows else Path('/mnt/d/nipaplay-next/x53-headless.zip')
with zipfile.ZipFile(bundle) as archive:
    archive.extractall(source)
output = source / 'build/headless'
output.mkdir(parents=True, exist_ok=True)
dart = base / 'x43-tools/dart-sdk/bin' / ('dart.exe' if windows else 'dart')
target = output / ('nipaplay-headless.exe' if windows else 'nipaplay-headless')
with (source / 'compile.txt').open('w') as log:
    subprocess.run([str(dart), 'compile', 'exe', '--packages=.dart_tool/package_config.json',
        'bin/nipaplay_headless.dart', '-o', str(target)], cwd=source,
        stdout=log, stderr=subprocess.STDOUT, check=True)
print(json.dumps({'compiledOnly': True, 'platform': 'windows-x64' if windows else 'linux-x64',
    'source': str(source), 'bytes': target.stat().st_size,
    'sha256': hashlib.file_digest(target.open('rb'), 'sha256').hexdigest(),
    'nativeUnchanged': True, 'nodeStarted': False}))
