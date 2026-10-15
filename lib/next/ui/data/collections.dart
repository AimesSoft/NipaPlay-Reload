import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

import 'gui_calls.dart';

/// Where a work stands with the person (在看、想看…) and their score, kept on
/// their 弹弹play and Bangumi accounts: `accounts.status`, the work's
/// identities (`state.query media.bindings`), `accounts.collections.*`.
final class NextCollections {
  NextCollections(this.calls);
  final GuiCalls calls;

  static const providers = ['bangumi', 'dandanplay'];

  final _changes = StreamController<void>.broadcast();

  /// Fires after a standing or score was set from here.
  Stream<void> get changes => _changes.stream;

  /// Whether the host can list works by standing
  /// (`accounts.collections.list`), signed in or not.
  Future<bool> lists() => calls.has('accounts.collections.list');

  /// The work's standing on each account it is known to.
  Future<UiCollection> of(String workId) async {
    final accounts = {
      for (final a in ((await calls.call('accounts.status', {}))['accounts']
              as List)
          .cast<Map>())
        '${a['provider']}': a['loggedIn'] == true
    };
    final ids = await _ids(workId);
    final links = <UiCollectionLink>[];
    for (final provider in providers) {
      final id = ids[provider];
      if (id == null) continue;
      if (accounts[provider] != true) {
        links.add(UiCollectionLink(provider: provider, id: id));
        continue;
      }
      try {
        final r = await calls.call('accounts.collections.get', {
          'provider': provider,
          'workIds': [id]
        });
        final row = (r['results'] as List).cast<Map>().single;
        if (row['status'] != 'completed') {
          links.add(UiCollectionLink(
              provider: provider, id: id, loggedIn: true, failed: true));
          continue;
        }
        links.add(UiCollectionLink.read(provider, id, row['result'] as Map));
      } on Failure {
        links.add(UiCollectionLink(
            provider: provider, id: id, loggedIn: true, failed: true));
      }
    }
    return UiCollection(workId: workId, links: links);
  }

  /// Sets the standing and/or score on every signed-in account that knows
  /// the work; the accounts that could not take it.
  Future<List<String>> set(UiCollection collection,
      {UiWatchStatus? status, int? rating}) async {
    final failed = <String>[];
    for (final link in collection.links) {
      if (!link.loggedIn) continue;
      final next = status ?? link.status;
      try {
        final r = await calls.call('accounts.collections.update', {
          'provider': link.provider,
          'items': [
            {
              'workId': link.id,
              if (next != null) 'status': next.on(link.provider),
              if (rating != null) 'rating': rating,
            }
          ]
        });
        if ((r['results'] as List).cast<Map>().single['status'] != 'completed') {
          failed.add(link.provider);
        }
      } on Failure {
        failed.add(link.provider);
      }
    }
    _changes.add(null);
    return failed;
  }

  /// Works of the library the person marked [status], in the account's
  /// order; null when no account is signed in. One account decides, as on
  /// the work's page: Bangumi keeps all five; 弹弹play's “following” would
  /// put 想看 and 搁置 under 在看.
  Future<List<String>?> works(UiWatchStatus status) async {
    final signedIn = {
      for (final a in ((await calls.call('accounts.status', {}))['accounts']
              as List)
          .cast<Map>())
        if (a['loggedIn'] == true) '${a['provider']}'
    };
    final provider = providers.where(signedIn.contains).firstOrNull;
    if (provider == null) return null;
    final values = status.all(provider);
    if (values.isEmpty) return const [];
    final found = <String>{};
    String? cursor;
    // A page the account filtered empty may still go on.
    do {
      final r = await calls.call('accounts.collections.list', {
        'provider': provider,
        'statuses': values,
        if (cursor != null) 'cursor': cursor,
      });
      found.addAll(await _entities(provider, [
        for (final item in (r['items'] as List).cast<Map>()) '${item['workId']}'
      ]));
      cursor = r['nextCursor'] as String?;
    } while (cursor != null);
    return found.toList();
  }

  /// The library's works bound to [ids] of [provider]'s works, in their
  /// order.
  Future<List<String>> _entities(String provider, List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = <Map>[];
    String? cursor;
    do {
      final r = await calls.call('state.query', {
        'view': 'media.bindings',
        'filter': {
          'provider': {'eq': provider},
          'objectType': {'in': _workTypes[provider]},
          'externalId': {'in': ids},
          'status': {'eq': 'accepted'},
        },
        'select': ['entityId', 'externalId'],
        'limit': 500,
        if (cursor != null) 'cursor': cursor,
      });
      rows.addAll((r['rows'] as List).cast<Map>());
      cursor = r['nextCursor'] as String?;
    } while (cursor != null);
    final order = {for (final (i, id) in ids.indexed) id: i};
    rows.sort((a, b) =>
        order['${a['externalId']}']!.compareTo(order['${b['externalId']}']!));
    return [for (final row in rows) '${row['entityId']}'];
  }

  /// What each account's work (not its episodes) is called in bindings.
  static const _workTypes = {
    'bangumi': ['subject'],
    'dandanplay': ['anime', 'work'],
  };

  Future<Map<String, int>> _ids(String workId) async {
    final r = await calls.call('state.query', {
      'view': 'media.bindings',
      'filter': {
        'entityId': {'eq': workId},
        'provider': {
          'in': providers,
        },
      },
      'select': ['provider', 'externalId', 'status'],
      'limit': 20,
    });
    final ids = <String, int>{};
    for (final row in (r['rows'] as List).cast<Map>()) {
      if (row['status'] == 'rejected') continue;
      final id = int.tryParse('${row['externalId']}');
      if (id != null && id > 0) ids.putIfAbsent('${row['provider']}', () => id);
    }
    return ids;
  }
}

/// 在看、想看、看过、搁置、抛弃.
enum UiWatchStatus {
  doing('在看'),
  wish('想看'),
  done('看过'),
  onHold('搁置'),
  dropped('抛弃');

  const UiWatchStatus(this.label);
  final String label;

  /// What the account calls it. 弹弹play keeps only following, finished and
  /// dropped: wanting to and putting aside are following there.
  String on(String provider) => provider == 'bangumi'
      ? name
      : switch (this) {
          done => 'finished',
          dropped => 'abandoned',
          _ => 'favorited',
        };

  /// Every account value that reads as this one.
  List<String> all(String provider) => provider == 'bangumi'
      ? [name]
      : switch (this) {
          doing => ['favorited'],
          done => ['finished'],
          dropped => ['abandoned'],
          _ => const [],
        };

  static UiWatchStatus? read(String provider, Object? value) =>
      switch ((provider, value)) {
        ('bangumi', 1 || 'wish') => wish,
        ('bangumi', 2 || 'done') => done,
        ('bangumi', 3 || 'doing') => doing,
        ('bangumi', 4 || 'onHold') => onHold,
        ('bangumi', 5 || 'dropped') => dropped,
        (_, 'favorited') => doing,
        (_, 'finished') => done,
        (_, 'abandoned') => dropped,
        _ => null,
      };
}

final class UiCollection {
  const UiCollection({required this.workId, this.links = const []});
  final String workId;

  /// Each account the work is known to.
  final List<UiCollectionLink> links;

  bool get signedIn => links.any((l) => l.loggedIn);

  /// What it says, Bangumi first (it keeps all five).
  UiWatchStatus? get status => links
      .where((l) => l.loggedIn)
      .map((l) => l.status)
      .whereType<UiWatchStatus>()
      .firstOrNull;
  int? get rating => links
      .where((l) => l.loggedIn)
      .map((l) => l.rating)
      .whereType<int>()
      .firstOrNull;
}

final class UiCollectionLink {
  const UiCollectionLink({
    required this.provider,
    required this.id,
    this.loggedIn = false,
    this.status,
    this.rating,
    this.failed = false,
  });

  final String provider;

  /// The work on that account (弹弹play's animeId, Bangumi's subject).
  final int id;
  final bool loggedIn;
  final UiWatchStatus? status;
  final int? rating;

  /// Could not be read just now.
  final bool failed;

  String get name => provider == 'bangumi' ? 'Bangumi' : '弹弹play';

  factory UiCollectionLink.read(String provider, int id, Map result) {
    final c = result['collection'];
    final collection = c is Map ? c : null;
    final Object? rate = provider == 'bangumi'
        ? (collection == null ? null : collection['rate'])
        : (result['rating'] ?? (collection == null ? null : collection['rating']));
    final rating = rate is num && rate > 0 ? rate.toInt() : null;
    return UiCollectionLink(
      provider: provider,
      id: id,
      loggedIn: true,
      status: collection == null
          ? null
          : UiWatchStatus.read(
              provider,
              provider == 'bangumi'
                  ? collection['type']
                  : collection['favoriteStatus']),
      rating: rating,
    );
  }
}
