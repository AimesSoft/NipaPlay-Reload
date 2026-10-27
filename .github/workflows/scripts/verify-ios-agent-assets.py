#!/usr/bin/env python3
"""Reject desktop Agent assets in an iOS app/IPA before upload or signing."""
import argparse
from pathlib import Path
import zipfile


def verify(path: Path) -> None:
    if path.is_dir():
        names = [p.relative_to(path).as_posix() for p in path.rglob('*') if p.is_file()]
    else:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
    if not any(name.endswith('/flutter_assets/AssetManifest.bin') for name in names):
        raise ValueError('No Flutter asset manifest found; expected an iOS app or IPA.')
    forbidden = [name for name in names if any(
        prefix in name for prefix in (
            '/flutter_assets/assets/next/harness/',
            '/flutter_assets/assets/next/agent/',
        )
    )]
    if forbidden:
        raise ValueError('iOS must not bundle local Agent seed/runtime assets:\n' + '\n'.join(forbidden))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    args = parser.parse_args()
    try:
        verify(args.bundle)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f'{error}\n')
    print('iOS asset check passed: no local Agent seed/runtime bundled.')


if __name__ == '__main__':
    main()
