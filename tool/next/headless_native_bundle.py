#!/usr/bin/env python3
"""Append portable native sources and offline build prerequisites to a Dart bundle."""
import argparse
import json
from pathlib import Path
import tomllib
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--bundle', type=Path, required=True)
parser.add_argument('--workstation-cache-list', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
lines = args.workstation_cache_list.read_text().splitlines()
cached = set(json.loads(next(line for line in lines if line.startswith('['))))
packages = tomllib.loads((root / 'rust/headless/Cargo.lock').read_text())['package']
registry = Path.home() / '.cargo/registry'
missing = []
with zipfile.ZipFile(args.bundle, 'a', zipfile.ZIP_DEFLATED) as archive:
    for pattern in ['rust/headless/Cargo.toml', 'rust/headless/Cargo.lock',
                    'rust/headless/src/*.rs', 'rust/mesh/Cargo.toml',
                    'rust/src/api/mesh.rs', 'rust/src/api/torrent.rs', 'rust/src/mesh_transport.rs',
                    'rust/third_party/librqbit-dualstack-sockets/**']:
        for file in root.glob(pattern):
            if file.is_file(): archive.write(file, Path('native') / file.relative_to(root))
    archive.write(root / 'tool/next/headless_workstation_build.py', 'build_workstation.py')
    for package in packages:
        if not package.get('source', '').startswith('registry+'):
            continue
        name, version = package['name'], package['version']
        filename = f'{name}-{version}.crate'
        if filename in cached: continue
        missing.append(filename)
        source = next((registry / 'cache').glob(f'*/{filename}'))
        archive.write(source, Path('native/cargo-supplement/registry') / source.relative_to(registry))
        suffix = f'1/{name}' if len(name) == 1 else f'2/{name}' if len(name) == 2 else f'3/{name[0]}/{name}' if len(name) == 3 else f'{name[:2]}/{name[2:4]}/{name}'
        entry = next((registry / 'index').glob(f'*/.cache/{suffix}'))
        entry_target = Path('native/cargo-supplement/registry') / entry.relative_to(registry)
        if str(entry_target) not in archive.namelist(): archive.write(entry, entry_target)
        config = entry.parents[len(Path(suffix).parts)] / 'config.json'
        target = Path('native/cargo-supplement/registry') / config.relative_to(registry)
        if str(target) not in archive.namelist(): archive.write(config, target)
print(json.dumps({'supplementCrates': len(missing), 'bundleBytes': args.bundle.stat().st_size, 'missing': missing}))
