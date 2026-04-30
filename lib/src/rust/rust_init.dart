import 'frb_generated.dart';

Future<void>? _rustInitFuture;

/// Initializes flutter_rust_bridge once per Dart isolate.
Future<void> ensureRustInitialized() async {
  try {
    _rustInitFuture ??= RustLib.init();
    await _rustInitFuture;
  } catch (_) {
    _rustInitFuture = null;
    rethrow;
  }
}
