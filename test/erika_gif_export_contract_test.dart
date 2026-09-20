import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Erika headless GIF export covers every native plugin platform', () {
    final adapter = File(
      'lib/player_abstraction/erika_player_adapter.dart',
    ).readAsStringSync();
    final nativeBridge = File(
      'lib/player_abstraction/erika_gif_export_io.dart',
    ).readAsStringSync();

    expect(adapter, contains('supportsHeadlessGifExport => _isSupported'));
    expect(nativeBridge, contains('Isolate.run'));
    expect(nativeBridge, contains('Platform.isIOS'));
    expect(nativeBridge, contains('Platform.isMacOS'));
    expect(nativeBridge, contains('Platform.isWindows'));
    expect(nativeBridge, contains('Platform.isAndroid'));
    expect(nativeBridge, contains("Platform.operatingSystem == 'ohos'"));
    expect(nativeBridge, contains("'erika_export_gif'"));
    expect(nativeBridge, contains("'liberika_capi.dylib'"));
    expect(nativeBridge, contains("'erika_capi.dll'"));
    expect(nativeBridge, contains("'liberika_capi.so'"));
  });
}
