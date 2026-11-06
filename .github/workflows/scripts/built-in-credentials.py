#!/usr/bin/env python3
"""Prepare and verify built-in credentials without logging their contents."""
import argparse
import base64
import json
import mmap
import os
from pathlib import Path
import sys
import urllib.error
import urllib.parse
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['check', 'prepare', 'verify'])
    parser.add_argument('path', nargs='?')
    args = parser.parse_args()
    token = os.environ.get('NIPAPLAY_TMDB_TOKEN', '').strip()
    official_next = (os.environ.get('GITHUB_REPOSITORY') == 'AimesSoft/NipaPlay-Reload'
                     and os.environ.get('GITHUB_REF_NAME') == 'next')
    if not token and (official_next or args.mode == 'check'):
        sys.exit('Missing NIPAPLAY_TMDB_TOKEN: configure the repository Actions secret before releasing Next.')
    if os.environ.get('GITHUB_ACTIONS') == 'true' and token:
        # Flutter verbose output may include base64-encoded Dart defines.
        encoded = base64.b64encode(f'NIPAPLAY_TMDB_TOKEN={token}'.encode()).decode()
        print(f'::add-mask::{encoded}', flush=True)
    if args.mode == 'check':
        url = 'https://api.themoviedb.org/3/authentication'
        headers = {}
        if '.' in token:
            headers['Authorization'] = f'Bearer {token}'
        else:
            url += '?' + urllib.parse.urlencode({'api_key': token})
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as response:
                if not json.load(response).get('success'):
                    sys.exit('TMDB rejected the built-in credential.')
        except urllib.error.HTTPError as error:
            sys.exit(f'TMDB credential validation failed: HTTP {error.code}.')
        except (urllib.error.URLError, TimeoutError):
            sys.exit('Could not reach TMDB to validate the built-in credential.')
        print('Built-in TMDB credential authenticated successfully.')
    elif args.mode == 'prepare':
        if not args.path:
            parser.error('prepare requires an output path')
        path = Path(args.path)
        path.write_text(json.dumps({'NIPAPLAY_TMDB_TOKEN': token} if token else {}), encoding='utf-8')
        path.chmod(0o600)
        print('Prepared Dart defines (TMDB configured).' if token else 'Diagnostic build without built-in TMDB.')
    elif token:
        if not args.path:
            parser.error('verify requires the compiled Dart binary path')
        with Path(args.path).open('rb') as binary, mmap.mmap(binary.fileno(), 0, access=mmap.ACCESS_READ) as data:
            if data.find(token.encode()) == -1:
                sys.exit('Compiled artifact is missing the configured TMDB credential; refusing to package it.')
        print('Verified built-in TMDB credential in compiled artifact.')
    else:
        print('Diagnostic build: no built-in TMDB credential to verify.')


if __name__ == '__main__':
    main()
