import 'package:path/path.dart' as p;
import 'package:nipaplay/src/rust/api/media_metadata.dart' as rust_metadata;
import 'package:nipaplay/src/rust/frb_generated.dart';

/// 从常见番组发布文件名中提取更适合搜索的关键词。
///
/// 目标：尽量去掉字幕组/压制组、清晰度、编码等信息，同时保留番名本体（含数字番名）。
class MediaFilenameParser {
  MediaFilenameParser._();

  static String baseNameWithoutExtension(String pathOrName) {
    if (RustLib.instance.initialized) {
      try {
        return rust_metadata.mediaBaseNameWithoutExtension(
          pathOrName: pathOrName,
        );
      } catch (_) {
        // 使用下方 Dart/Web fallback。
      }
    }
    final trimmed = pathOrName.trim();
    if (trimmed.isEmpty) return '';
    final base = p.basename(trimmed);
    return p.basenameWithoutExtension(base).trim();
  }

  /// 生成用于弹幕“搜索动画”的关键词（尽量接近番名）。
  static String extractAnimeTitleKeyword(String pathOrName) {
    if (RustLib.instance.initialized) {
      try {
        return rust_metadata.mediaExtractAnimeTitleKeyword(
          pathOrName: pathOrName,
        );
      } catch (_) {
        // 使用下方 Dart/Web fallback。
      }
    }
    var name = baseNameWithoutExtension(pathOrName);
    if (name.isEmpty) return '';

    // 常见分隔符归一化
    name = name.replaceAll(RegExp(r'[._]+'), ' ').trim();

    // 去掉开头的字幕组/压制组标识（可能存在多个）
    name = _stripLeadingGroupTags(name);

    // 去掉末尾的编码/分辨率等标签（可能存在多个）
    name = _stripTrailingTags(name);

    // 去掉常见季/集标识（仅影响搜索关键词，不做全局数字清理）
    name = name.replaceAll(
      RegExp(r'\bS\d{1,2}E\d{1,3}\b', caseSensitive: false),
      ' ',
    );
    name = name.replaceAll(
      RegExp(r'\bS\d{1,2}\b', caseSensitive: false),
      ' ',
    );
    name = name.replaceAll(
      RegExp(r'\b(?:EP|Ep|ep)\s*\d{1,3}\b'),
      ' ',
    );
    name = name.replaceAll(
      RegExp(r'\bE\d{1,3}\b', caseSensitive: false),
      ' ',
    );

    // 中文/日文“第X话/集/期”
    name = name.replaceAll(RegExp(r'第\s*\d{1,3}\s*[话話集期]'), ' ');
    name = name.replaceAll(RegExp(r'\d{1,3}\s*[话話集期]\b'), ' ');

    // 形如 [01] / 【01】 的独立集数标识（避免误删番名中的数字）
    name = name.replaceAll(RegExp(r'[\[【]\s*\d{1,3}\s*[\]】]'), ' ');

    // 形如 " - 01" / "_01" 的结尾集数
    name = name.replaceAll(RegExp(r'(?:\s*[-_]\s*)\d{1,3}$'), ' ');

    // 清理残留括号/多余空白
    name = name.replaceAll(RegExp(r'[\[\]【】()（）{}]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name;
  }

  /// 在常规标题提取结果上进一步去掉集数、分辨率、编码和字幕语言标签。
  ///
  /// 该关键词用于文件哈希匹配失败后的动画搜索。调用方仍应保留
  /// [extractAnimeTitleKeyword] 作为更保守的候选，避免数字属于作品名时丢失信息。
  static String extractAnimeSearchKeyword(
    String pathOrName, {
    int? episodeNumber,
  }) {
    final title = extractAnimeTitleKeyword(pathOrName);
    if (title.isEmpty) return '';

    final technicalToken = RegExp(
      r'^(?:'
      r'\d{3,4}p|[248]k|'
      r'x26[45]|h26[45]|hevc|avc|av1|'
      r'aac|flac|opus|ac3|eac3|dts|'
      r'web-?dl|webrip|bluray|bdrip|brrip|hdtv|'
      r'hdr10\+?|hdr|dolby|vision|dv|'
      r'jptc|jpchs|jpcht|chs|cht|gb|big5|'
      r'mp4|mkv'
      r')$',
      caseSensitive: false,
    );
    var removedEpisode = false;
    final kept = <String>[];

    for (final token in title.split(RegExp(r'\s+'))) {
      final normalized =
          token.replaceAll(RegExp(r'^[\[\]【】()（）{}]+|[\[\]【】()（）{}]+$'), '');
      if (normalized.isEmpty || technicalToken.hasMatch(normalized)) {
        continue;
      }

      if (!removedEpisode && episodeNumber != null) {
        final numericToken = int.tryParse(normalized);
        if (numericToken == episodeNumber) {
          removedEpisode = true;
          continue;
        }
      }
      kept.add(normalized);
    }

    return kept.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _stripLeadingGroupTags(String name) {
    var result = name.trimLeft();
    while (true) {
      if (result.startsWith('[')) {
        final end = result.indexOf(']');
        if (end > 0) {
          result = result.substring(end + 1).trimLeft();
          continue;
        }
      }
      if (result.startsWith('【')) {
        final end = result.indexOf('】');
        if (end > 0) {
          result = result.substring(end + 1).trimLeft();
          continue;
        }
      }
      break;
    }
    return result;
  }

  static String _stripTrailingTags(String name) {
    var result = name.trimRight();
    // 反复去掉结尾的 [...] / 【...】 / (...) / （...） 标签块
    result = result.replaceAll(
      RegExp(r'(?:\s*(?:\[[^\]]*\]|【[^】]*】|\([^)]*\)|（[^）]*）))+\s*$'),
      '',
    );
    return result.trim();
  }
}
