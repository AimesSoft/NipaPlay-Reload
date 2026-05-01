import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/webdav_service.dart';

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
}
