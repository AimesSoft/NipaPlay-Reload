#!/usr/bin/env python3
"""Package the resolved pure Dart import graph without pub get or host secrets."""
import argparse
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
config_file = root / '.dart_tool/package_config.json'
config = json.loads(config_file.read_text())
packages = {}
for package in config['packages']:
    uri = urlparse(package['rootUri'])
    directory = Path(unquote(uri.path)) if uri.scheme == 'file' else config_file.parent / unquote(package['rootUri'])
    packages[package['name']] = (directory.resolve(), package)

visited, names, parents = set(), set(), {}
queue = [root / 'bin/nipaplay_headless.dart']
forbidden = []
while queue:
    file = queue.pop()
    if file in visited:
        continue
    visited.add(file)
    source = file.read_text()
    # Match directives only, not documentation examples or strings in code.
    for directive in re.finditer(r'^\s*(?:import|export|part)\s+(?!of\b)([^;]+);', source, re.M):
        text = directive.group(1)
        first = re.match(r"['\"]([^'\"]+)['\"]", text)
        if not first:
            continue
        uri = first.group(1)
        tail = text[first.end():]
        while re.match(r"\s*['\"]", tail):
            adjacent = re.match(r"\s*['\"]([^'\"]*)['\"]", tail)
            uri += adjacent.group(1)
            tail = tail[adjacent.end():]
        for condition, choice in re.findall(r"if\s*\(dart\.library\.(\w+)(?:\s*==\s*['\"]true['\"])?\)\s*['\"]([^'\"]+)['\"]", text):
            if condition in {'io', 'ffi', 'isolate'}:
                uri = choice
        if uri == 'dart:ui' or uri.startswith('package:flutter/'):
            chain = [f'{file}: {uri}']
            parent = file
            while parent in parents and len(chain) < 25:
                parent = parents[parent]
                chain.append(str(parent))
            raise SystemExit('\n'.join(reversed(chain)))
        if uri.startswith('dart:'):
            if uri == 'dart:ui': forbidden.append(file)
            continue
        if uri.startswith('package:'):
            if '/' not in uri[8:]:
                raise ValueError(f'Invalid package import {uri} in {file}')
            name, relative = uri[8:].split('/', 1)
            names.add(name)
            base, pkg = packages[name]
            target = base / pkg.get('packageUri', 'lib/') / relative
        else:
            target = file.parent / uri
        target = target.resolve()
        parents.setdefault(target, file)
        queue.append(target)

print(json.dumps({'libraries': len(visited), 'packages': sorted(names),
                  'dart_ui_files': [str(f) for f in forbidden]}, indent=2))
if forbidden:
    for file in forbidden[:3]:
        chain = [str(file)]
        while file in parents and len(chain) < 25:
            file = parents[file]
            chain.append(str(file))
        print('\n'.join(reversed(chain)))
    raise SystemExit('The headless graph still imports dart:ui')
if not args.output:
    raise SystemExit(0)
relocated = []
with zipfile.ZipFile(args.output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for name in sorted(names):
        directory, pkg = packages[name]
        new = dict(pkg)
        new['rootUri'] = '..' if name == 'nipaplay' else '../vendor/' + name
        relocated.append(new)
        if name == 'nipaplay':
            # Copy source files in the active graph, without any runtime config.
            for file in sorted(visited):
                if file.is_relative_to(root / 'lib') or file == root / 'bin/nipaplay_headless.dart':
                    archive.write(file, file.relative_to(root))
            continue
        for file in directory.rglob('*'):
            if file.is_file() and file.is_relative_to(directory / 'lib'):
                archive.write(file, Path('vendor') / name / file.relative_to(directory))
        for extra in ['pubspec.yaml', 'LICENSE']:
            if (directory / extra).is_file():
                archive.write(directory / extra, Path('vendor') / name / extra)
    seed = root / 'assets/next/harness'
    for file in seed.rglob('*'):
        if file.is_file() and '.codex' not in file.relative_to(seed).parts:
            archive.write(file, file.relative_to(root))
    # The runtime Nipa runs on: the DSH manifest and NipaPlay's plugins, read
    # through --agent-assets (default assets/next/agent).
    agent = root / 'assets/next/agent'
    for file in agent.rglob('*'):
        if file.is_file():
            archive.write(file, file.relative_to(root))
    archive.writestr('.dart_tool/package_config.json', json.dumps({
        'configVersion': 2, 'packages': relocated}, indent=2))
print(f'Wrote {args.output} ({args.output.stat().st_size} bytes)')
