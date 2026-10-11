// Keep Windows FFI out of the embedded Web application's dependency graph.
export 'package:nipaplay_core/models/external_player_session/potplayer_window_api_stub.dart'
    if (dart.library.ffi) 'potplayer_window_api_native.dart';
