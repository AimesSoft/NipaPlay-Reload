/// Conditional export for ExampleCalculator.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'example_calculator_web.dart'
    if (dart.library.ffi) 'example_calculator_io.dart';
