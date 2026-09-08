// Keep Windows FFI out of the embedded Web application's dependency graph.
export 'potplayer_window_api_stub.dart'
    if (dart.library.ffi) 'potplayer_window_api_native.dart';
