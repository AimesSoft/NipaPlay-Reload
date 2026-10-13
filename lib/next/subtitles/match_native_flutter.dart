import 'package:nipaplay/src/rust/api/media_metadata.dart' as rust_metadata;
import 'package:nipaplay/src/rust/frb_generated.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

const subtitleIsWeb = kIsWeb;
Set<String>? nativeSubtitleMatchTokens(String name) {
  if (!RustLib.instance.initialized) return null;
  try {
    return rust_metadata.subtitleExtractMatchTokens(name: name).toSet();
  } catch (_) {
    return null;
  }
}

({String? value})? nativeSubtitleEpisodeNumber(List<String> numbers) {
  if (!RustLib.instance.initialized) return null;
  try {
    return (
      value: rust_metadata.subtitlePickLikelyEpisodeNumber(numbers: numbers)
    );
  } catch (_) {
    return null;
  }
}

String? nativeSubtitleMatchName(String name) {
  if (!RustLib.instance.initialized) return null;
  try {
    return rust_metadata.subtitleNormalizeMatchName(name: name);
  } catch (_) {
    return null;
  }
}

int? nativeSubtitleMatchScore(
    {required String videoName,
    required String subtitleName,
    required String extension,
    required List<String> videoNumbers,
    String? episodeNumber}) {
  if (!RustLib.instance.initialized) return null;
  try {
    return rust_metadata.subtitleComputeMatchScore(
        videoName: videoName,
        subtitleName: subtitleName,
        extension_: extension,
        videoNumbers: videoNumbers,
        episodeNumber: episodeNumber);
  } catch (_) {
    return null;
  }
}
