import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared pubspec does not force platform-specific dependency forks', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, isNot(contains('gitcode.com/openharmony')));
    expect(pubspec, isNot(contains('gitee.com/openharmony')));
    expect(pubspec, isNot(contains('path: packages/fvp-0.37.3')));
    expect(pubspec, isNot(contains('path: packages/fluent_ui-4.15.1')));
    expect(pubspec, contains('fvp: ^0.33.1'));
    expect(File('.fvmrc').readAsStringSync(), contains('3.44.6'));
    expect(File('pubspec_overrides.ohos.yaml').existsSync(), isTrue);
    expect(File('pubspec_overrides.linux.yaml').existsSync(), isTrue);
    expect(File('pubspec_overrides.tvos.yaml').existsSync(), isTrue);
    expect(pubspec, contains('package_info_plus: ^10.2.1'));
    expect(pubspec, contains('wakelock_plus: ^1.7.0'));
    expect(pubspec, contains('ref: v0.1.4'));
    expect(
      pubspec,
      isNot(contains('ref: 29f47da8e64ae9caacfd7317c2a6ad9d2d609e9b')),
    );
    expect(
      File('.flutter-version-linux').readAsStringSync().trim(),
      '3.47.0-0.3.pre',
    );
  });

  test('HarmonyOS mode retains every shared dependency override', () {
    final sharedKeys = _dependencyOverrideKeys(
      File('pubspec.yaml').readAsStringSync(),
    );
    final harmonyKeys = _dependencyOverrideKeys(
      File('pubspec_overrides.ohos.yaml').readAsStringSync(),
    );

    expect(harmonyKeys, containsAll(sharedKeys));
    final harmonyOverrides =
        File('pubspec_overrides.ohos.yaml').readAsStringSync();
    expect(
      harmonyOverrides,
      contains('package_info_plus_platform_interface: 3.2.1'),
      reason: 'tvOS native registrants must not raise the HarmonyOS 3.35 '
          'Dart/Flutter floor.',
    );
    expect(
      harmonyOverrides,
      contains('wakelock_plus_platform_interface: 1.3.0'),
      reason: 'tvOS native registrants must not raise the HarmonyOS 3.35 '
          'Dart/Flutter floor.',
    );
  });

  test('Linux mode retains every shared dependency override', () {
    final sharedKeys = _dependencyOverrideKeys(
      File('pubspec.yaml').readAsStringSync(),
    );
    final linuxKeys = _dependencyOverrideKeys(
      File('pubspec_overrides.linux.yaml').readAsStringSync(),
    );

    expect(linuxKeys, containsAll(sharedKeys));
    expect(linuxKeys, containsAll(['desktop_multi_window', 'fvp']));
  });

  test('tvOS mode isolates only its SDK-specific Erika revision', () {
    final sharedKeys = _dependencyOverrideKeys(
      File('pubspec.yaml').readAsStringSync(),
    );
    final tvOSOverrides = File(
      'pubspec_overrides.tvos.yaml',
    ).readAsStringSync();
    final tvOSKeys = _dependencyOverrideKeys(tvOSOverrides);
    final wrapper = File('tool/flutter_tvos.sh').readAsStringSync();
    final workflow = File(
      '.github/workflows/build-tvos.yml',
    ).readAsStringSync();

    expect(tvOSKeys, containsAll(sharedKeys));
    expect(tvOSOverrides, isNot(contains('package_info_plus:')));
    expect(tvOSOverrides, isNot(contains('wakelock_plus:')));
    expect(
      tvOSOverrides,
      contains('ref: 29f47da8e64ae9caacfd7317c2a6ad9d2d609e9b'),
    );
    expect(wrapper, contains('configure_flutter_dependencies.dart" tvos'));
    expect(workflow, contains('configure_flutter_dependencies.dart tvos'));
  });

  test('desktop multi-window downgrade is isolated to HarmonyOS mode', () {
    final sharedPubspec = File('pubspec.yaml').readAsStringSync();
    final harmonyOverrides =
        File('pubspec_overrides.ohos.yaml').readAsStringSync();
    final mainlineFacade = File(
      'packages/desktop_multi_window/lib/desktop_multi_window.dart',
    ).readAsStringSync();
    final harmonyFacade = File(
      'packages/desktop_multi_window_ohos/lib/desktop_multi_window.dart',
    ).readAsStringSync();
    final linuxFacade = File(
      'packages/desktop_multi_window_linux_347/lib/desktop_multi_window.dart',
    ).readAsStringSync();

    expect(sharedPubspec, contains('path: packages/desktop_multi_window'));
    expect(
      harmonyOverrides,
      contains('path: packages/desktop_multi_window_ohos'),
    );
    expect(mainlineFacade, contains('nipaplay/desktop_multi_window_host'));
    expect(mainlineFacade, contains('preferredConstraints:'));
    expect(harmonyFacade, contains('static bool get isSupported => false'));
    expect(linuxFacade, contains('constraints:'));
    expect(linuxFacade, isNot(contains('preferredConstraints:')));
  });

  test('Linux build selects its dedicated Flutter and dependency profile', () {
    final workflow =
        File('.github/workflows/build-linux.yml').readAsStringSync();
    final containerRunner = File('containerbuild/run.sh').readAsStringSync();

    expect(workflow, contains('.flutter-version-linux'));
    expect(workflow, contains('dependency-profile: linux'));
    expect(containerRunner, contains('.flutter-version-linux'));
    expect(containerRunner, contains('--build-arg'));
  });

  test('isolated media_kit EGL keeps Linux ARM64 and scaling safeguards', () {
    final source = File('packages/media_kit_video/linux/video_output.cc')
        .readAsStringSync();

    expect(source, contains('H/W rendering with isolated EGL context'));
    expect(source, contains('video_output_should_force_sw_rendering'));
    expect(source, contains('NIPAPLAY_ENABLE_LINUX_ARM64_MPV_GL'));
    expect(source, contains('video_output_scale_sw_dimension'));
    expect(source, isNot(contains('return width / height *')));
    expect(source, isNot(contains('return height / width *')));
  });

  test('HarmonyOS project does not commit local signing material', () {
    final buildProfile = File('ohos/build-profile.json5').readAsStringSync();
    const forbiddenSigningFields = <String>[
      '"signingConfigs"',
      '"signingConfig"',
      '"certpath"',
      '"keyAlias"',
      '"keyPassword"',
      '"storeFile"',
      '"storePassword"',
    ];
    const forbiddenLocalPaths = <String>[
      '/Users/',
      '/home/',
      '.ohos/config',
      r':\Users\',
    ];

    for (final field in forbiddenSigningFields) {
      expect(
        buildProfile,
        isNot(contains(field)),
        reason: '$field belongs in a developer-local signing configuration.',
      );
    }
    for (final path in forbiddenLocalPaths) {
      expect(
        buildProfile,
        isNot(contains(path)),
        reason: 'HarmonyOS build configuration must not contain $path.',
      );
    }
  });

  test('HarmonyOS CI builds and signs without committed credentials', () {
    final workflow =
        File('.github/workflows/build-ohos.yml').readAsStringSync();

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('workflow_call:'));
    expect(workflow, contains('--no-codesign'));
    expect(workflow, contains('hap-sign-tool.jar'));
    expect(workflow, contains('verify-app'));
    expect(workflow, contains('release-HarmonyOS-signed'));
    expect(workflow, contains('OHOS_FLUTTER_BASE_TAG: 3.35.8-ohos-1.0.1'));
    expect(
      workflow,
      contains(
        r'+refs/tags/$OHOS_FLUTTER_BASE_TAG:refs/tags/$OHOS_FLUTTER_BASE_TAG',
      ),
    );
    expect(workflow, contains('merge-base --is-ancestor'));
    expect(
      workflow,
      matches(RegExp(r'apt-get install -y[\s\S]*?\bpython3\b')),
      reason: 'The HarmonyOS dependency setup generates build metadata with Python.',
    );
    expect(
      workflow,
      isNot(contains(r'fetch --depth=1 origin "$OHOS_FLUTTER_COMMIT"')),
    );
    expect(workflow, contains(r'-keyPwd "$SIGNING_KEY_PASSWORD"'));
    expect(workflow, contains(r'-keystorePwd "$SIGNING_KEYSTORE_PASSWORD"'));
    expect(workflow, isNot(contains('-pwdInputMode')));
    expect(workflow, contains('set +x'));
    expect(workflow, isNot(contains("printf '%s\\n%s\\n'")));
    expect(workflow, contains(r'${{ secrets.OHOS_SIGNING_CERT_BASE64 }}'));
    expect(workflow, contains(r'${{ secrets.OHOS_SIGNING_PROFILE_BASE64 }}'));
    expect(workflow, contains(r'${{ secrets.OHOS_SIGNING_KEYSTORE_BASE64 }}'));
    expect(
      workflow,
      matches(
        RegExp(
          r'container:\s+image:\s+\S+@sha256:[0-9a-f]{64}',
          multiLine: true,
        ),
      ),
    );
    expect(workflow, isNot(contains('/Users/')));
    expect(workflow, isNot(contains('.ohos/config')));
  });

  test('release CI publishes HarmonyOS and Apple TV sideload packages', () {
    final releaseWorkflow =
        File('.github/workflows/main.yml').readAsStringSync();
    final tvOSWorkflow =
        File('.github/workflows/build-tvos.yml').readAsStringSync();

    expect(
        releaseWorkflow, contains('uses: ./.github/workflows/build-ohos.yml'));
    expect(
        releaseWorkflow, contains('uses: ./.github/workflows/build-tvos.yml'));
    expect(releaseWorkflow, contains('sign_hap: true'));
    expect(releaseWorkflow, contains('Build-HarmonyOS'));
    expect(releaseWorkflow, contains('Build-tvOS'));
    expect(
      releaseWorkflow,
      contains('/tmp/artifacts/release-HarmonyOS-signed/*.hap'),
    );
    expect(
      releaseWorkflow,
      contains('/tmp/artifacts/release-tvOS-sideload/*.ipa'),
    );

    expect(tvOSWorkflow, contains("github.event_name == 'pull_request'"));
    expect(tvOSWorkflow, contains('CODE_SIGNING_ALLOWED = NO'));
    expect(tvOSWorkflow, contains('build tvos --release --no-pub'));
    expect(tvOSWorkflow, contains('build/tvos/Release-appletvos'));
    expect(tvOSWorkflow, contains("grep -q 'platform TVOS'"));
    expect(tvOSWorkflow, contains('release-tvOS-sideload'));
    expect(tvOSWorkflow, contains('tvOS-arm64-sideload.ipa'));
  });

  test('application source does not require custom Platform APIs', () {
    final incompatibleFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => file.readAsStringSync().contains('Platform.isOhos'))
        .map((file) => file.path)
        .toList();

    expect(
      incompatibleFiles,
      isEmpty,
      reason: 'Platform.isOhos is unavailable in upstream Dart.',
    );
  });
}

Set<String> _dependencyOverrideKeys(String yaml) {
  final keys = <String>{};
  var insideOverrides = false;

  for (final line in yaml.split('\n')) {
    if (line == 'dependency_overrides:') {
      insideOverrides = true;
      continue;
    }
    if (!insideOverrides) {
      continue;
    }
    if (line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      break;
    }
    final match = RegExp(r'^  ([a-zA-Z0-9_]+):$').firstMatch(line);
    if (match != null) {
      keys.add(match.group(1)!);
    }
  }

  return keys;
}
