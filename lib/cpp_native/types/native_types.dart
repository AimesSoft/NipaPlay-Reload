/// Conditional export for native FFI types.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'native_types_web.dart'
    if (dart.library.ffi) 'native_types_io.dart';
