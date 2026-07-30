import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

class _NativeDanmakuDelegate extends Fake implements AbstractPlayer {
  final List<bool> visibilityCalls = <bool>[];
  final List<Map<String, Object?>> configCalls = <Map<String, Object?>>[];
  Completer<void>? pendingCall;

  bool get supportsNativeDanmaku => true;

  Future<void> setDanmakuEnabled(bool enabled) {
    visibilityCalls.add(enabled);
    final completer = Completer<void>();
    pendingCall = completer;
    return completer.future;
  }

  Future<void> setDanmakuConfig({
    bool? enabled,
    double? opacity,
    double? fontSize,
    double? displayArea,
    bool? mergeDuplicates,
    bool? allowStacking,
    double? scrollDurationSeconds,
    double? trackGapRatio,
    double? outlineWidth,
    int? shadowStyle,
    String? customFontFamily,
    String? customFontFilePath,
  }) async {
    configCalls.add(<String, Object?>{
      if (enabled != null) 'enabled': enabled,
      if (opacity != null) 'opacity': opacity,
      if (fontSize != null) 'fontSize': fontSize,
      if (displayArea != null) 'displayArea': displayArea,
      if (mergeDuplicates != null) 'mergeDuplicates': mergeDuplicates,
      if (allowStacking != null) 'allowStacking': allowStacking,
      if (scrollDurationSeconds != null)
        'scrollDurationSeconds': scrollDurationSeconds,
      if (trackGapRatio != null) 'trackGapRatio': trackGapRatio,
      if (outlineWidth != null) 'outlineWidth': outlineWidth,
      if (shadowStyle != null) 'shadowStyle': shadowStyle,
      if (customFontFamily != null) 'customFontFamily': customFontFamily,
      if (customFontFilePath != null)
        'customFontFilePath': customFontFilePath,
    });
  }
}

void main() {
  test('native danmaku visibility uses the dedicated immediate delegate call',
      () async {
    final delegate = _NativeDanmakuDelegate();
    final player = Player.withDelegate(delegate);
    var completed = false;

    final update = player.setNativeDanmakuEnabled(false).then((_) {
      completed = true;
    });

    expect(delegate.visibilityCalls, <bool>[false]);
    expect(completed, isFalse);

    delegate.pendingCall!.complete();
    await update;
    expect(completed, isTrue);
  });

  test('native danmaku style updates remain field-specific', () async {
    final delegate = _NativeDanmakuDelegate();
    final player = Player.withDelegate(delegate);

    await player.setNativeDanmakuConfig(opacity: 0.4);
    await player.setNativeDanmakuConfig(fontSize: 36.0);

    expect(delegate.configCalls, <Map<String, Object?>>[
      <String, Object?>{'opacity': 0.4},
      <String, Object?>{'fontSize': 36.0},
    ]);
  });
}
