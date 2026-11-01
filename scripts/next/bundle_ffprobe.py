#!/usr/bin/env python3
"""Bundle a pinned standalone ffprobe. Run before app signing/packaging.

macOS: --target darwin-arm64 --output APP/Contents/Resources/probe/arm64
Windows/Linux: --target win32-x64/linux-x64 --output BUNDLE/probe
Archives are pinned by SHA-256; only the executable and license notices are copied.
"""
import argparse
import hashlib
import io
import json
import pathlib
import tarfile
import zipfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]


def bundle(target, output):
    entry = json.loads((ROOT / 'scripts/next/ffprobe-packages.json').read_text())[target]
    cache = ROOT / 'build/probe-cache' / entry['cacheFile']
    cache.parent.mkdir(parents=True, exist_ok=True)
    if not cache.exists():
        request = urllib.request.Request(entry['url'], headers={'User-Agent': 'NipaPlay-build'})
        with urllib.request.urlopen(request, timeout=120) as response:
            cache.write_bytes(response.read())
    data = cache.read_bytes()
    if hashlib.sha256(data).hexdigest() != entry['sha256']:
        cache.unlink()
        raise ValueError('ffprobe archive integrity mismatch')
    binary = 'ffprobe.exe' if target.startswith('win32') else 'ffprobe'
    output.mkdir(parents=True, exist_ok=True)
    if cache.suffix == '.zip':
        archive = zipfile.ZipFile(io.BytesIO(data))
        names = archive.namelist()
        read = archive.read
    else:
        archive = tarfile.open(fileobj=io.BytesIO(data), mode='r:*')
        names = [m.name for m in archive.getmembers() if m.isfile()]
        read = lambda name: archive.extractfile(name).read()
    with archive:
        matches = [n for n in names if pathlib.PurePosixPath(n).name == binary and not n.startswith('__MACOSX/')]
        if len(matches) != 1:
            raise ValueError('Expected exactly one ffprobe executable')
        (output / binary).write_bytes(read(matches[0]))
        for name in names:
            base = pathlib.PurePosixPath(name).name
            if base.upper().startswith(('LICENSE', 'COPYING', 'README')) and not name.endswith('/'):
                (output / base).write_bytes(read(name))
    (output / binary).chmod(0o755)
    if target.startswith('darwin'):
        license_url = 'https://raw.githubusercontent.com/FFmpeg/FFmpeg/n8.0/COPYING.GPLv2'
        with urllib.request.urlopen(license_url, timeout=30) as response:
            (output / 'COPYING.GPLv2').write_bytes(response.read())
    (output / 'PROVENANCE.json').write_text(json.dumps(entry, indent=2) + '\n')
    (output / 'SOURCE.txt').write_text(
        'ffprobe is part of FFmpeg, distributed as a separate executable.\n'
        'Source: ' + entry['source'] + '\n'
        'Build recipes: ' + entry['buildRecipe'] + '\n'
        'Upstream license information: https://ffmpeg.org/legal.html\n')
    print('Bundled', target, 'at', output)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target', required=True)
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    bundle(args.target, args.output)
