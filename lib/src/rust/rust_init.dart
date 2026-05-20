import 'package:flutter/foundation.dart';

import 'frb_generated.dart';
import 'rust_external_library.dart';

Future<void>? _rustInitFuture;

/// Initializes flutter_rust_bridge once per Dart isolate.
Future<void> ensureRustInitialized() async {
  if (kIsWeb) {
    throw UnsupportedError('Rust runtime is not supported on Flutter Web.');
  }

  try {
    _rustInitFuture ??= RustLib.init(
      externalLibrary: openRustExternalLibrary(),
    );
    await _rustInitFuture;
  } catch (_) {
    _rustInitFuture = null;
    rethrow;
  }
}
