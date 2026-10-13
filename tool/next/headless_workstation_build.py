#!/usr/bin/env python3
"""Compile an unpacked headless bundle in the workstation working directory.

Does not start a node, load a native library, enroll credentials or run tests.
Uses installed compilers read-only; Cargo homes and all outputs stay local.
"""
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tomllib

windows = os.name == 'nt'
base = Path('D:/nipaplay-next') if windows else Path.home() / 'nipaplay-next'
source = base / 'x45-headless'
binary = source / 'build/headless'
binary.mkdir(parents=True, exist_ok=True)
tools = base / 'x43-tools/dart-sdk/bin'
dart = tools / ('dart.exe' if windows else 'dart')
user_cargo = Path.home() / '.cargo'
rustup = user_cargo / 'bin' / ('rustup.exe' if windows else 'rustup')
rustc = Path(subprocess.check_output([str(rustup), 'which', 'rustc'], text=True).strip())
cargo = rustc.parent / ('cargo.exe' if windows else 'cargo')
cargo_home = base / 'x45-tools/cargo'
cargo_home.mkdir(parents=True, exist_ok=True)
cache_source = Path('C:/Users/labuser/.cargo') if windows else Path('/mnt/c/Users/labuser/.cargo')
packages = tomllib.loads((source / 'native/rust/headless/Cargo.lock').read_text())['package']
# Reuse cached crate archives and sparse index entries, without writing the
# user's registry or downloading hundreds of individual files on campus.
missing = []
for package in packages:
    if not package.get('source', '').startswith('registry+'):
        continue
    name, version = package['name'], package['version']
    archives = list((cache_source / 'registry/cache').glob(f'*/{name}-{version}.crate'))
    if not archives:
        missing.append(f'{name}-{version}')
        continue
    for archive in archives:
        target = cargo_home / archive.relative_to(cache_source)
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists(): shutil.copy2(archive, target)
    suffix = (f'1/{name}' if len(name) == 1 else f'2/{name}' if len(name) == 2
              else f'3/{name[0]}/{name}' if len(name) == 3 else f'{name[:2]}/{name[2:4]}/{name}')
    for index in (cache_source / 'registry/index').glob('*/.cache'):
        entry = index / suffix
        if entry.exists():
            target = cargo_home / entry.relative_to(cache_source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(entry, target)
            config = index.parent / 'config.json'
            if config.exists(): shutil.copy2(config, cargo_home / config.relative_to(cache_source))
# The Mac supplied only necessary missing archives/index entries in the bundle.
supplement = source / 'native/cargo-supplement'
if supplement.exists(): shutil.copytree(supplement, cargo_home, dirs_exist_ok=True)
env = dict(os.environ, CARGO_HOME=str(cargo_home), RUSTC=str(rustc), CARGO_BUILD_JOBS='4')
if windows:
    vswhere = Path(os.environ['ProgramFiles(x86)']) / 'Microsoft Visual Studio/Installer/vswhere.exe'
    installation = subprocess.check_output([str(vswhere), '-latest', '-property', 'installationPath'], text=True).strip()
    vcvars = Path(installation) / 'VC/Auxiliary/Build/vcvars64.bat'
    capture = cargo_home.parent / 'capture-msvc-env.cmd'
    capture.write_text(f'@call "{vcvars}" >nul\n@set\n', encoding='utf-8')
    output = subprocess.check_output(['cmd.exe', '/d', '/c', str(capture)], text=True)
    for line in output.splitlines():
        if '=' in line:
            key, value = line.split('=', 1)
            env[key] = value
    env.update(CARGO_HOME=str(cargo_home), RUSTC=str(rustc), CARGO_BUILD_JOBS='4')
else:
    env['PATH'] = str(rustc.parent) + os.pathsep + env['PATH']
log = source / ('build-windows.txt' if windows else 'build-linux.txt')
with log.open('w', encoding='utf-8') as output:
    output.write(subprocess.check_output([str(rustc), '--version'], text=True)); output.flush()
    subprocess.run([str(cargo), 'build', '--offline', '--locked', '--manifest-path',
        'native/rust/headless/Cargo.toml'], cwd=source, env=env,
        stdout=output, stderr=subprocess.STDOUT, check=True)
    library = 'nipaplay_headless_native.dll' if windows else 'libnipaplay_headless_native.so'
    shutil.copy2(source / 'native/rust/headless/target/debug' / library, binary / library)
    subprocess.run([str(dart), 'compile', 'exe', '--packages=.dart_tool/package_config.json',
        'bin/nipaplay_headless.dart', '-o', str(binary / ('nipaplay-headless.exe' if windows else 'nipaplay-headless'))],
        cwd=source, env=env, stdout=output, stderr=subprocess.STDOUT, check=True)
print(json.dumps({'compiledOnly': True, 'platform': 'windows-x64' if windows else 'linux-x64',
    'binaryDirectory': str(binary), 'log': str(log),
    'artifacts': [{'name': f.name, 'bytes': f.stat().st_size,
        'sha256': hashlib.file_digest(f.open('rb'), 'sha256').hexdigest()}
        for f in sorted(binary.iterdir()) if f.is_file()]}), flush=True)
