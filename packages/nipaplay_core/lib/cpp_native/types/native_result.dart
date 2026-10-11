/// Conditional export for native result types.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'package:nipaplay_core/cpp_native/types/native_result_web.dart'
    if (dart.library.ffi) 'native_result_io.dart';
