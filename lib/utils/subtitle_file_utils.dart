import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/src/rust/api/media_metadata.dart' as rust_metadata;
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:path/path.dart' as p;

const Map<String, int> subtitleExtensionMatchScore = <String, int>{
  '.ass': 70,
  '.ssa': 60,
  '.srt': 50,
  '.sub': 35,
  '.sup': 20,
  '.idx': 20,
};

const Set<String> supportedSubtitleExtensions = <String>{
  '.ass',
  '.ssa',
  '.srt',
  '.sub',
  '.sup',
  '.idx',
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
  'idx',
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

/// Read only the MPEG-PS signature; MicroDVD .sub files remain text subtitles.
bool isVobSubBinaryFile(String path) {
  if (p.extension(path).toLowerCase() != '.sub') return false;
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final header = file.readSync(4);
    return header.length == 4 &&
        header[0] == 0 &&
        header[1] == 0 &&
        header[2] == 1 &&
        header[3] == 0xba;
  } on FileSystemException {
    return false;
  } finally {
    file?.closeSync();
  }
}

/// Candidate matching must reject other episodes even when a series title matches.
bool subtitleMatchesVideo(String videoName, String subtitleName) {
  (int?, int?) episode(String name) {
    final serial =
        RegExp(r's(\d+)e(\d+)', caseSensitive: false).firstMatch(name);
    if (serial != null) return (int.parse(serial[1]!), int.parse(serial[2]!));
    final tokens = extractSubtitleMatchTokens(name);
    final numbers = tokens.where((t) => RegExp(r'^\d+$').hasMatch(t)).toList();
    final number = pickLikelyEpisodeNumber(numbers);
    return (null, number == null ? null : int.tryParse(number));
  }

  final videoEpisode = episode(videoName), subEpisode = episode(subtitleName);
  if (videoEpisode.$2 != null &&
      subEpisode.$2 != null &&
      videoEpisode.$2 != subEpisode.$2) return false;
  if (videoEpisode.$1 != null &&
      subEpisode.$1 != null &&
      videoEpisode.$1 != subEpisode.$1) return false;
  Set<String> titleTokens(String name) => extractSubtitleMatchTokens(name)
      .where((t) => !RegExp(r'^\d+$|^s\d+e\d+$').hasMatch(t))
      .toSet();
  final videoTitle = titleTokens(videoName),
      subTitle = titleTokens(subtitleName);
  if (videoTitle.isNotEmpty &&
      subTitle.isNotEmpty &&
      videoTitle.intersection(subTitle).isEmpty) return false;
  final numbers =
      RegExp(r'(\d+)').allMatches(videoName).map((m) => m[0]!).toList();
  return computeLocalSubtitleMatchScore(
          videoName: videoName,
          subtitleName: subtitleName,
          extension: '',
          videoNumbers: numbers,
          episodeNumber: videoEpisode.$2?.toString()) >=
      minReliableLocalSubtitleMatchScore;
}

/// Locate a companion without assuming lowercase extensions on case-sensitive disks.
String? vobSubCompanionPath(String path, String extension) {
  final expected = p.setExtension(path, extension);
  try {
    final name = p.basename(expected).toLowerCase();
    for (final entry in File(path).parent.listSync()) {
      if (entry is File && p.basename(entry.path).toLowerCase() == name)
        return entry.path;
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

/// Bitmap .sub files are selected through their index; text .sub files stand alone.
String canonicalSubtitlePath(String path) => isVobSubBinaryFile(path)
    ? (vobSubCompanionPath(path, '.idx') ?? path)
    : path;

/// Both VobSub members must exist. A MicroDVD text .sub needs no companion.
bool isVobSubPairComplete(String subtitlePath) {
  final ext = p.extension(subtitlePath).toLowerCase();
  if (ext == '.idx') {
    final subPath = vobSubCompanionPath(subtitlePath, '.sub');
    return File(subtitlePath).existsSync() &&
        subPath != null &&
        isVobSubBinaryFile(subPath);
  }
  if (ext == '.sub' && isVobSubBinaryFile(subtitlePath)) {
    final idx = vobSubCompanionPath(subtitlePath, '.idx');
    return idx != null && File(idx).lengthSync() > 0;
  }
  return true;
}

/// 列表来源的配对校验：candidateNames 为同一目录下可见字幕文件名集合。
/// 远程列表（WebDAV/SMB/共享库/弹弹play）中 .idx 孤立（无同名 .sub）时剔除。
bool isVobSubPairCompleteInNames(String fileName, Set<String> candidateNames) {
  final ext = p.extension(fileName).toLowerCase();
  if (ext != '.idx') return true;
  final base = p.basenameWithoutExtension(fileName).toLowerCase();
  return candidateNames.contains('$base.sub');
}

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
  if (RustLib.instance.initialized) {
    try {
      return rust_metadata.subtitleNormalizeMatchName(name: name);
    } catch (_) {
      // 使用下方 Dart/Web fallback。
    }
  }
  return extractSubtitleMatchTokens(name).join(' ');
}

Set<String> extractSubtitleMatchTokens(String name) {
  if (RustLib.instance.initialized) {
    try {
      return rust_metadata.subtitleExtractMatchTokens(name: name).toSet();
    } catch (_) {
      // 使用下方 Dart/Web fallback。
    }
  }
  var working = name.toLowerCase();
  working = working.replaceAll(_subtitleBracketPattern, ' ');

  final rawTokens = working
      .split(_subtitleSplitPattern)
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty);

  return rawTokens.where((token) => !_isSubtitleNoiseToken(token)).toSet();
}

String? pickLikelyEpisodeNumber(List<String> numbers) {
  if (RustLib.instance.initialized) {
    try {
      return rust_metadata.subtitlePickLikelyEpisodeNumber(numbers: numbers);
    } catch (_) {
      // 使用下方 Dart/Web fallback。
    }
  }
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
  if (RustLib.instance.initialized) {
    try {
      return rust_metadata.subtitleComputeMatchScore(
        videoName: videoName,
        subtitleName: subtitleName,
        extension_: extension,
        videoNumbers: videoNumbers,
        episodeNumber: episodeNumber,
      );
    } catch (_) {
      // 使用下方 Dart/Web fallback。
    }
  }
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

  score += computeSubtitleLanguagePreferenceBonus(subtitleName);

  return score;
}

/// 语言偏好加权：同名多字幕（如 .ass 与 .SC.ass）时优先默认激活简体/简日，
/// 繁中次之。其余语言不加权。
int computeSubtitleLanguagePreferenceBonus(String subtitleName) {
  final lower = subtitleName.toLowerCase();
  // 语言标记通常是文件名末段（.SC.ass / .chs&sja），按点分段检测
  final segments = lower.split(RegExp(r'[.\[\] ()_-]+'));
  const simplified = {
    'sc',
    'chs',
    'gb',
    'scjp',
    'chsjpn',
    'sc&jp',
    'sc&jpn',
    'chs&jpn',
    'chs&jp',
  };
  const traditional = {
    'tc',
    'cht',
    'big5',
    'tcjp',
    'chtjpn',
    'tc&jp',
    'tc&jpn'
  };
  for (final segment in segments) {
    if (simplified.contains(segment) ||
        segment.contains('简中') ||
        segment.contains('简体') ||
        segment.contains('简日')) {
      return 15;
    }
    if (segment.contains('jp') ||
        segment.contains('jpn') ||
        segment == 'ja' ||
        segment.contains('日')) {
      return 12;
    }
  }
  for (final segment in segments) {
    if (traditional.contains(segment) ||
        segment.contains('繁中') ||
        segment.contains('繁体')) {
      return 6;
    }
  }
  return 0;
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
