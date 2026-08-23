enum DanmakuAutoLoadStrategy {
  remoteAndLocal,
  remote,
  local,
  // Legacy persisted value; new versions store the skip switch separately.
  manual,
}

typedef DanmakuAutoLoadSettings = ({
  DanmakuAutoLoadStrategy strategy,
  bool skipMatching,
});

extension DanmakuAutoLoadStrategyPrefs on DanmakuAutoLoadStrategy {
  String get prefsValue {
    switch (this) {
      case DanmakuAutoLoadStrategy.remoteAndLocal:
        return 'remoteAndLocal';
      case DanmakuAutoLoadStrategy.remote:
        return 'remote';
      case DanmakuAutoLoadStrategy.local:
        return 'local';
      case DanmakuAutoLoadStrategy.manual:
        return 'manual';
    }
  }
}

DanmakuAutoLoadStrategy danmakuAutoLoadStrategyFromPrefs(
  String? value, {
  bool legacyAutoMatchOnPlay = true,
}) {
  switch (value) {
    case 'remoteAndLocal':
      return DanmakuAutoLoadStrategy.remoteAndLocal;
    case 'remote':
      return DanmakuAutoLoadStrategy.remote;
    case 'local':
      return DanmakuAutoLoadStrategy.local;
    case 'manual':
      return DanmakuAutoLoadStrategy.manual;
    default:
      return legacyAutoMatchOnPlay
          ? DanmakuAutoLoadStrategy.remoteAndLocal
          : DanmakuAutoLoadStrategy.manual;
  }
}

DanmakuAutoLoadSettings resolveDanmakuAutoLoadSettings({
  required String? persistedStrategy,
  required bool? persistedSkipMatching,
  required bool? legacyAutoMatchOnPlay,
}) {
  final loadedStrategy = danmakuAutoLoadStrategyFromPrefs(
    persistedStrategy,
    legacyAutoMatchOnPlay: legacyAutoMatchOnPlay ?? true,
  );
  final usesLegacyManualStrategy =
      loadedStrategy == DanmakuAutoLoadStrategy.manual;

  return (
    strategy: usesLegacyManualStrategy
        ? DanmakuAutoLoadStrategy.remoteAndLocal
        : loadedStrategy,
    skipMatching: persistedSkipMatching ?? usesLegacyManualStrategy,
  );
}
