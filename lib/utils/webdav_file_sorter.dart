import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show Int64List, Uint32List;
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';
import 'package:nipaplay/src/rust/api/remote_directory.dart'
    as rust_remote_directory;
import 'package:nipaplay/src/rust/frb_generated.dart';

class WebDAVFileSorter {
  const WebDAVFileSorter._();

  static const int rustBatchThreshold = 128;

  static void sort(List<WebDAVFile> files, WebDAVSortPreset preset) {
    files.sort((a, b) => compare(a, b, preset));
  }

  /// Uses one asynchronous Rust task for large directories. This avoids an
  /// FFI call for every comparator invocation while keeping small directories
  /// on the cheaper Dart path.
  static Future<void> sortAsync(
    List<WebDAVFile> files,
    WebDAVSortPreset preset,
  ) async {
    if (files.length < rustBatchThreshold || !RustLib.instance.initialized) {
      sort(files, preset);
      return;
    }

    try {
      final order = await rust_remote_directory.sortRemoteEntryIndices(
        names: files.map((file) => file.name).toList(growable: false),
        isDirectories:
            files.map((file) => file.isDirectory).toList(growable: false),
        sizes: Int64List.fromList(
          files.map((file) => file.size ?? 0).toList(growable: false),
        ),
        modifiedMillis: Int64List.fromList(
          files
              .map((file) => file.lastModified?.millisecondsSinceEpoch ?? 0)
              .toList(growable: false),
        ),
        preset: _rustPresetCode(preset),
      );
      if (_applyOrder(files, order)) return;
    } catch (_) {
      // Rust 运行时不可用或绑定异常时使用确定性的 Dart 回退。
    }

    sort(files, preset);
  }

  static int compare(
    WebDAVFile a,
    WebDAVFile b,
    WebDAVSortPreset preset,
  ) {
    return _compareWith(a, b, preset, naturalCompare);
  }

  static int _compareWith(
    WebDAVFile a,
    WebDAVFile b,
    WebDAVSortPreset preset,
    int Function(String, String) compareNames,
  ) {
    switch (preset) {
      case WebDAVSortPreset.defaultValue:
        if (a.isDirectory != b.isDirectory) {
          return a.isDirectory ? -1 : 1;
        }
        return compareNames(a.name, b.name);

      case WebDAVSortPreset.nameAsc:
        return compareNames(a.name, b.name);

      case WebDAVSortPreset.nameDesc:
        return compareNames(b.name, a.name);

      case WebDAVSortPreset.modifiedDesc:
        return _compareDateThenName(
          b.lastModified,
          a.lastModified,
          a,
          b,
          compareNames,
        );

      case WebDAVSortPreset.modifiedAsc:
        return _compareDateThenName(
          a.lastModified,
          b.lastModified,
          a,
          b,
          compareNames,
        );

      case WebDAVSortPreset.sizeDesc:
        return _compareNumberThenName(
          b.size ?? 0,
          a.size ?? 0,
          a,
          b,
          compareNames,
        );

      case WebDAVSortPreset.sizeAsc:
        return _compareNumberThenName(
          a.size ?? 0,
          b.size ?? 0,
          a,
          b,
          compareNames,
        );
    }
  }

  static int naturalCompare(String a, String b) {
    return _naturalCompareDart(a, b);
  }

  static int _naturalCompareDart(String a, String b) {
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
    int Function(String, String) compareNames,
  ) {
    final cmp = (first ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
      second ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
    return cmp != 0 ? cmp : compareNames(a.name, b.name);
  }

  static int _compareNumberThenName(
    int first,
    int second,
    WebDAVFile a,
    WebDAVFile b,
    int Function(String, String) compareNames,
  ) {
    final cmp = first.compareTo(second);
    return cmp != 0 ? cmp : compareNames(a.name, b.name);
  }

  static int _rustPresetCode(WebDAVSortPreset preset) => switch (preset) {
        WebDAVSortPreset.defaultValue => 0,
        WebDAVSortPreset.nameAsc => 1,
        WebDAVSortPreset.nameDesc => 2,
        WebDAVSortPreset.modifiedDesc => 3,
        WebDAVSortPreset.modifiedAsc => 4,
        WebDAVSortPreset.sizeDesc => 5,
        WebDAVSortPreset.sizeAsc => 6,
      };

  static bool _applyOrder(List<WebDAVFile> files, Uint32List order) {
    if (order.length != files.length) return false;
    final seen = List<bool>.filled(files.length, false);
    for (final index in order) {
      if (index >= files.length || seen[index]) return false;
      seen[index] = true;
    }

    final original = List<WebDAVFile>.of(files);
    for (var index = 0; index < order.length; index++) {
      files[index] = original[order[index]];
    }
    return true;
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
