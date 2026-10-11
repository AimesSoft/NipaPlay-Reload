/// Conditional export for SubtitleParser.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'package:nipaplay_core/cpp_native/bindings/subtitle_parser_web.dart'
    if (dart.library.ffi) 'subtitle_parser_io.dart';
