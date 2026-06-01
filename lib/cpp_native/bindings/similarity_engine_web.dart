/// Web stub for SimilarityEngine.
///
/// Provides the same public API as [similarity_engine_io.dart] without
/// any `dart:ffi` / `package:ffi` imports, so it compiles on Web.
/// On Web the similarity engine is never actually used.

class SimilarityResult {
  final List<SimilarityPair> pairs;
  final List<List<int>> groups;

  const SimilarityResult({required this.pairs, required this.groups});

  factory SimilarityResult.empty() =>
      const SimilarityResult(pairs: [], groups: []);
}

class SimilarityPair {
  final int sourceIndex;
  final int targetIndex;
  final String reason;
  final int distance;
  final double score;

  const SimilarityPair({
    required this.sourceIndex,
    required this.targetIndex,
    required this.reason,
    required this.distance,
    required this.score,
  });
}

class DanmakuSimItem {
  final String text;
  final int mode;
  final double timeSeconds;

  const DanmakuSimItem({
    required this.text,
    required this.mode,
    required this.timeSeconds,
  });
}

class SimilarityConfig {
  final int maxDist;
  final int maxCosine;
  final bool usePinyin;
  final bool crossMode;
  final double timeWindow;

  const SimilarityConfig({
    this.maxDist = 3,
    this.maxCosine = 70,
    this.usePinyin = true,
    this.crossMode = false,
    this.timeWindow = 45.0,
  });
}

/// Web stub — all methods return default values
class SimilarityEngine {
  static SimilarityResult checkSimilarity(
          List<DanmakuSimItem> items, SimilarityConfig config) =>
      SimilarityResult.empty();

  static double pairSimilarity(String textA, String textB,
          {bool usePinyin = true}) =>
      0.0;

  static bool probeNativeBinding() => false;
}
