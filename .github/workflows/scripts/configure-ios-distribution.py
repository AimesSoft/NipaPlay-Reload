#!/usr/bin/env python3
"""Use an installed App Store profile and distribution identity for Runner."""
import datetime
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys


def configure(project, export_options, team, platform='ios'):
    if platform not in ('ios', 'tvos'):
        raise ValueError('platform must be ios or tvos')
    profile_platform = 'tvOS' if platform == 'tvos' else 'iOS'
    sdk = 'appletvos' if platform == 'tvos' else 'iphoneos'
    bundle = 'com.aimessoft.nipaplay'
    identities = subprocess.check_output(
        ['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    available = set(re.findall(r'([A-Fa-f0-9]{40}) "(?:Apple|iPhone) Distribution:', identities))
    available = {value.upper() for value in available}
    candidates = []
    for path in [Path(os.environ[f'{platform.upper()}_DISTRIBUTION_PROFILE'])]:
        profile = plistlib.loads(subprocess.check_output(['security', 'cms', '-D', '-i', str(path)]))
        entitlements = profile.get('Entitlements', {})
        certificates = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get('DeveloperCertificates', [])}
        matching = sorted(certificates & available)
        if (profile.get('TeamIdentifier') == [team]
                and profile_platform in profile.get('Platform', [])
                and entitlements.get('application-identifier') == f'{team}.{bundle}'
                and not entitlements.get('get-task-allow')
                and not profile.get('ProvisionedDevices')
                and not profile.get('ProvisionsAllDevices')
                and profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
                and matching):
            candidates.append((profile['ExpirationDate'], profile['UUID'], matching[0], path))
    if not candidates:
        raise SystemExit('No valid App Store profile matches the imported distribution certificate and NipaPlay bundle ID.')
    _, uuid, identity, profile_path = max(candidates)
    # Xcode 16+ stores profiles here; retain the download action's legacy copy.
    profiles = Path.home() / 'Library/Developer/Xcode/UserData/Provisioning Profiles'
    profiles.mkdir(parents=True, exist_ok=True)
    shutil.copy2(profile_path, profiles / profile_path.name)
    data = plistlib.loads(subprocess.check_output(['plutil', '-convert', 'xml1', '-o', '-', str(project)]))
    objects = data['objects']
    runner = next(obj for obj in objects.values() if obj.get('isa') == 'PBXNativeTarget' and obj.get('name') == 'Runner')
    configs = objects[runner['buildConfigurationList']]['buildConfigurations']
    release = next(objects[key] for key in configs if objects[key]['name'] == 'Release')
    release['buildSettings'].update({
        'CODE_SIGN_STYLE': 'Manual',
        'CODE_SIGN_IDENTITY': identity,
        f'CODE_SIGN_IDENTITY[sdk={sdk}*]': identity,
        'DEVELOPMENT_TEAM': team,
        'PROVISIONING_PROFILE_SPECIFIER': uuid,
    })
    project.write_bytes(plistlib.dumps(data, sort_keys=False))
    export_options.write_bytes(plistlib.dumps({
        'method': 'app-store-connect', 'destination': 'export',
        'signingStyle': 'manual', 'teamID': team, 'signingCertificate': identity,
        'provisioningProfiles': {bundle: uuid},
        'manageAppVersionAndBuildNumber': False,
        'stripSwiftSymbols': True, 'uploadSymbols': True,
    }))
    print('Configured Runner Release with an existing App Store profile and distribution identity.')


if __name__ == '__main__':
    platform = sys.argv[1] if len(sys.argv) > 1 else 'ios'
    if platform not in ('ios', 'tvos') or len(sys.argv) > 2:
        raise SystemExit('usage: configure-ios-distribution.py [ios|tvos]')
    configure(Path(platform) / 'Runner.xcodeproj/project.pbxproj',
              Path(os.environ['RUNNER_TEMP']) / 'ExportOptions-AppStore.plist',
              os.environ['APPLE_TEAM_ID'], platform)
