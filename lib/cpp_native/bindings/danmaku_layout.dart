/// Conditional export for DanmakuLayoutEngine.
///
/// Default: Web stub (no dart:ffi dependency).
/// Override: Real FFI implementation when dart:ffi is available (all native platforms).
export 'danmaku_layout_web.dart'
    if (dart.library.ffi) 'danmaku_layout_io.dart';
