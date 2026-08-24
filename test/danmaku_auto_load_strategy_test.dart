import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';

void main() {
  group('DanmakuAutoLoadStrategy', () {
    test('serializes to preference values', () {
      expect(
        DanmakuAutoLoadStrategy.remoteAndLocal.prefsValue,
        'remoteAndLocal',
      );
      expect(DanmakuAutoLoadStrategy.remote.prefsValue, 'remote');
      expect(DanmakuAutoLoadStrategy.local.prefsValue, 'local');
      expect(DanmakuAutoLoadStrategy.manual.prefsValue, 'manual');
    });

    test('parses persisted preference values', () {
      expect(
        danmakuAutoLoadStrategyFromPrefs('remoteAndLocal'),
        DanmakuAutoLoadStrategy.remoteAndLocal,
      );
      expect(
        danmakuAutoLoadStrategyFromPrefs('remote'),
        DanmakuAutoLoadStrategy.remote,
      );
      expect(
        danmakuAutoLoadStrategyFromPrefs('local'),
        DanmakuAutoLoadStrategy.local,
      );
      expect(
        danmakuAutoLoadStrategyFromPrefs('manual'),
        DanmakuAutoLoadStrategy.manual,
      );
    });

    test('migrates from legacy auto-match setting', () {
      expect(
        danmakuAutoLoadStrategyFromPrefs(
          null,
          legacyAutoMatchOnPlay: true,
        ),
        DanmakuAutoLoadStrategy.remoteAndLocal,
      );
      expect(
        danmakuAutoLoadStrategyFromPrefs(
          null,
          legacyAutoMatchOnPlay: false,
        ),
        DanmakuAutoLoadStrategy.manual,
      );
    });

    test('resolves legacy manual strategy into the standalone skip switch', () {
      final settings = resolveDanmakuAutoLoadSettings(
        persistedStrategy: 'manual',
        persistedSkipMatching: null,
        legacyAutoMatchOnPlay: null,
      );

      expect(settings.strategy, DanmakuAutoLoadStrategy.remoteAndLocal);
      expect(settings.skipMatching, isTrue);
    });

    test('explicit skip preference overrides the legacy manual value', () {
      final settings = resolveDanmakuAutoLoadSettings(
        persistedStrategy: 'manual',
        persistedSkipMatching: false,
        legacyAutoMatchOnPlay: false,
      );

      expect(settings.strategy, DanmakuAutoLoadStrategy.remoteAndLocal);
      expect(settings.skipMatching, isFalse);
    });
  });
}
