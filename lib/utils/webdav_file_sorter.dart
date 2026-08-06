import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/src/rust/api/media_metadata.dart' as rust_metadata;
import 'package:nipaplay/src/rust/frb_generated.dart';

class WebDAVFileSorter {
  const WebDAVFileSorter._();

  static void sort(List<WebDAVFile> files, WebDAVSortPreset preset) {
    files.sort((a, b) => compare(a, b, preset));
  }

  static int compare(
    WebDAVFile a,
    WebDAVFile b,
    WebDAVSortPreset preset,
  ) {
    switch (preset) {
      case WebDAVSortPreset.defaultValue:
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return naturalCompare(a.name, b.name);

      case WebDAVSortPreset.nameAsc:
        return naturalCompare(a.name, b.name);

      case WebDAVSortPreset.nameDesc:
        return naturalCompare(b.name, a.name);

      case WebDAVSortPreset.modifiedDesc:
        return _compareDateThenName(
          b.lastModified,
          a.lastModified,
          a,
          b,
        );

      case WebDAVSortPreset.modifiedAsc:
        return _compareDateThenName(
          a.lastModified,
          b.lastModified,
          a,
          b,
        );

      case WebDAVSortPreset.sizeDesc:
        return _compareNumberThenName(
          b.size ?? 0,
          a.size ?? 0,
          a,
          b,
        );

      case WebDAVSortPreset.sizeAsc:
        return _compareNumberThenName(
          a.size ?? 0,
          b.size ?? 0,
          a,
          b,
        );
    }
  }

  static int naturalCompare(String a, String b) {
    if (RustLib.instance.initialized) {
      try {
        return rust_metadata.naturalCompare(a: a, b: b);
      } catch (_) {
        // 使用下方 Dart/Web fallback。
      }
    }
    final aParts = _tokenize(a);
    final bParts = _tokenize(b);
    final minLength =
        aParts.length < bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < minLength; i++) {
      final aPart = aParts[i];
      final bPart = bParts[i];

      final aNum = int.tryParse(aPart);
      final bNum = int.tryParse(bPart);
      if (aNum != null && bNum != null) {
        final cmp = aNum.compareTo(bNum);
        if (cmp != 0) return cmp;
        final lengthCmp = aPart.length.compareTo(bPart.length);
        if (lengthCmp != 0) return lengthCmp;
      } else {
        final cmp = aPart.toLowerCase().compareTo(bPart.toLowerCase());
        if (cmp != 0) return cmp;
      }
    }

    return aParts.length.compareTo(bParts.length);
  }

  /// Compares media names by their explicit episode token before falling back
  /// to the general natural sort. This prevents technical metadata such as
  /// `Ma10p`, `1080p`, or `x265` from being mistaken for the episode number.
  static int playlistCompare(String a, String b) {
    final aKey = _episodeSortKey(a);
    final bKey = _episodeSortKey(b);
    if (aKey != null && bKey != null && aKey.seriesKey == bKey.seriesKey) {
      final episodeCompare = aKey.episode.compareTo(bKey.episode);
      if (episodeCompare != 0) return episodeCompare;
    }
    return naturalCompare(a, b);
  }

  static int _compareDateThenName(
    DateTime? first,
    DateTime? second,
    WebDAVFile a,
    WebDAVFile b,
  ) {
    final cmp = (first ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      second ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    return cmp != 0 ? cmp : naturalCompare(a.name, b.name);
  }

  static int _compareNumberThenName(
    int first,
    int second,
    WebDAVFile a,
    WebDAVFile b,
  ) {
    final cmp = first.compareTo(second);
    return cmp != 0 ? cmp : naturalCompare(a.name, b.name);
  }

  static List<String> _tokenize(String value) {
    final matches = RegExp(r'(\d+)|(\D+)').allMatches(value);
    return matches.map((match) => match.group(0) ?? '').toList();
  }

  static _EpisodeSortKey? _episodeSortKey(String value) {
    final baseName = value
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceFirst(RegExp(r'\.[^.]+$'), '');

    final patterns = <RegExp>[
      RegExp(
        r'\bS\d{1,2}[ ._-]*E(?:P)?[ ._-]*(\d{1,4}(?:\.\d+)?)\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:EP?|Episode)[ ._-]*(\d{1,4}(?:\.\d+)?)\b',
        caseSensitive: false,
      ),
      RegExp(r'第\s*(\d{1,4}(?:\.\d+)?)\s*[话話集期]'),
      RegExp(r'[\[【(（]\s*(\d{1,4}(?:\.\d+)?)\s*[\]】)）]'),
      RegExp(r'(?:^|[\s._-])(\d{1,4}(?:\.\d+)?)(?=\s*(?:[\[【(（]|$))'),
    ];

    for (final pattern in patterns) {
      final matches = pattern.allMatches(baseName).toList();
      if (matches.isEmpty) continue;
      // The last pure numeric tag is normally the episode tag; leading tags
      // can contain a release year or a group version.
      final match = matches.last;
      final episode = double.tryParse(match.group(1) ?? '');
      if (episode == null) continue;
      final seriesKey = baseName
          .substring(0, match.start)
          .toLowerCase()
          .replaceAll(RegExp(r'[\s._-]+'), ' ')
          .trim();
      return _EpisodeSortKey(seriesKey, episode);
    }
    return null;
  }
}

class _EpisodeSortKey {
  const _EpisodeSortKey(this.seriesKey, this.episode);

  final String seriesKey;
  final double episode;
}
