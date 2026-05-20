import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:path/path.dart' as p;

const String _stem = 'rust_lib_nipaplay';
const bool _logRustLibraryLoading = bool.fromEnvironment(
  'NIPAPLAY_RUST_DYLIB_LOG',
  defaultValue: false,
);

ExternalLibrary openRustExternalLibrary() {
  if (Platform.isIOS) {
    // iOS links the Rust static library into the app process via CocoaPods.
    return ExternalLibrary.process(
      iKnowHowToUseIt: true,
      debugInfo: ' for iOS static Rust library',
    );
  }

  if (Platform.isAndroid) {
    return ExternalLibrary.open('lib$_stem.so');
  }

  if (Platform.isWindows) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return _openFirstAvailable(
      candidates: <String>[
        p.join(exeDir, '$_stem.dll'),
        p.join(Directory.current.path, '$_stem.dll'),
      ],
      fallback: '$_stem.dll',
    );
  }

  if (Platform.isMacOS) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return _openFirstAvailable(
      candidates: <String>[
        p.normalize(
          p.join(
            exeDir,
            '..',
            'Frameworks',
            '$_stem.framework',
            _stem,
          ),
        ),
        p.normalize(
          p.join(exeDir, '..', 'Frameworks', 'lib$_stem.dylib'),
        ),
        p.normalize(
          p.join(
            exeDir,
            '..',
            'Frameworks',
            'rust_builder.framework',
            'rust_builder',
          ),
        ),
        p.normalize(
          p.join(
            Directory.current.path,
            'rust',
            'target',
            'release',
            'lib$_stem.dylib',
          ),
        ),
      ],
      fallback: '$_stem.framework/$_stem',
    );
  }

  if (Platform.isLinux) {
    return _openFirstAvailable(
      candidates: <String>[
        p.normalize(
          p.join(
            Directory.current.path,
            'rust',
            'target',
            'release',
            'lib$_stem.so',
          ),
        ),
        'lib$_stem.so',
        '$_stem.so',
      ],
      fallback: 'lib$_stem.so',
    );
  }

  throw UnsupportedError(
    'Rust runtime is not supported on ${Platform.operatingSystem}.',
  );
}

ExternalLibrary _openFirstAvailable({
  required List<String> candidates,
  required String fallback,
}) {
  for (final candidate in candidates) {
    try {
      if (_looksLikePath(candidate) && !File(candidate).existsSync()) {
        _log('skip missing Rust library candidate: $candidate');
        continue;
      }
      _log('open Rust library candidate: $candidate');
      return ExternalLibrary.open(candidate);
    } catch (error) {
      _log('failed Rust library candidate "$candidate": $error');
    }
  }
  _log('open Rust library fallback: $fallback');
  return ExternalLibrary.open(fallback);
}

bool _looksLikePath(String value) {
  return value.contains('/') || value.contains(r'\');
}

void _log(String message) {
  if (_logRustLibraryLoading) {
    // ignore: avoid_print
    print('[RustExternalLibrary] $message');
  }
}
