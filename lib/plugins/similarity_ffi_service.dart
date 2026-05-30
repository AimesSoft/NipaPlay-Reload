/// Conditional export for SimilarityFfiService.
///
/// Default: Web stub (no dart:ffi / dart:io / package:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'similarity_ffi_service_web.dart'
    if (dart.library.ffi) 'similarity_ffi_service_io.dart';
