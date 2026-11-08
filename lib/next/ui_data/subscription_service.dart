part of 'service.dart';

Future<List<JsonMap>> localSubscriptionFacts(UiDataService ui) async {
  final rows = await SubscriptionStore(ui.db).display();
  final result = <JsonMap>[];
  for (final row in rows) {
    final workId = row['workId'] as String?;
    String? workTitle;
    if (workId != null) {
      final fields =
          (await ui.media.store.mergedMetadata(workId))['fields'] as JsonMap;
      workTitle = fields['title'] as String?;
    }
    result.add({
      for (final key in ['id', 'title', 'kind', 'workId', 'state', 'note'])
        key: row[key],
      if (workTitle != null) 'title': workTitle,
      'lastCheckedAt': row['lastCheckedAt'],
      'downloads': row['downloads'],
      'errors': row['errors'],
    });
  }
  return result;
}

Stream<List<UiSubscription>> subscriptionStream(UiDataService ui,
        {String? deviceId}) =>
    Stream.multi((controller) {
      var closed = false, running = false, dirty = false;
      Future<void> publish() async {
        if (closed) return;
        if (running) {
          dirty = true;
          return;
        }
        running = true;
        try {
          do {
            dirty = false;
            final own = ui.media.store.ownerDeviceId;
            final groups = <(String, String?, bool, List<JsonMap>)>[
              if (deviceId == null || deviceId == own)
                (own, null, true, await localSubscriptionFacts(ui)),
              for (final (id, name, online, rows)
                  in ui.meshLibrary?.peerSubscriptions ??
                      const <(String, String, bool, List<JsonMap>)>[])
                if (deviceId == null || deviceId == id)
                  (id, name, online, rows),
            ];
            final result = <UiSubscription>[];
            for (final (owner, name, online, rows) in groups) {
              for (final row in rows) {
                final workId = row['workId'] as String?;
                UiArtwork? art;
                if (workId != null) {
                  if (name == null) {
                    art = uiArtwork(await ui.artwork.cached(workId));
                  } else {
                    // The merged catalogue owns local artwork paths, never trust
                    // another device's absolute path as a path on this computer.
                    try {
                      art = (await ui.meshLibrary?.work(workId))?.artwork;
                    } on Failure {/* Metadata may not be projected yet. */}
                  }
                }
                result.add(UiSubscription(
                    id: row['id'] as String,
                    title: row['title'] as String,
                    state: UiSubscriptionState.values
                        .firstWhere((s) => s.name == row['state']),
                    deviceId: owner,
                    device: name,
                    online: online,
                    workId: workId,
                    artwork: art,
                    kind: row['kind'] as String? ?? 'series',
                    note: row['note'] as String? ?? '',
                    lastCheckedAt: DateTime.tryParse(
                        row['lastCheckedAt'] as String? ?? ''),
                    downloads: [
                      for (final d in row['downloads'] as List? ?? const [])
                        UiSubscriptionDownload(
                            jobId: d['jobId'] as String,
                            title: d['title'] as String,
                            episode: d['episode'] as String?)
                    ],
                    errors:
                        (row['errors'] as List? ?? const []).cast<String>()));
              }
            }
            if (!closed) controller.add(result);
          } while (dirty && !closed);
        } catch (e, s) {
          if (!closed) controller.addError(e, s);
        } finally {
          running = false;
        }
      }

      final sub = ui.changes
          .listen((_) => unawaited(publish()), onDone: controller.close);
      unawaited(publish());
      controller.onCancel = () {
        closed = true;
        return sub.cancel();
      };
    }, isBroadcast: true);
