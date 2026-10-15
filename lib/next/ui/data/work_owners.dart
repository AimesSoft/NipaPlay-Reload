import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';

import 'work_manage.dart';

/// Where works are: per merged work ID, the devices that have it with their
/// own IDs for it (`media.management.targets`) and the names their hosts
/// gave them (`state.query` `mesh.devices`), or the error the targets gave
/// for it. [call] runs an Action on this device.
Future<Map<String, ({List<WorkOwner> owners, Map? error})>> readWorkOwners(
    Future<JsonMap> Function(String action, JsonMap input) call,
    List<String> workIds) async {
  List<Map> maps(Object? v) =>
      v is List ? v.whereType<Map>().toList() : const [];
  final result = await call('media.management.targets', {'workIds': workIds});
  final entries = maps(result['entries']);
  final remote = {
    for (final e in entries)
      for (final t in maps(e['targets']))
        if (t['local'] != true) t['deviceId'] as String
  }.toList();
  final devices = <Object?, Map>{};
  if (remote.isNotEmpty) {
    final rows = await call('state.query', {
      'view': 'mesh.devices',
      'filter': {
        'deviceId': {'in': remote}
      },
      'select': ['deviceId', 'name', 'platform'],
    });
    for (final row in maps(rows['rows'])) {
      devices[row['deviceId']] = row;
    }
  }
  return {
    for (final e in entries)
      e['workId'] as String: (
        owners: [
          for (final t in maps(e['targets']))
            WorkOwner(t, devices[t['deviceId']])
        ],
        error: e['error'] as Map?,
      )
  };
}

/// A device that has the work, with its own IDs for it.
final class WorkOwner {
  WorkOwner(Map target, Map? device)
      : deviceId = target['deviceId'] as String,
        workId = target['workId'] as String,
        local = target['local'] == true,
        name = target['local'] == true
            ? null
            : device?['name'] as String? ?? '另一台设备',
        manager = UiFileManager.of(target['local'] == true
            ? Platform.operatingSystem
            : device?['platform']),
        away = uiAway(
            Map<String, Object?>.from(target), device?['name'] as String?),
        episodes = {
          for (final e in (target['episodes'] as List).cast<Map>())
            if (e['mergedEpisodeId'] case final String merged)
              e['episodeId'] as String: merged
        };

  final String deviceId;

  /// Its own work.
  final String workId;
  final bool local;

  /// As its host named it; null for this device.
  final String? name;
  final UiFileManager? manager;

  /// Why it cannot be asked now, as said; null when it can.
  final String? away;

  /// Its own episodes, to the merged ones they are.
  final Map<String, String> episodes;

  /// Its own episode for the merged [episodeId].
  String? episode(String episodeId) => [
        for (final e in episodes.entries)
          if (e.value == episodeId) e.key
      ].firstOrNull;
}
