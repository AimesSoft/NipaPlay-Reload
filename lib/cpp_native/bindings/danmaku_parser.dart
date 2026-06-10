/// Conditional export for DanmakuParser.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'danmaku_parser_web.dart'
    if (dart.library.ffi) 'danmaku_parser_io.dart';
