import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:nipa_harness/nipa_harness.dart';

import '../../ui_data/ui_data.dart';
import 'gui_calls.dart' show failureOf;
import 'work_manage.dart';
import 'work_owners.dart';

typedef _Owner = WorkOwner;

/// [NextWorkManage] through the harness, as the person (`origin: gui`).
///
/// The interface knows works and episodes by their merged library IDs;
/// media Actions take each device's own. `media.management.targets` names
/// the devices that have a work and their own work, episode and file IDs:
/// this device's are asked directly, another's through `mesh.invoke`, so
/// every check and question happens where the work is. Nothing is
/// inferred from names.
final class CoreWorkManage implements NextWorkManage {
  CoreWorkManage(this.harness, this.data);

  /// The runtime's, read at each call (it may come later).
  final Harness Function() harness;
  final NextUiData data;

  Invocation get _gui => Invocation(origin: 'gui');

  Future<Outcome<JsonEncodable>> _invoke(String action, JsonMap input) =>
      harness().invokeJson(action, input, _gui);

  /// [action] where [owner] is: here directly (also when null), on
  /// another device through `mesh.invoke` with its own IDs.
  Future<Outcome<JsonEncodable>> _on(
          _Owner? owner, String action, JsonMap input,
          {bool destructive = false}) =>
      owner == null || owner.local
          ? _invoke(action, input)
          : _invoke(destructive ? 'mesh.invoke_destructive' : 'mesh.invoke', {
              'deviceId': owner.deviceId,
              'action': action,
              'input': input,
            });

  Future<JsonMap> _call(String action, JsonMap input) =>
      _callOn(null, action, input);

  Future<JsonMap> _callOn(_Owner? owner, String action, JsonMap input) async =>
      switch (await _on(owner, action, input)) {
        Completed(:final value) => value.toJson(),
        Failed(:final failure) => throw _error(failure),
        NeedsDecision() =>
          throw const UiManageError(message: 'asked for a decision'),
      };

  static UiManageError _error(Failure failure) => UiManageError(
      conflict: failure.code == FailureCode.conflict,
      message: failure.message);

  /// Batch outcomes report each entry; any that failed fails the whole.
  static void _entries(JsonMap result, String key) {
    for (final e in _maps(result[key])) {
      final error = e['error'];
      if (e['status'] == 'failed' || e['saved'] == false || error is Map) {
        throw UiManageError(
            conflict: error is Map && error['code'] == 'conflict',
            message: error is Map ? '${error['message']}' : null);
      }
    }
  }

  static final _random = math.Random.secure();
  static String _id(String prefix) =>
      '$prefix-${List.generate(12, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  static List<Map> _maps(Object? v) =>
      v is List ? v.whereType<Map>().toList() : const [];
  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  static int? _int(Object? v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);

  static const _providers = {
    'dandanplay': UiProvider.dandanplay,
    'tmdb': UiProvider.tmdb,
    'bangumi': UiProvider.bangumi,
  };

  // —— Where a work is ——

  /// The devices that have [workId], each with its own IDs for it
  /// (`media.management.targets`) and the name its host gave it
  /// (`state.query` `mesh.devices`).
  Future<List<_Owner>> _owners(String workId) async {
    final found = (await readWorkOwners(_call, [workId]))[workId]!;
    if (found.error case final Map error) {
      throw UiManageError(message: '${error['message']}');
    }
    return found.owners;
  }

  /// Every place a file of [owner]'s work is (`media.files.list`).
  Future<List<Map>> _listed(_Owner owner) async => _maps((await _callOn(
      owner, 'media.files.list', {'workId': owner.workId}))['files']);

  /// The owner's own episodes a listed file is.
  static Iterable<String> _episodesOf(Map row) =>
      [for (final e in _maps(row['episodes'])) e['episodeId'] as String];

  static UiFile _file(_Owner owner, Map row) => UiFile.listed(
        Map<String, Object?>.from(row),
        device: owner.name,
        manager: owner.manager,
        handle: _FileRef(owner, row['fileId'] as String),
      );

  /// What another device changed reaches the merged library now, not at
  /// its next look (`media.library.refresh`).
  Future<void> _settle(Iterable<_Owner> owners) async {
    if (owners.any((o) => !o.local)) await _call('media.library.refresh', {});
  }

  // —— Reading a work ——

  Future<JsonMap?> _identity(_Owner? owner, String entityId) async {
    final outcome =
        await _on(owner, 'media.identity.get', {'entityId': entityId});
    return switch (outcome) {
      Completed(:final value) => value.toJson()['identity'] as JsonMap,
      Failed(failure: Failure(code: FailureCode.notFound)) => null,
      Failed(:final failure) => throw _error(failure),
      NeedsDecision() => null,
    };
  }

  static List<Map> _accepted(JsonMap identity) => [
        for (final b in _maps(identity['bindings']))
          if (b['status'] == 'accepted') b
      ];

  /// Whether the catalogue would remove it as its own: a local work.
  Future<bool> _isLocal(_Owner owner) async {
    final outcome = await _on(owner, 'media.entities.remove_batch', {
      'entityIds': [owner.workId],
      'requestId': _id('gui-preview'),
      'reason': 'Viewer opened the work sheet.',
      'preview': true,
    });
    return outcome is Completed;
  }

  static UiText _textFact(Object? fact) {
    final f = fact is Map ? fact : const {};
    final source = f['source'];
    final value = f['value'];
    return UiText(value is String ? value : null,
        edited: source is Map && source.containsKey('mode'));
  }

  static UiArt _artFact(Object? fact) {
    final f = fact is Map ? fact : const {};
    final source = f['source'];
    return UiArt(f['path'] as String?,
        edited: source is Map && source['edit'] != null);
  }

  @override
  Future<UiManagedWork> work(UiWork work) async {
    final facts = (await _call('media.metadata.ui_facts', {
      'workId': work.workId
    }));
    final fields = facts['fields'] as Map;
    final items = _maps((facts['episodes'] as Map)['items']);
    final shown = {
      for (final e in await data.episodes(work.workId)) e.episodeId: e
    };
    final owners = await _owners(work.workId);
    final away = [
      for (final o in owners)
        if (o.away case final reason?) reason
    ];
    final reachable = [
      for (final o in owners)
        if (o.away == null) o
    ];
    final primary =
        reachable.where((o) => o.local).firstOrNull ?? reachable.firstOrNull;
    if (primary == null) {
      if (away.isEmpty) throw const UiManageError(message: 'no device has it');
      return UiManagedWork(
          work: work,
          kind: UiWorkKind.loose,
          away: away,
          unavailable: away.first);
    }

    final bindings = <_Owner, List<Map>>{};
    final listed = <_Owner, List<Map>>{};
    for (final o in [primary, ...reachable.where((o) => o != primary)]) {
      final identity = await _identity(o, o.workId);
      bindings[o] = identity == null ? const [] : _accepted(identity);
      listed[o] = await _listed(o);
    }
    final provider = [
      for (final b in bindings[primary]!)
        if (_providers[(b['ref'] as Map)['provider']] case final p?) (p, b)
    ].firstOrNull;
    final kind = provider != null
        ? UiWorkKind.matched
        : await _isLocal(primary)
            ? UiWorkKind.local
            : UiWorkKind.loose;

    final episodes = <UiManagedEpisode>[];
    for (final item in items) {
      final id = item['episodeId'] as String;
      final own = <_Owner, String>{};
      final files = <UiFile>[];
      for (final MapEntry(key: o, value: rows) in listed.entries) {
        final seen = <String>{};
        for (final row in rows) {
          final local =
              _episodesOf(row).where((e) => o.episodes[e] == id).firstOrNull;
          if (local == null || !seen.add(row['fileId'] as String)) continue;
          own[o] = local;
          files.add(_file(o, row));
        }
      }
      if (files.isEmpty) continue;
      final title = item['title'] as Map?;
      episodes.add(UiManagedEpisode(
        episode: shown[id],
        number: '${item['number'] ?? ''}',
        season: _int(item['season']),
        title: title?['value'] as String?,
        titleEdited:
            title?['source'] is Map && (title!['source'] as Map).containsKey('mode'),
        files: files,
        handle: _EpisodeRef(id, own),
      ));
    }

    return UiManagedWork(
      work: work,
      kind: kind,
      metadata: Map<String, Object?>.from(facts['metadata'] as Map? ?? const {}),
      match: provider == null
          ? null
          : UiMatch(
              provider: provider.$1,
              title: _textFact(fields['title']).value ?? work.title,
              year: work.year,
              image: work.artwork.poster,
              candidate: UiMatchCandidate(
                provider: provider.$1,
                title: work.title,
                ref: Map<String, Object?>.from(provider.$2['ref'] as Map),
                current: true,
              ),
            ),
      text: {
        UiTextField.title: _textFact(fields['title']),
        UiTextField.originalTitle: _textFact(fields['originalTitle']),
        UiTextField.overview: _textFact(fields['overview']),
      },
      art: {
        UiArtKind.backdrop: _artFact(fields['backdrop']),
        UiArtKind.poster: _artFact(fields['poster']),
        UiArtKind.logo: _artFact(fields['logo']),
      },
      episodes: episodes,
      device: primary.name,
      away: away,
      handle: _WorkRef(primary, bindings),
    );
  }

  /// Where files picked on this device can go: the work's part here.
  static _Owner _here(UiManagedWork work) {
    final primary = (work.handle as _WorkRef).primary;
    if (!primary.local) {
      throw const UiManageError(message: 'not on this device');
    }
    return primary;
  }

  // —— 匹配 ——

  @override
  Future<List<UiMatchCandidate>> search(
      UiProvider provider, String query) async {
    final result = await _call('media.metadata.search',
        {'provider': provider.name, 'query': query});
    return [
      for (final r in _maps(result['results']))
        if (_text(r['title']) case final title?)
          UiMatchCandidate(
            provider: provider,
            title: title,
            ref: Map<String, Object?>.from(r['ref'] as Map),
            originalTitle: _text(r['originalTitle']),
            year: _int(r['year']),
            image: _text(r['imageUrl']),
            movie: r['kind'] == 'movie',
            elsewhere: r['workId'] != null,
          )
    ];
  }

  @override
  Future<List<UiCandidateEpisode>> candidateEpisodes(
      UiMatchCandidate candidate) async {
    try {
      return await readCandidateEpisodes(_call, candidate.ref);
    } on Failure catch (failure) {
      throw _error(failure);
    }
  }

  /// [owner]'s files linked to episodes of another identity, to be let go
  /// of first: the catalogue refuses to relink them silently.
  Future<JsonMap?> _letGo(
      _Owner owner, Iterable<UiFile> files, String reason) async {
    final entries = <JsonMap>[];
    for (final file in files) {
      final id = (file.handle as _FileRef).fileId;
      final identity = await _identity(owner, id);
      if (identity == null) continue;
      final accepted = _accepted(identity);
      if (accepted.isEmpty) continue;
      entries.add({
        'entityId': id,
        'reason': reason,
        'bindingIds': [for (final b in accepted) b['bindingId']],
      });
    }
    return entries.isEmpty
        ? null
        : {'requestId': _id('gui-unbind'), 'entries': entries};
  }

  /// One device's part, previewed without a plan.
  Future<_Plan> _plan(_Owner owner, {JsonMap? unbind, JsonMap? bind}) async =>
      _Plan(
        owner,
        unbind: unbind,
        bind: bind,
        unbound: unbind == null
            ? null
            : await _callOn(owner, 'media.management.unbind_batch', unbind),
        bound: bind == null
            ? null
            : await _callOn(owner, 'media.management.bind_batch', bind),
      );

  /// Does [plan] as previewed. A binding after a release is previewed
  /// again: the release is what it waited for.
  Future<void> _apply(_Plan plan) async {
    if (plan.unbind case final input?) {
      await _callOn(plan.owner, 'media.management.unbind_batch',
          {...input, 'expectedPlan': plan.unbound!['expectedPlan']});
    }
    if (plan.bind case final input?) {
      final preview = plan.unbind == null
          ? plan.bound!
          : await _callOn(plan.owner, 'media.management.bind_batch', input);
      await _callOn(plan.owner, 'media.management.bind_batch',
          {...input, 'expectedPlan': preview['expectedPlan']});
    }
  }

  UiAssociation _association(List<_Plan> plans) => UiAssociation.fromPreviews(
        [
          for (final p in plans)
            for (final preview in [p.unbound, p.bound])
              if (preview != null)
                Map<String, Object?>.from(preview['preview'] as Map)
        ],
        devices: [for (final p in plans) p.owner.name],
        apply: () async {
          for (final p in plans) {
            await _apply(p);
          }
          await _settle([for (final p in plans) p.owner]);
        },
      );

  @override
  Future<UiAssociation> previewMatch(UiManagedWork work,
      UiMatchCandidate candidate, Map<UiFile, UiCandidateEpisode> files) async {
    if (files.isEmpty) throw const UiManageError(message: 'no files');
    const reason = 'Viewer matched the work in its sheet.';
    final byOwner = <_Owner, Map<UiFile, UiCandidateEpisode>>{};
    for (final MapEntry(key: file, value: episode) in files.entries) {
      (byOwner[(file.handle as _FileRef).owner] ??= {})[file] = episode;
    }
    return _association([
      for (final MapEntry(key: owner, value: chosen) in byOwner.entries)
        await _plan(owner,
            unbind: await _letGo(owner, chosen.keys, reason),
            bind: {
              'requestId': _id('gui-bind'),
              'entries': [
                for (final MapEntry(key: file, value: episode)
                    in chosen.entries)
                  {
                    'kind': 'file',
                    'reason': reason,
                    'entityId': (file.handle as _FileRef).fileId,
                    'workRef': candidate.ref,
                    if (episode.release != null) 'releaseRef': episode.release,
                    'episodeRefs': [episode.ref],
                  }
              ],
            })
    ]);
  }

  @override
  Future<UiAssociation> previewUnmatch(UiManagedWork work) async {
    final ref = work.handle as _WorkRef;
    final plans = [
      for (final MapEntry(key: owner, value: bindings) in ref.bindings.entries)
        if (bindings.isNotEmpty)
          await _plan(owner, unbind: {
            'requestId': _id('gui-unbind'),
            'entries': [
              {
                'entityId': owner.workId,
                'reason': 'Viewer let go of the match in the work sheet.',
                'bindingIds': [for (final b in bindings) b['bindingId']],
              }
            ],
          })
    ];
    if (plans.isEmpty) throw const UiManageError(message: 'no match');
    return _association(plans);
  }

  // —— 本地作品 ——

  @override
  Future<String> createLocal(UiManagedWork from, String title) async {
    const reason = 'Viewer made a work of its own.';
    final owner = _here(from);
    // Each episode as it is, with its files here: a file on another
    // device is in that device's catalogue, not this one's.
    final episodes = [
      for (final e in from.episodes)
        if ([
          for (final f in e.files)
            if ((f.handle as _FileRef).owner == owner) f
        ]
            case final files when files.isNotEmpty)
          (e, files)
    ];
    final files = {
      for (final (_, files) in episodes)
        for (final f in files) (f.handle as _FileRef).fileId: f
    };
    if (await _letGo(owner, files.values, reason) case final release?) {
      await _call('media.identity.unbind_batch', release);
    }
    final work = _id('local-work'), release = _id('local-release');
    await _call('media.entities.put_batch', {
      'requestId': _id('gui-put'),
      'reason': reason,
      'entries': [
        {'entityId': work, 'kind': 'work', 'title': title},
        {
          'entityId': release,
          'kind': 'release',
          'parentId': work,
          'title': title
        },
        for (final (e, files) in episodes)
          {
            'entityId': _id('local-episode'),
            'kind': 'episode',
            'parentId': release,
            'title': _text(e.title) ??
                _text(files.first.name.replaceFirst(RegExp(r'\.[^.]+$'), '')) ??
                title,
            if (_text(e.number) case final number?) 'number': number,
            if (e.season != null) 'season': e.season,
            'fileIds': [for (final f in files) (f.handle as _FileRef).fileId],
          }
      ],
    });
    return work;
  }

  /// Puts entries in two steps: the preview's plan, then the change.
  Future<JsonMap> _put(
      _Owner owner, List<JsonMap> entries, String reason) async {
    final requestId = _id('gui-put');
    final preview = await _callOn(owner, 'media.entities.put_batch', {
      'requestId': requestId,
      'reason': reason,
      'entries': entries,
      'preview': true,
    });
    final result = await _callOn(owner, 'media.entities.put_batch', {
      'requestId': requestId,
      'reason': reason,
      'entries': entries,
      if (preview['expectedPlan'] != null)
        'expectedPlan': preview['expectedPlan'],
    });
    await _settle([owner]);
    return result;
  }

  /// The release local episodes hang from, made when the work has none.
  Future<String> _release(
      _Owner owner, UiManagedWork work, List<JsonMap> entries) async {
    for (final e in work.episodes) {
      final local = (e.handle as _EpisodeRef).own[owner];
      if (local == null) continue;
      final parent = (await _identity(owner, local))?['parentId'] as String?;
      if (parent != null) return parent;
    }
    final release = _id('local-release');
    entries.add({
      'entityId': release,
      'kind': 'release',
      'parentId': owner.workId,
      'title': work.work.title,
    });
    return release;
  }

  @override
  Future<void> saveLocal(
      UiManagedWork work, List<UiLocalEpisodeEdit> edits) async {
    final owner = (work.handle as _WorkRef).primary;
    final entries = <JsonMap>[];
    final release = await _release(owner, work, entries);
    for (final edit in edits) {
      final local = (edit.handle as _EpisodeRef?)?.own[owner];
      final identity = local == null ? null : await _identity(owner, local);
      entries.add({
        'entityId': local ?? _id('local-episode'),
        'kind': 'episode',
        'parentId': identity?['parentId'] ?? release,
        'title': edit.title ?? edit.number,
        'number': edit.number,
        if (edit.season != null) 'season': edit.season,
        'fileIds': [
          for (final f in edit.files)
            if ((f.handle as _FileRef) case final ref when ref.owner == owner)
              ref.fileId
        ],
        if (identity != null) 'expectedRevision': identity['revision'],
      });
    }
    await _put(
        owner, entries, 'Viewer edited the episodes of a work of its own.');
  }

  @override
  Future<void> addFile(UiManagedWork work, String path) async {
    final owner = _here(work);
    final outcome = await _invoke('media.identity.get', {'path': path});
    final file = switch (outcome) {
      Completed(:final value) => value.toJson()['identity'] as JsonMap,
      Failed(:final failure) => throw _error(failure),
      NeedsDecision() => throw const UiManageError(),
    };
    final entries = <JsonMap>[];
    final release = await _release(owner, work, entries);
    final numbers = [for (final e in work.episodes) int.tryParse(e.number) ?? 0];
    final next = numbers.isEmpty ? 1 : numbers.reduce(math.max) + 1;
    entries.add({
      'entityId': _id('local-episode'),
      'kind': 'episode',
      'parentId': release,
      'title': path
          .split(RegExp(r'[\\/]'))
          .last
          .replaceFirst(RegExp(r'\.[^.]+$'), ''),
      'number': '$next',
      'fileIds': [file['id']],
    });
    await _put(owner, entries, 'Viewer added a file to a work of its own.');
  }

  @override
  Future<UiUndo> removeLocal(UiManagedWork work,
      {UiManagedEpisode? episode}) async {
    final owner = (work.handle as _WorkRef).primary;
    final id = episode == null
        ? owner.workId
        : (episode.handle as _EpisodeRef).own[owner]!;
    const reason = 'Viewer removed it from the catalogue.';
    final requestId = _id('gui-remove');
    final preview = await _callOn(owner, 'media.entities.remove_batch', {
      'entityIds': [id],
      'requestId': requestId,
      'reason': reason,
      'preview': true,
    });
    final result = await _callOn(owner, 'media.entities.remove_batch', {
      'entityIds': [id],
      'requestId': requestId,
      'reason': reason,
      'preview': false,
      'expectedPlan': preview['expectedPlan'],
    });
    await _settle([owner]);
    return UiUndo((owner, result['undoId'] as String));
  }

  @override
  Future<void> restore(UiUndo undo) async {
    final (owner, undoId) = undo.handle as (_Owner, String);
    await _callOn(owner, 'media.entities.restore', {'undoId': undoId});
    await _settle([owner]);
  }

  // —— 资料与图片 ——
  //
  // Words and matches are the work's wherever it is: every device that
  // answers gets the same change. Pictures picked here stay here.

  @override
  Future<void> editText(
      UiManagedWork work, Map<UiTextField, String?> values) async {
    if (values.isEmpty) return;
    final owners = (work.handle as _WorkRef).owners;
    for (final o in owners) {
      await _callOn(o, 'media.metadata.override_batch', {
        'entries': [
          for (final MapEntry(key: field, value: value) in values.entries)
            {'entityId': o.workId, 'field': field.name, 'value': value}
        ]
      });
    }
    await _settle(owners);
  }

  @override
  Future<void> editEpisodeTitles(Map<UiManagedEpisode, String?> titles) =>
      _titles({
        for (final MapEntry(key: e, value: title) in titles.entries)
          e: {'value': title}
      });

  @override
  Future<void> clearEpisodeTitle(UiManagedEpisode episode) =>
      _titles({
        episode: {'value': null, 'mode': 'clear'}
      });

  /// Episode titles on every device that has the episode, a batch each.
  Future<void> _titles(Map<UiManagedEpisode, JsonMap> changes) async {
    final entries = <_Owner, List<JsonMap>>{};
    for (final MapEntry(key: e, value: change) in changes.entries) {
      for (final MapEntry(key: owner, value: id)
          in (e.handle as _EpisodeRef).own.entries) {
        (entries[owner] ??= [])
            .add({'entityId': id, 'field': 'title', ...change});
      }
    }
    for (final MapEntry(key: owner, value: list) in entries.entries) {
      await _callOn(owner, 'media.metadata.override_batch', {'entries': list});
    }
    await _settle(entries.keys);
  }

  @override
  Future<void> clearText(UiManagedWork work, UiTextField field) async {
    final owners = (work.handle as _WorkRef).owners;
    for (final o in owners) {
      await _callOn(o, 'media.metadata.override', {
        'entityId': o.workId,
        'field': field.name,
        'value': null,
        'mode': 'clear',
      });
    }
    await _settle(owners);
  }

  @override
  Future<void> setArt(UiManagedWork work, UiArtKind kind, String file) async {
    final result = await _call('media.artwork.set', {
      'entries': [
        {
          'entityId': _here(work).workId,
          'kind': kind.name,
          'file': file,
          'source': {'label': '本地文件'},
        }
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> clearArt(UiManagedWork work, UiArtKind kind) async {
    final owners = (work.handle as _WorkRef).owners;
    for (final o in owners) {
      await _callOn(o, 'media.artwork.clear', {
        'entries': [
          {'entityId': o.workId, 'kind': kind.name}
        ]
      });
    }
    await _settle(owners);
  }

  @override
  Future<void> refresh(UiManagedWork work) async {
    final matched = {
      for (final MapEntry(key: owner, value: bindings)
          in (work.handle as _WorkRef).bindings.entries)
        if (bindings.isNotEmpty) owner: bindings
    };
    if (matched.isEmpty) throw const UiManageError(message: 'no match');
    for (final MapEntry(key: owner, value: bindings) in matched.entries) {
      final result = await _callOn(owner, 'media.metadata.refresh_batch', {
        'entries': [
          for (final b in bindings)
            {'ref': b['ref'], 'requestId': _id('gui-refresh')}
        ]
      });
      _entries(result, 'entries');
    }
  }

  // —— 剧集 ——

  @override
  Future<UiManagedEpisode> episode(UiWork work, UiEpisode episode) async {
    final holders = [
      for (final o in await _owners(work.workId))
        if (o.episode(episode.episodeId) != null) o
    ];
    final away = [
      for (final o in holders)
        if (o.away case final reason?) reason
    ];
    final reachable = [
      for (final o in holders)
        if (o.away == null) o
    ];
    final primary =
        reachable.where((o) => o.local).firstOrNull ?? reachable.firstOrNull;
    final own = {for (final o in reachable) o: o.episode(episode.episodeId)!};

    final locations = <UiFile>[];
    for (final o in [
      if (primary != null) primary,
      ...reachable.where((o) => o != primary)
    ]) {
      for (final row in await _listed(o)) {
        if (_episodesOf(row).contains(own[o])) locations.add(_file(o, row));
      }
    }
    final files = <String, UiFile>{};
    for (final f in locations) {
      final ref = f.handle as _FileRef;
      if (ref.owner == primary) files.putIfAbsent(ref.fileId, () => f);
    }

    final tracks = <UiDanmakuTrack>[];
    final subtitles = <UiSubtitles>[];
    if (primary != null) {
      final seen = <Object>{};
      for (final entity in [own[primary]!, ...files.keys]) {
        final result =
            await _callOn(primary, 'danmaku.tracks', {'entityId': entity});
        for (final t in _maps(result['tracks'])) {
          final key = t['bindingId'] ?? t['trackId'];
          if (key == null || !seen.add(key)) continue;
          tracks.add(_track(primary, t));
        }
      }
      if (files.isNotEmpty) {
        final result = await _callOn(
            primary, 'subtitle.tracks', {'fileIds': files.keys.toList()});
        for (final facts in _maps(result['files'])) {
          if (files[facts['fileId']] case final file?) {
            subtitles.add(_subtitles(primary, facts, file));
          }
        }
      }
    }

    return UiManagedEpisode(
      episode: episode,
      number: '${episode.number ?? ''}',
      season: episode.season,
      title: episode.title,
      files: files.values.toList(),
      locations: locations,
      device: primary?.name,
      away: away,
      unavailable: primary == null ? away.firstOrNull : null,
      danmaku: tracks,
      subtitles: subtitles,
      handle: _EpisodeRef(episode.episodeId, own, primary),
    );
  }

  /// Where an episode's comments and subtitles are changed, when files
  /// picked on this device may go there.
  static _Owner _episodeHere(UiManagedEpisode episode) {
    final primary = (episode.handle as _EpisodeRef).primary!;
    if (!primary.local) {
      throw const UiManageError(message: 'not on this device');
    }
    return primary;
  }

  static const _platforms = {
    'dandanplay': '弹弹play',
    'local': '本地文件',
    'bilibili': 'B 站',
    'youku': '优酷',
    'iqiyi': '爱奇艺',
    'tencent': '腾讯视频',
  };

  static String _platform(Object? p) =>
      _platforms['$p'] ?? (p is String && p.isNotEmpty ? p : '弹幕');

  UiDanmakuTrack _track(_Owner owner, Map t) {
    var count = _int(t['count']);
    if (count == null) {
      final chunks = _maps(t['coverage']);
      if (chunks.isNotEmpty) {
        count = chunks.fold<int>(0, (n, c) => n + (_int(c['entry_count']) ?? 0));
      }
    }
    final origin = '${t['origin']}';
    return UiDanmakuTrack(
      source: _platform(origin == 'sidecar' || origin.endsWith('import')
          ? (t['platform'] == null || t['platform'] == 'local'
              ? 'local'
              : t['platform'])
          : t['platform'] ?? t['source']),
      name: _text((t['video'] as Map?)?['title']) ?? _text(t['name']),
      count: count,
      enabled: t['enabled'] != false,
      offset: Duration(milliseconds: _int(t['offsetMs']) ?? 0),
      loading: t['status'] == 'pending' || t['stale'] == true && count == null,
      removable: t['bindingId'] != null,
      handle: _TrackRef(owner, t['bindingId'] as String?,
          t['trackId'] as String?, _int(t['revision'])),
    );
  }

  static UiSubtitles _subtitles(_Owner owner, Map facts, UiFile file) {
    final selection = facts['selection'] as Map?;
    return UiSubtitles(
      file: file,
      tracks: [
        for (final t in _maps(facts['tracks']))
          UiSubtitleTrack(
            id: t['id'] as String,
            kind: switch (t['origin']) {
              'embedded' => UiSubtitleKind.embedded,
              'import' => UiSubtitleKind.imported,
              _ => UiSubtitleKind.external,
            },
            language: t['language'] as String?,
            title: _text(t['title']),
            format: _text(t['format']),
            available: t['available'] != false,
          )
      ],
      selected: selection?['trackId'] as String?,
      explicit: selection?['basis'] == 'explicit',
      detached: [
        for (final p in facts['detachedPaths'] is List
            ? facts['detachedPaths'] as List
            : const [])
          if (p is String) p
      ],
      handle: _SubtitleRef(
          owner, facts['fileId'] as String, _int(facts['revision']) ?? 0),
    );
  }

  @override
  Future<void> setDanmaku(UiDanmakuTrack track,
      {bool? enabled, Duration? offset}) async {
    final ref = track.handle as _TrackRef;
    final result = await _callOn(ref.owner, 'danmaku.update', {
      'changes': [
        {
          if (ref.bindingId != null) ...{
            'bindingId': ref.bindingId,
            'expectedRevision': ref.revision,
          } else
            'trackId': ref.trackId,
          if (enabled != null) 'enabled': enabled,
          if (offset != null) 'offsetMs': offset.inMilliseconds,
        }
      ]
    });
    _entries(result, 'results');
  }

  @override
  Future<List<UiDanmakuCandidate>> searchDanmaku(String query) async {
    final sources = await _call('danmaku.sources', {});
    final out = <UiDanmakuCandidate>[];
    for (final s in _maps(sources['sources'])) {
      if (s['search'] != true) continue;
      final result = await _call(
          'danmaku.search', {'sourceId': s['sourceId'], 'query': query});
      for (final v in _maps(result['results'])) {
        out.add(UiDanmakuCandidate(
          title: _text(v['title']) ?? '',
          source: _platform(s['platform'] ?? s['sourceId']),
          handle: Map<String, Object?>.from(v),
        ));
      }
    }
    return out;
  }

  @override
  Future<void> addDanmaku(
      UiManagedEpisode episode, UiDanmakuCandidate found) async {
    final ref = episode.handle as _EpisodeRef;
    final owner = ref.primary!;
    final duration = episode.files.firstOrNull?.duration ??
        episode.episode?.runtime;
    final video = Map<String, Object?>.from(found.handle as Map);
    if (duration != null && (video['durationMs'] as num? ?? 0) <= 0) {
      video['durationMs'] = duration.inMilliseconds;
    }
    await _callOn(owner, 'danmaku.prepare', {
      'video': video,
      'reason': 'Viewer added comments in the episode sheet.',
      'requestId': _id('gui-attach'),
      'entityId': ref.own[owner],
    });
  }

  @override
  Future<void> importDanmaku(UiManagedEpisode episode, String path) async {
    final owner = _episodeHere(episode);
    await _call('danmaku.import', {
      'filePath': path,
      'platform': 'local',
      'platformVideoId': path.split(RegExp(r'[\\/]')).last,
      'entityId': (episode.handle as _EpisodeRef).own[owner],
    });
  }

  @override
  Future<void> removeDanmaku(UiDanmakuTrack track) async {
    final ref = track.handle as _TrackRef;
    await _callOn(ref.owner, 'danmaku.detach',
        {'bindingId': ref.bindingId, 'revision': ref.revision});
  }

  @override
  Future<void> selectSubtitle(UiSubtitles file, String? trackId) {
    final ref = file.handle as _SubtitleRef;
    return _callOn(ref.owner, 'subtitle.select', {
      'fileId': ref.fileId,
      'trackId': trackId,
    });
  }

  @override
  Future<void> automaticSubtitle(UiSubtitles file) async {
    final ref = file.handle as _SubtitleRef;
    final result = await _callOn(ref.owner, 'subtitle.reset_selection', {
      'entries': [
        {'fileId': ref.fileId}
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> importSubtitle(UiSubtitles file, String path) async {
    final ref = file.handle as _SubtitleRef;
    if (!ref.owner.local) {
      throw const UiManageError(message: 'not on this device');
    }
    final result = await _call('subtitle.import', {
      'entries': [
        {
          'fileId': ref.fileId,
          'filePath': path,
          'language': 'und',
          'source': {'label': '本地文件'},
        }
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> editSubtitle(UiSubtitles file, UiSubtitleTrack track,
      {String? language, String? title}) async {
    final ref = file.handle as _SubtitleRef;
    final result = await _callOn(ref.owner, 'subtitle.update', {
      'entries': [
        {
          'fileId': ref.fileId,
          'trackId': track.id,
          'expectedRevision': ref.revision,
          'patch': {
            if (language != null) 'language': language,
            if (title != null) 'title': title,
          },
        }
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> detachSubtitle(UiSubtitles file, UiSubtitleTrack track) async {
    final ref = file.handle as _SubtitleRef;
    final result = await _callOn(ref.owner, 'subtitle.remove', {
      'entries': [
        {
          'fileId': ref.fileId,
          'trackId': track.id,
          'expectedRevision': ref.revision
        }
      ]
    });
    _entries(result, 'entries');
  }

  /// A destructive Action's question as the sheet asks it: [items], and
  /// running the option NipaPlay offered (another device's options come
  /// back as its own `mesh.invoke` calls).
  Future<UiConfirm> _decision(
      _Owner? owner, String action, JsonMap input, List<String> items,
      {bool destructive = false}) async {
    final outcome =
        await _on(owner, action, input, destructive: destructive);
    return switch (outcome) {
      NeedsDecision(:final decision) when decision.options.isNotEmpty =>
        UiConfirm(
          items: items,
          run: () async {
            final call = decision.options.first.call;
            final done = await _invoke(call.actionId, call.input);
            if (done case Failed(:final failure)) throw _error(failure);
          },
        ),
      Failed(:final failure) => throw _error(failure),
      _ => throw const UiManageError(message: 'no decision offered'),
    };
  }

  @override
  Future<UiConfirm> deleteSubtitleCopies(UiSubtitles file) => _decision(
      (file.handle as _SubtitleRef).owner,
      'subtitle.copy_delete',
      {'paths': file.detached},
      [for (final p in file.detached) p.split(RegExp(r'[\\/]')).last],
      destructive: true);

  @override
  Future<void> reveal(UiFile file) async => uiRevealed(await _callOn(
      (file.handle as _FileRef).owner, 'media.files.reveal', {
    'paths': [file.path]
  }));

  @override
  Future<UiConfirm> deleteFile(UiFile file) {
    final owner = (file.handle as _FileRef).owner;
    return _decision(
        null,
        'media.mesh_files.delete',
        {
          'paths': [file.path],
          if (!owner.local) 'deviceId': owner.deviceId,
        },
        [file.name]);
  }

  @override
  Future<String?> pickFile(List<String> kinds) async =>
      (await openFile(acceptedTypeGroups: [XTypeGroup(extensions: kinds)]))
          ?.path;
}

/// A provider work's episodes as the agent reads them: the work's record
/// (`media.metadata.get`) and, where it lists seasons without their
/// episodes (a TMDB series), every such season's own record in one call
/// (`media.metadata.get_batch`). A season that cannot be read throws its
/// [Failure]: part of a work is never shown as if it had no episodes.
/// [call] runs an Action on this device and throws when it fails.
Future<List<UiCandidateEpisode>> readCandidateEpisodes(
    Future<JsonMap> Function(String action, JsonMap input) call,
    Map<String, Object?> ref) async {
  final record = Map<String, Object?>.from(
      (await call('media.metadata.get', {'ref': ref}))['record'] as Map);
  final entries = CoreWorkManage._maps(record['episodes']);
  final unread = [
    for (final (i, e) in entries.indexed)
      if ((e['ref'] as Map?)?['objectType'] == 'season' &&
          CoreWorkManage._maps(e['episodes']).isEmpty)
        i
  ];
  if (unread.isEmpty) return candidateEpisodesOf(record);
  final read = await call('media.metadata.get_batch', {
    'refs': [for (final i in unread) entries[i]['ref']]
  });
  final seasons = [...entries];
  final filled = <int>{};
  for (final r in CoreWorkManage._maps(read['results'])) {
    final at = unread[r['index'] as int];
    if (r['error'] case final Map error) throw failureOf(error);
    seasons[at] = {...entries[at], 'episodes': (r['record'] as Map)['episodes']};
    filled.add(at);
  }
  if (filled.length != unread.length) {
    throw const Failure(FailureCode.internal, 'A season was not read.');
  }
  return candidateEpisodesOf({...record, 'episodes': seasons});
}

/// A provider work's episodes as `media.metadata.get` records them; a
/// TV season's within it, with the season as their release, the specials
/// (season 0) after the others. Of several seasons, each says its own. A
/// film has none: it is its own one (`media.management.bind_batch` takes
/// the film's ref as the episode, with no release).
List<UiCandidateEpisode> candidateEpisodesOf(Map record) {
  if (record['ref'] case final Map ref
      when ref['objectType'] == 'movie' || record['kind'] == 'movie') {
    return [UiCandidateEpisode.film(Map<String, Object?>.from(ref))];
  }
  final found = <(Map, Map?, int?)>[];
  for (final e in CoreWorkManage._maps(record['episodes'])) {
    final ref = e['ref'] as Map;
    if (ref['objectType'] == 'season') {
      final season =
          CoreWorkManage._int(e['number']) ?? CoreWorkManage._int(e['season']);
      for (final inner in CoreWorkManage._maps(e['episodes'])) {
        found.add((inner, ref, CoreWorkManage._int(inner['season']) ?? season));
      }
    } else {
      found.add((e, null, CoreWorkManage._int(e['season'])));
    }
  }
  final several = {
        for (final (_, _, s) in found)
          if (s != null) s
      }.length >
      1;
  final out = [
    for (final (e, release, season) in found)
      UiCandidateEpisode(
        number: '${e['number'] ?? e['order'] ?? ''}',
        season: season,
        title: CoreWorkManage._text(e['title']),
        ref: Map<String, Object?>.from(e['ref'] as Map),
        release: release == null ? null : Map<String, Object?>.from(release),
        seasons: several,
      )
  ];
  return [
    ...out.where((e) => e.season != 0),
    ...out.where((e) => e.season == 0),
  ];
}

final class _WorkRef {
  const _WorkRef(this.primary, this.bindings);

  /// Where it is changed: this device when it has it.
  final _Owner primary;

  /// Each device that answers, with the accepted matches of its own work.
  final Map<_Owner, List<Map>> bindings;

  Iterable<_Owner> get owners => bindings.keys;
}

final class _EpisodeRef {
  const _EpisodeRef(this.episodeId, this.own, [this.primary]);
  final String episodeId;

  /// Each device's own episode.
  final Map<_Owner, String> own;

  /// Where its comments and subtitles are changed.
  final _Owner? primary;
}

/// A place of a file, on the device that has it.
final class _FileRef {
  const _FileRef(this.owner, this.fileId);
  final _Owner owner;
  final String fileId;
}

/// One device's part of a change of matches: what it lets go of and what
/// it binds, each with its preview.
final class _Plan {
  const _Plan(this.owner, {this.unbind, this.bind, this.unbound, this.bound});
  final _Owner owner;
  final JsonMap? unbind, bind;
  final JsonMap? unbound, bound;
}

final class _TrackRef {
  const _TrackRef(this.owner, this.bindingId, this.trackId, this.revision);
  final _Owner owner;
  final String? bindingId;
  final String? trackId;
  final int? revision;
}

final class _SubtitleRef {
  const _SubtitleRef(this.owner, this.fileId, this.revision);
  final _Owner owner;
  final String fileId;
  final int revision;
}
