"""使用合成描述文件验证两个 Apple 平台，不访问钥匙串或 Apple 服务。"""
import copy
import datetime
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'distribution', Path(__file__).with_name('configure-ios-distribution.py'))
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class DistributionConfigurationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.project = self.root / 'project.pbxproj'
        self.project.write_text('original project')
        self.export = self.root / 'ExportOptions.plist'
        self.profile_path = self.root / 'fixture.mobileprovision'
        self.profile_path.write_bytes(b'synthetic profile')
        self.fingerprint = hashlib.sha1(b'synthetic certificate').hexdigest().upper()
        self.profile = {
            'TeamIdentifier': ['FIXTURE'],
            'Platform': ['tvOS'],
            'Entitlements': {'application-identifier': 'FIXTURE.com.aimessoft.nipaplay'},
            'DeveloperCertificates': [b'synthetic certificate'],
            'ExpirationDate': datetime.datetime.now() + datetime.timedelta(days=7),
            'UUID': 'fixture-profile',
        }
        self.objects = {
            'target': {'isa': 'PBXNativeTarget', 'name': 'Runner',
                       'buildConfigurationList': 'configs'},
            'configs': {'buildConfigurations': ['debug', 'release', 'profile']},
            'debug': {'name': 'Debug', 'buildSettings': {'PRODUCT_BUNDLE_IDENTIFIER': 'debug'}},
            'release': {'name': 'Release', 'buildSettings': {
                'PRODUCT_BUNDLE_IDENTIFIER': 'com.aimessoft.nipaplay'}},
            'profile': {'name': 'Profile', 'buildSettings': {}},
        }

    def command(self, args, **kwargs):
        if args[:2] == ['security', 'find-identity']:
            return f'1) {self.fingerprint} "Apple Distribution: fixture"'
        if args[:2] == ['security', 'cms']:
            self.assertEqual(args[-1], str(self.profile_path))
            return plistlib.dumps(self.profile)
        if args[0] == 'plutil':
            return plistlib.dumps({'objects': copy.deepcopy(self.objects)})
        self.fail(f'Unexpected external command: {args}')

    def configure(self, platform):
        with patch.dict(os.environ, {
            'IOS_DISTRIBUTION_PROFILE': str(self.profile_path),
            'TVOS_DISTRIBUTION_PROFILE': str(self.profile_path),
        }), patch.object(distribution.Path, 'home', return_value=self.root), \
                patch.object(distribution.subprocess, 'check_output', side_effect=self.command):
            distribution.configure(self.project, self.export, 'FIXTURE', platform)

    def test_each_platform_signs_only_release_with_the_imported_identity(self):
        for platform, apple_platform, sdk in [('ios', 'iOS', 'iphoneos'),
                                               ('tvos', 'tvOS', 'appletvos')]:
            with self.subTest(platform=platform):
                self.profile['Platform'] = [apple_platform]
                self.configure(platform)
                objects = plistlib.loads(self.project.read_bytes())['objects']
                settings = objects['release']['buildSettings']
                self.assertEqual(settings['CODE_SIGN_STYLE'], 'Manual')
                self.assertEqual(settings[f'CODE_SIGN_IDENTITY[sdk={sdk}*]'], self.fingerprint)
                self.assertEqual(settings['PROVISIONING_PROFILE_SPECIFIER'], 'fixture-profile')
                self.assertEqual(objects['debug'], self.objects['debug'])
                self.assertEqual(objects['profile'], self.objects['profile'])
                options = plistlib.loads(self.export.read_bytes())
                self.assertEqual(options['method'], 'app-store-connect')
                self.assertFalse(options['manageAppVersionAndBuildNumber'])
                self.assertEqual(options['provisioningProfiles'], {
                    'com.aimessoft.nipaplay': 'fixture-profile'})
                installed = self.root / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
                self.assertEqual((installed / self.profile_path.name).read_bytes(), b'synthetic profile')

    def test_wrong_platform_is_rejected_before_project_or_export_is_written(self):
        self.profile['Platform'] = ['iOS']
        with self.assertRaisesRegex(SystemExit, 'No valid App Store profile'):
            self.configure('tvos')
        self.assertEqual(self.project.read_text(), 'original project')
        self.assertFalse(self.export.exists())

    def test_invalid_or_unrelated_profiles_cannot_be_used(self):
        original = copy.deepcopy(self.profile)
        invalid = [
            {'TeamIdentifier': ['OTHER']},
            {'DeveloperCertificates': [b'another certificate']},
            {'ExpirationDate': datetime.datetime.now() - datetime.timedelta(days=1)},
            {'ProvisionedDevices': ['fixture-device']},
            {'ProvisionsAllDevices': True},
            {'Entitlements': {'application-identifier': 'FIXTURE.com.aimessoft.nipaplay.tvos'}},
            {'Entitlements': {'application-identifier': 'FIXTURE.com.aimessoft.nipaplay',
                              'get-task-allow': True}},
        ]
        for change in invalid:
            with self.subTest(change=change):
                self.profile = {**original, **change}
                with self.assertRaisesRegex(SystemExit, 'No valid App Store profile'):
                    self.configure('tvos')
                self.assertEqual(self.project.read_text(), 'original project')
                self.assertFalse(self.export.exists())

    def test_unknown_platform_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'platform must be'):
            self.configure('unknown')


if __name__ == '__main__':
    unittest.main()
