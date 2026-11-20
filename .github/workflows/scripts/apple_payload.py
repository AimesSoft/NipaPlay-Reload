#!/usr/bin/env python3
"""Derive a macOS app slice or an unsigned iOS IPA without rebuilding."""

import argparse
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile


THIN_MAGICS = {bytes.fromhex(value) for value in
               ('feedface', 'cefaedfe', 'feedfacf', 'cffaedfe')}
FAT_MAGICS = {bytes.fromhex(value) for value in
              ('cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def machos(app):
    for path in app.rglob('*'):
        if path.is_symlink() or not path.is_file():
            continue
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic in THIN_MAGICS or (
            magic in FAT_MAGICS and run('file', '-b', path, capture_output=True,
                                       text=True).stdout.startswith('Mach-O')
        ):
            yield path


def architectures(path):
    return run('lipo', '-archs', path, capture_output=True, text=True).stdout.split()


def thin(path, arch):
    archs = architectures(path)
    if archs == [arch]:
        return
    if arch not in archs:
        raise ValueError(f'{path}: missing {arch} slice (found {archs})')
    with tempfile.TemporaryDirectory(dir=path.parent) as temp:
        output = Path(temp) / path.name
        run('lipo', path, '-thin', arch, '-output', output)
        if architectures(output) != [arch]:
            raise ValueError(f'{path}: lipo did not produce exactly {arch}')
        output.chmod(stat.S_IMODE(path.stat().st_mode))
        output.replace(path)


def derive_macos(source, destination, arch):
    if destination.exists() or destination.is_symlink():
        raise ValueError(f'destination already exists: {destination}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        staged = Path(temp) / destination.name
        run('ditto', source, staged)
        binaries = list(machos(staged))
        if not binaries:
            raise ValueError(f'{source}: no Mach-O binaries')
        for path in binaries:
            thin(path, arch)
        staged.rename(destination)
    print(f'{destination.name}: {len(binaries)} Mach-O files, all {arch}')


def remove_signature(path):
    result = subprocess.run(('codesign', '--display', path), capture_output=True, text=True)
    if result.returncode == 0:
        run('codesign', '--remove-signature', path)
    elif 'code object is not signed at all' not in result.stderr:
        result.check_returncode()


def unsigned_ios(source, config, destination):
    settings = dict(line.split('=', 1) for line in config.read_text().splitlines() if '=' in line)
    version = settings['FLUTTER_BUILD_NAME']
    build = settings['FLUTTER_BUILD_NUMBER']
    if not version or not build:
        raise ValueError('missing Flutter side-load version or build number')
    destination = destination.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        root = Path(temp)
        app = root / 'Payload' / source.name
        run('ditto', source, app)
        plist = app / 'Info.plist'
        contents = plistlib.loads(plist.read_bytes())
        if contents['CFBundleIdentifier'] != 'com.aimessoft.nipaplay':
            raise ValueError('unexpected iOS release bundle ID')
        contents.update(CFBundleShortVersionString=version, CFBundleVersion=build)
        plist.write_bytes(plistlib.dumps(contents, fmt=plistlib.FMT_BINARY))
        binaries = list(machos(app))
        if app / contents['CFBundleExecutable'] not in binaries:
            raise ValueError('missing iOS main executable')
        for path in binaries:
            remove_signature(path)
            thin(path, 'arm64')
            run('xcrun', '--sdk', 'iphoneos', 'bitcode_strip', path, '-r', '-o', path)
            run('strip', '-S', '-x', path, '-o', path)
            remove_signature(path)
        for directory, subdirs, files in os.walk(app):
            for name in set(subdirs) & {'_CodeSignature'}:
                path = Path(directory) / name
                if path.is_symlink():
                    path.unlink()
                else:
                    shutil.rmtree(path)
                subdirs.remove(name)
            for name in set(files) & {'embedded.mobileprovision', 'embedded.provisionprofile', 'CodeResources'}:
                (Path(directory) / name).unlink()
        archive = root / destination.name
        run('zip', '-q', '-9', '-y', '-r', archive, 'Payload', cwd=root)
        archive.replace(destination)
    print(f'{destination.name}: unsigned Payload, bundle {contents["CFBundleIdentifier"]}, {version} ({build})')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest='command', required=True)
    macos = subcommands.add_parser('macos')
    macos.add_argument('source', type=Path)
    macos.add_argument('destination', type=Path)
    macos.add_argument('architecture', choices=('arm64', 'x86_64'))
    ios = subcommands.add_parser('ios')
    ios.add_argument('source', type=Path)
    ios.add_argument('config', type=Path)
    ios.add_argument('destination', type=Path)
    arguments = parser.parse_args()
    if arguments.command == 'macos':
        derive_macos(arguments.source, arguments.destination, arguments.architecture)
    else:
        unsigned_ios(arguments.source, arguments.config, arguments.destination)
