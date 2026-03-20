import 'dart:io';

import 'package:flutter/foundation.dart';

const Map<String, int> subtitleExtensionMatchScore = <String, int>{
  '.ass': 70,
  '.ssa': 60,
  '.srt': 50,
  '.sub': 35,
  '.sup': 20,
};

const Set<String> supportedSubtitleExtensions = <String>{
  '.ass',
  '.ssa',
  '.srt',
  '.sub',
  '.sup',
};

const int minReliableLocalSubtitleMatchScore = 100;

const int _exactNameMatchBonus = 500;
const int _prefixNameMatchBonus = 320;
const int _normalizedExactMatchBonus = 280;
const int _normalizedPrefixMatchBonus = 220;
const int _normalizedContainsMatchBonus = 180;
const int _normalizedContainedByMatchBonus = 80;
const int _tokenOverlapWeight = 25;
const int _allVideoTokensMatchedBonus = 120;
const int _zeroTokenOverlapPenalty = 80;
const int _episodeExactMatchBonus = 220;
const int _episodeNumericEqualBonus = 190;
const int _episodeMismatchPenalty = 120;
const int _fallbackNumberMatchBonus = 15;

const Set<String> _subtitleNoiseTokens = <String>{
  'ass',
  'srt',
  'ssa',
  'sub',
  'sup',
  'subtitle',
  'subtitles',
  'subs',
  'caption',
  'captions',
  'cc',
  'sdh',
  'chs',
  'cht',
  'sc',
  'tc',
  'gb',
  'big5',
  'zh',
  'zho',
  'chi',
  'cn',
  'jp',
  'jpn',
  'eng',
  'english',
  'chsjpn',
  'chtjpn',
  'scjp',
  'tcjp',
  'bilingual',
  'default',
  'forced',
  'signs',
  'sign',
  'dialogue',
  'dialog',
  '简中',
  '繁中',
  '简体',
  '繁体',
  '中文',
  '字幕',
  '双语',
};

final RegExp _subtitleBracketPattern = RegExp(r'[\[\(\{][^\]\)\}]*[\]\)\}]');
final RegExp _subtitleSplitPattern = RegExp(
  r'[^a-z0-9\u4e00-\u9fff\u3040-\u30ff\uac00-\ud7af]+',
);
final RegExp _subtitleResolutionPattern = RegExp(
  r'^\d{3,4}p$|^\d{3,4}x\d{3,4}$',
);
final RegExp _subtitleCodecPattern = RegExp(
  r'^(x26[45]|h26[45]|hevc|av1|avc|aac\d*|flac|ac3|eac3|opus|truehd|dts|dtsx|atmos|hdr\d*|dv|uhd|remux|webdl|web|webrip|bluray|bdrip|10bit|8bit)$',
);
final RegExp _subtitleLongNumberPattern = RegExp(r'^\d{3,4}$');

String normalizeExternalSubtitleTrackUri(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || kIsWeb) {
    return trimmed;
  }

  final lower = trimmed.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('file://') ||
      lower.startsWith('content://') ||
      lower.startsWith('fd://') ||
      lower.startsWith('asset://') ||
      lower.startsWith('data:') ||
      lower.startsWith('rtsp://') ||
      lower.startsWith('rtmp://')) {
    return trimmed;
  }

  return File(trimmed).absolute.uri.toString();
}

String normalizeSubtitleMatchName(String name) {
  return extractSubtitleMatchTokens(name).join(' ');
}

Set<String> extractSubtitleMatchTokens(String name) {
  var working = name.toLowerCase();
  working = working.replaceAll(_subtitleBracketPattern, ' ');

  final rawTokens = working
      .split(_subtitleSplitPattern)
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty);

  return rawTokens.where((token) => !_isSubtitleNoiseToken(token)).toSet();
}

String? pickLikelyEpisodeNumber(List<String> numbers) {
  for (final number in numbers) {
    final parsed = int.tryParse(number);
    if (number.length == 2 && parsed != null && parsed > 0) {
      return number;
    }
  }
  return numbers.isNotEmpty ? numbers.last : null;
}

int computeLocalSubtitleMatchScore({
  required String videoName,
  required String subtitleName,
  required String extension,
  required List<String> videoNumbers,
  String? episodeNumber,
}) {
  final lowerVideo = videoName.toLowerCase();
  final lowerSubtitle = subtitleName.toLowerCase();
  final normalizedVideo = normalizeSubtitleMatchName(videoName);
  final normalizedSubtitle = normalizeSubtitleMatchName(subtitleName);

  var score = subtitleExtensionMatchScore[extension.toLowerCase()] ?? 0;

  if (lowerSubtitle == lowerVideo) {
    score += _exactNameMatchBonus;
  }

  if (lowerSubtitle.startsWith('$lowerVideo.') ||
      lowerSubtitle.startsWith('$lowerVideo ') ||
      lowerSubtitle.startsWith('$lowerVideo[') ||
      lowerSubtitle.startsWith('$lowerVideo(')) {
    score += _prefixNameMatchBonus;
  }

  if (normalizedVideo.isNotEmpty && normalizedSubtitle == normalizedVideo) {
    score += _normalizedExactMatchBonus;
  } else if (normalizedVideo.isNotEmpty &&
      normalizedSubtitle.startsWith('$normalizedVideo ')) {
    score += _normalizedPrefixMatchBonus;
  } else if (normalizedVideo.isNotEmpty &&
      normalizedSubtitle.contains(normalizedVideo)) {
    score += _normalizedContainsMatchBonus;
  } else if (normalizedSubtitle.isNotEmpty &&
      normalizedVideo.contains(normalizedSubtitle)) {
    score += _normalizedContainedByMatchBonus;
  }

  final videoTokens = extractSubtitleMatchTokens(videoName);
  final subtitleTokens = extractSubtitleMatchTokens(subtitleName);
  final overlapCount = videoTokens.intersection(subtitleTokens).length;

  score += overlapCount * _tokenOverlapWeight;

  if (videoTokens.isNotEmpty && overlapCount == videoTokens.length) {
    score += _allVideoTokensMatchedBonus;
  } else if (videoTokens.length >= 2 && overlapCount == 0) {
    score -= _zeroTokenOverlapPenalty;
  }

  final subtitleNumbers = RegExp(
    r'(\d+)',
  ).allMatches(subtitleName).map((match) => match.group(0)!).toList();
  final subtitleEpisode = pickLikelyEpisodeNumber(subtitleNumbers);

  if (episodeNumber != null && subtitleEpisode != null) {
    if (episodeNumber == subtitleEpisode) {
      score += _episodeExactMatchBonus;
    } else {
      final videoEpisodeInt = int.tryParse(episodeNumber);
      final subtitleEpisodeInt = int.tryParse(subtitleEpisode);
      if (videoEpisodeInt != null &&
          subtitleEpisodeInt != null &&
          videoEpisodeInt > 0 &&
          videoEpisodeInt == subtitleEpisodeInt) {
        score += _episodeNumericEqualBonus;
      } else {
        score -= _episodeMismatchPenalty;
      }
    }
  } else if (videoNumbers.isNotEmpty && subtitleNumbers.isNotEmpty) {
    for (final videoNumber in videoNumbers.take(3)) {
      if (subtitleNumbers.contains(videoNumber)) {
        score += _fallbackNumberMatchBonus;
      }
    }
  }

  return score;
}

bool _isSubtitleNoiseToken(String token) {
  if (_subtitleNoiseTokens.contains(token)) {
    return true;
  }
  if (_subtitleResolutionPattern.hasMatch(token) ||
      _subtitleCodecPattern.hasMatch(token) ||
      _subtitleLongNumberPattern.hasMatch(token)) {
    return true;
  }
  if (token.startsWith('zh') && token.length <= 8) {
    return true;
  }
  return false;
}
