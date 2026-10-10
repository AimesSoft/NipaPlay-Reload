import 'package:nipa_harness/nipa_harness.dart';

JsonMap analyzeDanmakuAnchors(List<JsonMap> anchors) {
  if (anchors.length > 100) {
    throw const Failure(
        FailureCode.invalidInput, 'At most 100 alignment anchors.');
  }
  final offsets = [
    for (final a in anchors)
      (a['sourceTimeMs'] as int) - (a['mediaTimeMs'] as int)
  ];
  final sorted = [...offsets]..sort();
  final estimate = sorted.isEmpty ? null : sorted[sorted.length ~/ 2];
  final residuals = [for (final n in offsets) (n - estimate!).abs()];
  final maximum =
      residuals.isEmpty ? null : residuals.reduce((a, b) => a > b ? a : b);
  final times = [for (final a in anchors) a['sourceTimeMs'] as int]..sort();
  final span = times.isEmpty ? 0 : times.last - times.first;
  return {
    'estimateOffsetMs': estimate,
    'anchorOffsetsMs': offsets,
    'residualsMs': residuals,
    'maxResidualMs': maximum,
    'anchorSpanMs': span,
    'method': 'median',
    'anchors': anchors,
    'evidence': [for (final a in anchors) a['evidence']],
    'confidence': offsets.length >= 3 && span >= 60000 && maximum! <= 250
        ? 'consistentAnchors'
        : 'insufficientEvidence',
    'limitations': [
      'Only a fixed translation of the supplied anchors is estimated.',
      'Anchor consistency does not verify episode identity or semantic alignment.',
      if (sorted.length.isEven && sorted.isNotEmpty)
        'For an even anchor count, the upper middle offset is used.',
      if (anchors.isEmpty) 'No anchors supplied; no offset can be estimated.'
    ]
  };
}
