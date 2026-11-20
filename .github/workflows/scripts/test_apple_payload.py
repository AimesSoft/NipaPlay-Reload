import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

from apple_payload import architectures, derive_macos, machos, run, unsigned_ios


@unittest.skipUnless(sys.platform == 'darwin', 'requires Apple tools')
class ApplePayloadTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)

    def test_derive_and_resign_macos_bundle(self):
        developer = run('xcode-select', '-p', capture_output=True, text=True).stdout.strip()
        binary = Path(os.environ.get('MACOS_UNIVERSAL_TEST_BINARY',
                                     str(Path(developer) / 'usr/bin/filtercalltree')))
        self.assertTrue({'arm64', 'x86_64'} <= set(architectures(binary)))
        source = self.root / 'Universal.app'
        info = {'CFBundleIdentifier': 'test.example.payload', 'CFBundleExecutable': 'Test'}
        main = source / 'Contents/MacOS/Test'
        helper = source / 'Contents/Helpers/Probe With Spaces'
        framework = source / 'Contents/Frameworks/Test.framework'
        framework_binary = framework / 'Versions/A/Test'
        resources = source / 'Contents/Resources'
        for path in (main, helper):
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(binary, path)
        (source / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        framework_resources = framework_binary.parent / 'Resources'
        framework_resources.mkdir(parents=True)
        (framework_resources / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': 'test.example.framework', 'CFBundleExecutable': 'Test',
            'CFBundlePackageType': 'FMWK',
        }))
        code = self.root / 'framework.c'
        code.write_text('int framework_fixture(void) { return 0; }\n')
        run('xcrun', '--sdk', 'macosx', 'clang', '-dynamiclib', '-arch', 'arm64', '-arch', 'x86_64',
            code, '-o', framework_binary)
        (framework / 'Versions/Current').symlink_to('A')
        (framework / 'Test').symlink_to('Versions/Current/Test')
        (framework / 'Resources').symlink_to('Versions/Current/Resources')
        resources.mkdir()
        resource = b'\xca\xfe\xba\xbe\x00\x00\x00\x3d' + bytes(24)
        (resources / 'not-macho.class').write_bytes(resource)

        for arch in ('arm64', 'x86_64'):
            destination = self.root / arch / 'Test.app'
            derive_macos(source, destination, arch)
            binaries = list(machos(destination))
            self.assertEqual(3, len(binaries))
            for path in binaries:
                self.assertEqual([arch], architectures(path))
            self.assertTrue(os.access(destination / helper.relative_to(source), os.X_OK))
            self.assertTrue((destination / framework.relative_to(source) / 'Test').is_symlink())
            self.assertEqual(resource, (destination / resources.relative_to(source) / 'not-macho.class').read_bytes())
            run('codesign', '--force', '--sign', '-', destination / helper.relative_to(source))
            run('codesign', '--force', '--sign', '-', destination / framework.relative_to(source))
            run('codesign', '--force', '--sign', '-', destination)
            run('codesign', '--verify', '--deep', '--strict', '--verbose=2', destination)

        self.assertTrue({'arm64', 'x86_64'} <= set(architectures(main)))
        bad = self.root / 'invalid' / 'Test.app'
        with self.assertRaisesRegex(ValueError, 'missing x86_64 slice'):
            derive_macos(self.root / 'arm64' / 'Test.app', bad, 'x86_64')
        self.assertFalse(bad.exists())

    def test_unsigned_ios_copy_preserves_source_and_restores_version(self):
        source = self.root / 'archive/Products/Applications/Runner.app'
        source.mkdir(parents=True)
        code = self.root / 'main.c'
        code.write_text('int main(void) { return 0; }\n')
        run('xcrun', '--sdk', 'iphoneos', 'clang', '-target', 'arm64-apple-ios15.0', code, '-o', source / 'Runner')
        settings = dict(CFBundleIdentifier='com.aimessoft.nipaplay', CFBundleExecutable='Runner',
                        CFBundleShortVersionString='1.2.3', CFBundleVersion='100.1')
        (source / 'Info.plist').write_bytes(plistlib.dumps(settings))
        (source / 'embedded.mobileprovision').write_bytes(b'fixture')
        (source / 'test-asset').write_bytes(b'original app asset')
        run('codesign', '--force', '--sign', '-', source)
        config = self.root / 'Generated.xcconfig'
        config.write_text('FLUTTER_BUILD_NAME=1.2.4\nFLUTTER_BUILD_NUMBER=2\n')
        ipa = self.root / 'out/derived.ipa'
        unsigned_ios(source, config, ipa)
        run('codesign', '--verify', '--deep', '--strict', source)
        self.assertEqual(settings, plistlib.loads((source / 'Info.plist').read_bytes()))
        prefix = 'Payload/Runner.app/'
        with zipfile.ZipFile(ipa) as archive:
            self.assertFalse(any('_CodeSignature' in name or name.endswith('mobileprovision')
                                 for name in archive.namelist()))
            derived_info = plistlib.loads(archive.read(prefix + 'Info.plist'))
            self.assertEqual('1.2.4', derived_info['CFBundleShortVersionString'])
            self.assertEqual('2', derived_info['CFBundleVersion'])
            self.assertEqual(settings['CFBundleIdentifier'], derived_info['CFBundleIdentifier'])
            self.assertEqual(b'original app asset', archive.read(prefix + 'test-asset'))
            runner = self.root / 'derived-runner'
            runner.write_bytes(archive.read(prefix + 'Runner'))
            self.assertEqual(['arm64'], architectures(runner))
            result = subprocess.run(('codesign', '--display', runner), capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertIn('code object is not signed at all', result.stderr)
