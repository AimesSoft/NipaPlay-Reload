#!/usr/bin/env python3
"""Embed vendor tvOS privacy manifests for both SPM and CocoaPods builds."""

import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess


def embed_manifests(app, plugins_file):
    plugins = json.loads(plugins_file.read_text())['plugins'].get('tvos', [])
    copied = []
    for plugin in plugins:
        name = plugin['name']
        source = Path(plugin['path']) / 'tvos/Resources/PrivacyInfo.xcprivacy'
        if not source.is_file():
            if name == 'sqflite_tvos':
                raise RuntimeError('sqflite_tvos vendor privacy manifest is missing')
            continue
        # Fail before packaging a malformed vendor declaration.
        with source.open('rb') as stream:
            plistlib.load(stream)
        framework = app / 'Frameworks' / f'{name}.framework'
        if framework.is_dir():
            destination = framework
        else:
            # Statically linked plugins (e.g. shared_preferences_tvos) do not
            # have a framework. Keep each vendor declaration in its own bundle.
            destination = app / f'{name}_privacy.bundle'
            destination.mkdir(parents=True, exist_ok=True)
            with (destination / 'Info.plist').open('wb') as stream:
                plistlib.dump({
                    'CFBundleIdentifier': f'com.nipaplay.privacy.{name.replace("_", "-")}',
                    'CFBundleName': f'{name}_privacy',
                    'CFBundlePackageType': 'BNDL',
                    'CFBundleVersion': '1',
                    'CFBundleShortVersionString': '1.0',
                }, stream)
        shutil.copyfile(source, destination / 'PrivacyInfo.xcprivacy')
        identity = os.environ.get('EXPANDED_CODE_SIGN_IDENTITY', '')
        if framework.is_dir() and identity and os.environ.get('CODE_SIGNING_ALLOWED') != 'NO':
            subprocess.run(['codesign', '--force', '--sign', identity,
                            '--timestamp=none', str(framework)], check=True)
        copied.append(name)
    return copied


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--plugins', type=Path, required=True)
    args = parser.parse_args()
    if not args.app.is_dir():
        parser.error('built app directory is missing')
    print('Embedded tvOS vendor privacy manifests: ' + ', '.join(
        embed_manifests(args.app, args.plugins)))
