import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

final class FilenameSignals implements JsonEncodable {
  const FilenameSignals(
      {required this.raw,
      required this.title,
      this.year,
      this.season,
      this.cour,
      this.number,
      this.endNumber,
      this.releaseGroup,
      this.version,
      this.episodeType = 'regular',
      required this.technical});
  final String raw, title, episodeType;
  final String? number, endNumber, releaseGroup, version;
  final int? year, season, cour;
  final List<String> technical;
  @override
  JsonMap toJson() => {
        'raw': raw,
        'title': title,
        'year': year,
        'season': season,
        'cour': cour,
        'number': number,
        'endNumber': endNumber,
        'episodeType': episodeType,
        'releaseGroup': releaseGroup,
        'version': version,
        'technical': technical,
        'parserVersion': 'rules-2'
      };
}

abstract interface class FilenameParserPort {
  FilenameSignals parse(String path);
}

final class RuleFilenameParser implements FilenameParserPort {
  const RuleFilenameParser();
  static const numberPattern =
      r'\d+(?:\.(?!(?:4320|2160|1440|1080|720|576|480)(?:[pi]?\b))\d+(?![\dA-Za-z]))?(?![\dA-Za-z])';
  @override
  FilenameSignals parse(String path) {
    final raw = p.basename(path);
    var title = p.basenameWithoutExtension(path);
    final group = RegExp(r'^\[([^\]]+)\]').firstMatch(title);
    final technical = RegExp(
            r'\b(?:\d{3,4}[pi]|[48]K|WEB[- .]?DL|WEBRip|BluRay|HEVC|AVC|x26[45]|H[ .]?26[45]|AAC|FLAC|HDR(?:10)?|DV)\b',
            caseSensitive: false)
        .allMatches(title)
        .map((m) => m[0]!)
        .toList();
    final year = RegExp(r'(?:^|[\s.\[(])((?:19|20)\d{2})(?=$|[\s.\])])')
        .firstMatch(title);
    final se = RegExp(
            r'(?:^|[\s._\[-])S(\d+)\s*E(' +
                numberPattern +
                r')(?:\s*[-~]\s*(?:E)?(' +
                numberPattern +
                r'))?',
            caseSensitive: false)
        .firstMatch(title);
    final explicit = se ??
        RegExp(
                r'(?:\s[-_]\s|\bEP?\s*|第)(' +
                    numberPattern +
                    r')(?:\s*[-~]\s*(' +
                    numberPattern +
                    r'))?(?:[话話集]|\b)',
                caseSensitive: false)
            .firstMatch(title);
    final special = RegExp(
            r'\b(SP|OVA|OAD|NCOP|NCED)(?=$|[\s_.-]|\d)(?:\s*[-_.]?\s*(' +
                numberPattern +
                r'))?',
            caseSensitive: false)
        .firstMatch(title);
    final part = RegExp(r'\b(?:Part|Cour)\s*(\d+)', caseSensitive: false)
        .firstMatch(title);
    final version = RegExp(r'\bv\d+\b', caseSensitive: false).firstMatch(title);
    final number = se != null
        ? se[2]
        : special != null
            ? special[2]
            : explicit?[1];
    final end = se != null ? se[3] : explicit?[2];
    final marker = se ?? special ?? explicit;
    if (marker != null) title = title.substring(0, marker.start);
    if (part != null && part.start < title.length) {
      title = title.substring(0, part.start);
    }
    title =
        title.replaceAll(RegExp(r'\[[^\]]*\]|\((?:19|20)\d{2}\)'), '').trim();
    title = title.replaceAll(RegExp(r'[ ._-]+$'), '').replaceAll('_', ' ');
    return FilenameSignals(
        raw: raw,
        title: title,
        year: year == null ? null : int.parse(year[1]!),
        season: se == null ? null : int.parse(se[1]!),
        cour: part == null ? null : int.parse(part[1]!),
        number: number,
        endNumber: end,
        episodeType: se != null || special == null
            ? 'regular'
            : special[1]!.toLowerCase(),
        releaseGroup: group?[1],
        version: version?[0],
        technical: technical);
  }
}
