import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

/// Keep the latest detail attempt even when a later image/catalogue snapshot
/// updates fields. A newer partial detail attempt must not hide behind an old
/// successful one. This is acquisition evidence, not a completeness verdict.
JsonMap? preferredAcquisition(Object? first, Object? second) {
  final a = first is Map ? Map<String, Object?>.from(first) : null;
  final b = second is Map ? Map<String, Object?>.from(second) : null;
  if (a == null) return b;
  if (b == null) return a;
  if ((a['kind'] == 'detail') != (b['kind'] == 'detail')) {
    return a['kind'] == 'detail' ? a : b;
  }
  return '${a['fetchedAt']}'.compareTo('${b['fetchedAt']}') >= 0 ? a : b;
}

/// Identity and stored source coverage are independent of merged page fields.
/// No network request, title matching or cross-source episode inference here.
List<JsonMap> metadataSourceCoverage(
    List<JsonMap> identities, JsonMap metadata) {
  String key(Map ref) => jsonEncode([
        ref['provider'],
        ref['objectType'],
        ref['externalId'],
        ref['scope'] ?? ''
      ]);
  final sources = (metadata['sources'] as List? ?? const []).whereType<Map>();
  final refs = {for (final ref in identities) key(ref): ref};
  final result = <JsonMap>[];
  for (final entry in refs.entries) {
    final matches = sources.where((s) => key(s) == entry.key).toList();
    if (matches.isEmpty) {
      result.add({'ref': entry.value, 'state': 'identity_only'});
      continue;
    }
    for (final source in matches) {
      final acquisition = source['acquisition'] as Map?;
      final sections = acquisition?['sections'] as Map? ?? const {};
      final gaps = [
        for (final s in sections.entries)
          if (s.value != 'received') s.key
      ];
      final state = switch (acquisition?['kind']) {
        'detail' => sections.isEmpty || gaps.isNotEmpty
            ? 'detail_partial'
            : 'detail_fetched',
        'catalogue' => 'catalogue_only',
        'search' => 'search_only',
        _ => 'snapshot_unverified',
      };
      result.add({
        'ref': entry.value,
        'language': source['language'],
        'state': state,
        'storedFields': (source['fields'] as Map? ?? const {}).keys.toList(),
        if (acquisition != null) 'acquisition': acquisition,
        'unreceivedSections': gaps,
      });
    }
  }
  return result;
}
