/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:ffi';

/// {@template native_library}
///
/// NativeLibrary
/// -------------
///
/// Discovers & loads the libmpv shared library.
///
/// {@endtemplate}
abstract class NativeLibrary {
  /// The resolved libmpv dynamic library.
  static String get path {
    if (_resolved == null) {
      throw Exception(
        'MediaKit.ensureInitialized must be called before using any API from package:media_kit.',
      );
    }
    return _resolved!;
  }

  /// Initializes the |NativeLibrary| class for usage.
  /// This method discovers & loads the libmpv shared library. It is generally present with the name `libmpv-2.dll` on Windows & `libmpv.so` on GNU/Linux.
  /// The [libmpv] parameter can be used to manually specify the path to the libmpv shared library.
  static void ensureInitialized({String? libmpv}) {
    final candidates = <String>[];

    if (libmpv != null) {
      candidates.add(libmpv);
    }

    try {
      final env = Platform.environment['LIBMPV_LIBRARY_PATH'];
      if (env != null && env.isNotEmpty) {
        candidates.add(env);
      }
    } catch (_) {}

    final names = _defaultCandidatesForCurrentPlatform();
    if (names != null) {
      candidates.addAll(names);
      for (final candidate in _dedupeCandidates(candidates)) {
        try {
          DynamicLibrary.open(candidate);
          _resolved = candidate;
          return;
        } catch (_) {}
      }

      if (_resolved == null) {
        throw Exception(
          {
            'windows':
                'Cannot find libmpv-2.dll in your system %PATH%. One way to deal with this is to ship libmpv-2.dll with your compiled executable or script in the same directory.',
            'linux':
                'Cannot find libmpv at the usual places. Depending upon your distribution, you can install the libmpv package to make shared library available globally. On Debian or Ubuntu based systems, you can install it with: apt install libmpv-dev.',
            'macos':
                'Cannot find Mpv.framework/Mpv. Please ensure it\'s presence in the Frameworks folder of the application.',
            'ios':
                'Cannot find Mpv.framework/Mpv. Please ensure it\'s presence in the Frameworks folder of the application.',
            'android':
                'Cannot find libmpv.so. Please ensure it\'s presence in the APK.',
          }[Platform.operatingSystem]!,
        );
      }
    } else {
      throw Exception(
        'Unsupported operating system: ${Platform.operatingSystem}',
      );
    }
  }

  static List<String>? _defaultCandidatesForCurrentPlatform() {
    switch (Platform.operatingSystem) {
      case 'windows':
        return const [
          'libmpv-2.dll',
          'mpv-2.dll',
          'mpv-1.dll',
        ];
      case 'linux':
        return const [
          'libmpv.so',
          'libmpv.so.2',
          'libmpv.so.1',
        ];
      case 'macos':
        return _darwinFrameworkCandidates(
          versionsPath: 'Frameworks/Mpv.framework/Versions/A/Mpv',
          shortPath: 'Frameworks/Mpv.framework/Mpv',
        );
      case 'ios':
        return _darwinFrameworkCandidates(
          versionsPath: 'Frameworks/Mpv.framework/Versions/A/Mpv',
          shortPath: 'Frameworks/Mpv.framework/Mpv',
          bundleParentLevels: 0,
        );
      case 'android':
        return const [
          'libmpv.so',
        ];
      default:
        return null;
    }
  }

  static List<String> _darwinFrameworkCandidates({
    required String versionsPath,
    required String shortPath,
    int bundleParentLevels = 1,
  }) {
    final executable = File(Platform.resolvedExecutable);
    Directory bundleRoot = executable.parent;
    for (int i = 0; i < bundleParentLevels; i++) {
      bundleRoot = bundleRoot.parent;
    }

    final bundleVersionsPath =
        bundleRoot.uri.resolve(versionsPath).toFilePath();
    final bundleShortPath = bundleRoot.uri.resolve(shortPath).toFilePath();

    return _dedupeCandidates([
      bundleVersionsPath,
      bundleShortPath,
      'Mpv.framework/Versions/A/Mpv',
      'Mpv.framework/Mpv',
    ]);
  }

  static List<String> _dedupeCandidates(List<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final candidate = value.trim();
      if (candidate.isEmpty || !seen.add(candidate)) {
        continue;
      }
      result.add(candidate);
    }
    return result;
  }

  /// The resolved libmpv dynamic library.
  ///
  /// **NOTE:** We are storing this value as [String] because we want to send/receive this across [Isolate]s.
  static String? _resolved;
}
