#!/usr/bin/env python3
"""Hash the top-level distributables from downloaded release-* artifacts."""
import argparse
import hashlib
import json
from pathlib import Path


def collect(root):
    files = []
    suffixes = ('.apk', '.ipa', '.dmg', '.zip', '.pkg', '.exe', '.msix',
                '.deb', '.AppImage', '.tar.gz', '.rpm', '.hap')
    for artifact in sorted(root.glob('release-*')):
        if not artifact.is_dir() or artifact.is_symlink():
            continue
        for path in sorted(artifact.iterdir()):
            if path.is_symlink() or not path.is_file() or not path.name.endswith(suffixes):
                continue
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            files.append({'path': path.relative_to(root).as_posix(),
                          'bytes': path.stat().st_size, 'sha256': digest.hexdigest()})
    if not files:
        raise ValueError('No distributable packages found')
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifacts', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--version', required=True)
    args = parser.parse_args()
    files = collect(args.artifacts)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'release-manifest.json').write_text(json.dumps({
        'version': args.version, 'revision': args.revision, 'files': files,
    }, indent=2) + '\n', encoding='utf-8')
    (args.output / 'SHA256SUMS').write_text(''.join(
        f"{f['sha256']}  {f['path']}\n" for f in files), encoding='utf-8')
    print(f'Verified {len(files)} distributable packages')


if __name__ == '__main__':
    main()
