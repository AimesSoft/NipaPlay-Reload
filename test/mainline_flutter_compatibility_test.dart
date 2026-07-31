import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared pubspec does not force HarmonyOS dependency forks', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, isNot(contains('gitcode.com/openharmony')));
    expect(pubspec, isNot(contains('gitee.com/openharmony')));
    expect(pubspec, isNot(contains('path: packages/fvp-0.37.3')));
    expect(pubspec, isNot(contains('path: packages/fluent_ui-4.15.1')));
    expect(pubspec, contains('fvp: ^0.33.1'));
    expect(File('.fvmrc').readAsStringSync(), contains('3.44.6'));
    expect(File('pubspec_overrides.ohos.yaml').existsSync(), isTrue);
  });

  test('HarmonyOS mode retains every shared dependency override', () {
    final sharedKeys = _dependencyOverrideKeys(
      File('pubspec.yaml').readAsStringSync(),
    );
    final harmonyKeys = _dependencyOverrideKeys(
      File('pubspec_overrides.ohos.yaml').readAsStringSync(),
    );

    expect(harmonyKeys, containsAll(sharedKeys));
  });

  test('desktop multi-window downgrade is isolated to HarmonyOS mode', () {
    final sharedPubspec = File('pubspec.yaml').readAsStringSync();
    final harmonyOverrides = File(
      'pubspec_overrides.ohos.yaml',
    ).readAsStringSync();
    final mainlineFacade = File(
      'packages/desktop_multi_window/lib/desktop_multi_window.dart',
    ).readAsStringSync();
    final harmonyFacade = File(
      'packages/desktop_multi_window_ohos/lib/desktop_multi_window.dart',
    ).readAsStringSync();

    expect(
      sharedPubspec,
      contains('path: packages/desktop_multi_window'),
    );
    expect(
      harmonyOverrides,
      contains('path: packages/desktop_multi_window_ohos'),
    );
    expect(mainlineFacade, contains('nipaplay/desktop_multi_window_host'));
    expect(harmonyFacade, contains('static bool get isSupported => false'));
  });

  test('HarmonyOS project does not commit local signing material', () {
    final buildProfile = File(
      'ohos/build-profile.json5',
    ).readAsStringSync();
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
    final workflow = File(
      '.github/workflows/build-ohos.yml',
    ).readAsStringSync();

    expect(workflow, contains('workflow_dispatch:'));
    expect(workflow, contains('workflow_call:'));
    expect(workflow, contains('--no-codesign'));
    expect(workflow, contains('hap-sign-tool.jar'));
    expect(workflow, contains('verify-app'));
    expect(workflow, contains('release-HarmonyOS-signed'));
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

  test('application source does not require custom Platform APIs', () {
    final incompatibleFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where(
          (file) => file.readAsStringSync().contains('Platform.isOhos'),
        )
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
