/// Conditional export for SimilarityEngine.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'similarity_engine_web.dart'
    if (dart.library.ffi) 'similarity_engine_io.dart';
