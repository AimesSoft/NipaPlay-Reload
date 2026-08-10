import '../models/emby_media_selection.dart';

EmbyReleaseIdentity parseEmbyReleaseIdentity(String name) {
  final tokens = _tokenize(name);
  final nonTechnicalTokens =
      tokens.where((token) => !_isTechnical(token)).toList(growable: false);
  final releaseFormats = _parseReleaseFormats(nonTechnicalTokens);
  final normalizedFullName = nonTechnicalTokens.join(' ');
  final features = <String>{
    ...nonTechnicalTokens.where(_isFeature).map((token) => token.toLowerCase()),
    ...releaseFormats.features,
  };
  final families = <String>{
    for (final entry in nonTechnicalTokens.asMap().entries)
      if (!_isFeature(entry.value) &&
          !releaseFormats.tokenIndexes.contains(entry.key))
        entry.value.toLowerCase(),
  };

  return EmbyReleaseIdentity(
    normalizedFullName: normalizedFullName,
    families: families,
    features: features,
  );
}

List<String> _tokenize(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(
      RegExp(r'[\s._/\\|,:;!?+&()\[\]{}<>\-\u00b7\u2022\u2013\u2014]+'),
      ' ',
    )
    .split(RegExp(r'\s+'))
    .where((token) => token.isNotEmpty)
    .toList(growable: false);

bool _isTechnical(String token) =>
    RegExp(r'^\d{3,4}p$').hasMatch(token) ||
    const {
      '2160p',
      '1440p',
      '1080p',
      '720p',
      '576p',
      '480p',
      'h264',
      'h265',
      'hevc',
      'av1',
      'x264',
      'x265',
      'vp9',
      '10bit',
      '8bit',
      'hdr',
      'hdr10',
      'dv',
      'dovi',
      'aac',
      'flac',
      'opus',
      'ac3',
      'eac3',
    }.contains(token);

({Set<String> features, Set<int> tokenIndexes}) _parseReleaseFormats(
  List<String> tokens,
) {
  final features = <String>{};
  final tokenIndexes = <int>{};
  for (var index = 0; index < tokens.length; index++) {
    final token = tokens[index];
    final next = index + 1 < tokens.length ? tokens[index + 1] : null;
    final pairFeature = switch ((token, next)) {
      ('web', 'dl') => 'web-dl',
      ('web', 'rip') => 'web-rip',
      ('blu', 'ray') => 'bluray',
      ('bd', 'rip') => 'bdrip',
      _ => null,
    };
    if (pairFeature != null) {
      features.add(pairFeature);
      tokenIndexes.addAll({index, index + 1});
      index++;
      continue;
    }

    final feature = switch (token) {
      'webdl' => 'web-dl',
      'webrip' => 'web-rip',
      'bluray' || 'bdrip' || 'remux' || 'raw' || 'encode' => token,
      _ => null,
    };
    if (feature != null) {
      features.add(feature);
      tokenIndexes.add(index);
    } else if (token == 'web' || token == 'dl') {
      tokenIndexes.add(index);
    }
  }
  return (features: features, tokenIndexes: tokenIndexes);
}

bool _isFeature(String token) => RegExp(
      r'[\u7b80\u7e41]|\u5185\u5c01|\u5185\u5d4c|\u5916\u6302|\u5b57\u5e55|\u53cc\u8bed|\u4e2d\u5b57',
    ).hasMatch(token);
