import 'dart:math' as math;

import 'package:nipa_harness/nipa_harness.dart';

import '../../ui_data/ui_data.dart';
import 'core_manage.dart' show candidateEpisodesOf;
import 'gui_calls.dart';
import 'work_manage.dart' show UiCandidateEpisode, UiProvider;
import 'work_owners.dart';

/// Several works of the library at once, as the person: their sources
/// read again (`media.metadata.refresh_batch`), each matched to a work a
/// provider knows or let go of its match (`media.management.bind_batch` /
/// `unbind_batch`: a preview first, then the same input with its plan).
///
/// Works are known by their merged library IDs; [readWorkOwners] names the
/// devices that have each and their own IDs for it. Each device is asked
/// for its own part, this one directly and another through `mesh.invoke`,
/// so every check happens where the work is.
final class NextBatch {
  NextBatch(this.calls, this.data);
  final GuiCalls calls;

  /// The library's episodes, for their numbers.
  final NextUiData data;

  int _ids = 0;
  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_ids++}';

  /// [action] on [owner]'s device.
  Future<JsonMap> _at(WorkOwner owner, String action, JsonMap input) =>
      owner.local
          ? calls.call(action, input)
          : calls.call('mesh.invoke',
              {'deviceId': owner.deviceId, 'action': action, 'input': input});

  /// Where each work is and what each device's own work is matched to
  /// (`media.identity.get` on each device that answers).
  Future<List<UiBatchWork>> read(List<UiWork> works) async {
    final merged = [
      for (final w in works)
        if (!w.workId.startsWith('source-work:')) w.workId
    ];
    final found = merged.isEmpty
        ? const <String, ({List<WorkOwner> owners, Map? error})>{}
        : await readWorkOwners(calls.call, merged);
    return Future.wait([
      for (final w in works)
        w.workId.startsWith('source-work:')
            ? Future.value(UiBatchWork(w, away: const ['在共享来源里']))
            : _read(w, found[w.workId]!)
    ]);
  }

  Future<UiBatchWork> _read(
      UiWork work, ({List<WorkOwner> owners, Map? error}) found) async {
    if (found.error case final Map error) {
      return UiBatchWork(work, away: [callFailure(failureOf(error))]);
    }
    final owners = <WorkOwner>[];
    final matches = <WorkOwner, List<Map<String, Object?>>>{};
    final away = <String>[];
    for (final o in found.owners) {
      if (o.away case final reason?) {
        away.add(reason);
        continue;
      }
      try {
        final identity = (await _at(
                o, 'media.identity.get', {'entityId': o.workId}))['identity']
            as Map;
        if (identity['kind'] != 'work') continue;
        owners.add(o);
        matches[o] = [
          for (final b in (identity['bindings'] as List).cast<Map>())
            if (b['status'] == 'accepted')
              Map<String, Object?>.from(b['ref'] as Map)
        ];
      } on Failure catch (f) {
        if (f.code != FailureCode.notFound) away.add(callFailure(f));
      }
    }
    owners.sort((a, b) => (b.local ? 1 : 0) - (a.local ? 1 : 0));
    return UiBatchWork(work, owners: owners, matches: matches, away: away);
  }

  /// Asks the sources of [works] for their data again, each device for its
  /// own; per work, the jobs doing it, or why one could not start. A
  /// hundred refs a call.
  Future<Map<String, UiRefreshStart>> refresh(List<UiBatchWork> works) async {
    final byDevice = <String, List<(String, WorkOwner, Map)>>{};
    for (final w in works) {
      for (final MapEntry(key: o, value: refs) in w.matches.entries) {
        for (final ref in refs) {
          (byDevice[o.deviceId] ??= []).add((w.work.workId, o, ref));
        }
      }
    }
    final jobs = <String, List<UiBatchJob>>{};
    final failures = <String, Failure>{};
    for (final refs in byDevice.values) {
      for (var at = 0; at < refs.length; at += 100) {
        final chunk = refs.sublist(at, math.min(at + 100, refs.length));
        final owner = chunk.first.$2;
        final JsonMap result;
        try {
          result = await _at(owner, 'media.metadata.refresh_batch', {
            'entries': [
              for (final (_, _, ref) in chunk)
                {'ref': ref, 'requestId': _id('gui-refresh')}
            ]
          });
        } on Failure catch (f) {
          for (final (workId, _, _) in chunk) {
            failures[workId] ??= f;
          }
          continue;
        }
        for (final e in (result['entries'] as List).cast<Map>()) {
          final (workId, _, _) = chunk[e['index'] as int];
          if (e['status'] == 'completed') {
            final job = (e['result'] as Map)['job'] as Map;
            (jobs[workId] ??= [])
                .add(UiBatchJob(owner, job['jobId'] as String));
          } else {
            failures[workId] ??= failureOf(e['error'] as Map);
          }
        }
      }
    }
    return {
      for (final w in works)
        if (w.matched)
          w.work.workId: UiRefreshStart(
              jobs[w.work.workId] ?? const [], failures[w.work.workId])
    };
  }

  /// Where a job is now (`task.get` on its device).
  Future<UiJobState> job(UiBatchJob job) async {
    final snapshot =
        (await _at(job.owner, 'task.get', {'jobId': job.jobId}))['job'] as Map;
    return switch (snapshot['state']) {
      'succeeded' => const UiJobState(UiJobStep.done),
      'failed' || 'cancelled' => UiJobState(UiJobStep.failed,
          failure: snapshot['error'] is Map
              ? failureOf(snapshot['error'] as Map)
              : const Failure(FailureCode.internal, 'cancelled')),
      _ => const UiJobState(UiJobStep.waiting),
    };
  }

  /// Works [provider] knows by [query] (`media.metadata.search`).
  Future<List<UiBatchCandidate>> search(
      UiProvider provider, String query) async {
    final result = await calls.call(
        'media.metadata.search', {'provider': provider.name, 'query': query});
    return [
      for (final r in (result['results'] as List).cast<Map>())
        UiBatchCandidate(
          title: r['title'] as String,
          ref: Map<String, Object?>.from(r['ref'] as Map),
          originalTitle: r['originalTitle'] as String?,
          year: r['year'] as int?,
          image: r['imageUrl'] as String?,
          movie: r['kind'] == 'movie',
          inLibrary: r['workId'] != null,
        )
    ];
  }

  /// What matching each work to its candidate would touch on every device
  /// that has it, nothing changed yet. As a single work's match: each file
  /// to the candidate's episode of its episode's number (the movie itself
  /// for a film; `media.metadata.get`), a file matched to another identity
  /// let go of first. Episodes no number fits stay as they are.
  Future<UiAssociationPreview> previewMatch(
      List<(UiBatchWork, UiBatchCandidate)> pairs) async {
    const reason = 'Viewer matched several works in the library.';
    final catalogues = <String, Future<List<UiCandidateEpisode>>>{};
    final parts = <String, _Part>{};
    final fits = <String, (int, int)>{};
    for (final (w, c) in pairs) {
      final catalogue = c.movie
          ? const <UiCandidateEpisode>[]
          : await (catalogues[_refKey(c.ref)] ??= calls
              .call('media.metadata.get', {'ref': c.ref}).then(
                  (r) => candidateEpisodesOf(r['record'] as Map)));
      final mine = {
        for (final e in await data.episodes(w.work.workId)) e.episodeId: e
      };
      final fitted = <String>{}, missed = <String>{};
      for (final o in w.owners) {
        final part = parts[o.deviceId] ??=
            _Part(o, _id('gui-batch-release'), _id('gui-batch-match'));
        part.works[o.workId] = w;
        final files =
            (await _at(o, 'media.files.list', {'workId': o.workId}))['files']
                as List;
        for (final file in files.cast<Map>()) {
          final fileId = file['fileId'] as String;
          if (!part.files.add(fileId)) continue;
          final episodes = [
            for (final e in (file['episodes'] as List).cast<Map>())
              if (o.episodes[e['episodeId']] case final merged?) merged
          ];
          final number = episodes.map((e) => mine[e]).nonNulls.firstOrNull;
          final to = c.movie
              ? UiCandidateEpisode(number: '', ref: c.ref)
              : number == null
                  ? null
                  : _fit(catalogue, number);
          if (to == null) {
            missed.addAll(episodes);
            continue;
          }
          fitted.addAll(episodes);
          final bindings = (file['bindings'] as List).cast<Map>();
          if (bindings.isNotEmpty) {
            part.releases.add({
              'entityId': fileId,
              'reason': reason,
              'bindingIds': [for (final b in bindings) b['bindingId']],
            });
          }
          part.binds.add({
            'kind': 'file',
            'reason': reason,
            'entityId': fileId,
            'workRef': c.ref,
            if (to.release != null) 'releaseRef': to.release,
            'episodeRefs': [to.ref],
          });
        }
      }
      fits[w.work.workId] = (fitted.length, missed.difference(fitted).length);
    }
    return _preview(
        [for (final (w, _) in pairs) w], parts.values.toList(), fits);
  }

  /// The candidate's episode for [mine]: the one of its number, and of its
  /// season when the number is in several.
  static UiCandidateEpisode? _fit(
      List<UiCandidateEpisode> catalogue, UiEpisode mine) {
    final same = [
      for (final c in catalogue)
        if (int.tryParse(c.number) == mine.number) c
    ];
    if (same.length <= 1) return same.firstOrNull;
    final season = [
      for (final c in same)
        if (c.season == (mine.season ?? 1)) c
    ];
    return season.length == 1 ? season.single : null;
  }

  static String _refKey(Map ref) =>
      '${ref['provider']}/${ref['objectType']}/${ref['externalId']}/${ref['scope']}';

  /// What letting go of the works' matches would touch on every device
  /// whose own work has one.
  Future<UiAssociationPreview> previewUnmatch(List<UiBatchWork> works) {
    final parts = <String, _Part>{};
    for (final w in works) {
      for (final MapEntry(key: o, value: refs) in w.matches.entries) {
        if (refs.isEmpty) continue;
        final part =
            parts[o.deviceId] ??= _Part(o, _id('gui-batch-unmatch'), '');
        part.works[o.workId] = w;
        part.releases.add({
          'entityId': o.workId,
          'reason': 'Viewer let go of several works\' matches in the library.',
        });
      }
    }
    return _preview(works, parts.values.toList(), null);
  }

  /// The same change previewed again where it is not done yet, after what
  /// it touches changed.
  Future<UiAssociationPreview> again(UiAssociationPreview preview) =>
      _preview(preview.works, preview._parts, preview._fits);

  /// Carries [preview] out as it was shown, device by device: what is let
  /// go of first, then the matches, previewed again after the release they
  /// waited for. A conflict [Failure] when what one touches changed since
  /// ([again]). Another device's change reaches the merged library at once.
  Future<void> apply(UiAssociationPreview preview) async {
    for (final part in preview._parts) {
      if (part.applied) continue;
      if (part.releases.isNotEmpty && !part.released) {
        await _at(part.owner, 'media.management.unbind_batch',
            {...part.release, 'expectedPlan': part.unbound!['expectedPlan']});
        part.released = true;
      }
      if (part.binds.isNotEmpty) {
        final plan = part.releases.isEmpty
            ? part.bound!['expectedPlan']
            : (await _at(part.owner, 'media.management.bind_batch', part.bind))[
                'expectedPlan'];
        await _at(part.owner, 'media.management.bind_batch',
            {...part.bind, 'expectedPlan': plan});
      }
      part.applied = true;
    }
    if (preview._parts.any((p) => !p.owner.local)) {
      await calls.call('media.library.refresh', {});
    }
  }

  Future<UiAssociationPreview> _preview(List<UiBatchWork> works,
      List<_Part> parts, Map<String, (int, int)>? fits) async {
    for (final part in parts) {
      if (part.applied) continue;
      if (part.releases.isNotEmpty && !part.released) {
        part.unbound = await _at(
            part.owner, 'media.management.unbind_batch', part.release);
      }
      if (part.binds.isNotEmpty) {
        part.bound =
            await _at(part.owner, 'media.management.bind_batch', part.bind);
      }
    }

    final tallies = <String, _Tally>{};
    var episodes = 0, files = 0, progress = 0;
    var keeps = true;
    for (final part in parts) {
      final previews = [
        for (final r in [part.unbound, part.bound])
          if (r != null) r['preview'] as Map
      ];
      final rows = {
        for (final p in previews)
          for (final r in (p['entities'] as List).cast<Map>())
            _entity(r)['id'] as String: r
      };
      keeps = keeps &&
          previews.every((p) =>
              p['diskFilesDeleted'] == false && p['progressChanged'] == false);
      for (final row in rows.values) {
        final kind = _entity(row)['kind'];
        final e = kind == 'episode' ? 1 : 0;
        final f = kind == 'file' ? 1 : 0;
        final p = kind == 'file' ? _watched(row) : 0;
        episodes += e;
        files += f;
        progress += p;
        final own = _workAbove(rows, _entity(row)['id'] as String);
        if (own == null) continue;
        final work = part.works[own];
        final tally =
            tallies[work?.work.workId ?? '${part.owner.deviceId}/$own'] ??=
                _Tally(work, part.owner);
        tally
          ..row ??= rows[own]
          ..episodes += e
          ..files += f
          ..progress += p;
      }
    }
    return UiAssociationPreview._(
      parts: parts,
      fits: fits,
      works: works,
      groups: [
        for (final w in works)
          (tallies[w.work.workId] ?? _Tally(w, null))
              .group(w.work.workId, fits?[w.work.workId]),
        for (final MapEntry(key: id, value: t) in tallies.entries)
          if (t.work == null) t.group(id, null),
      ],
      episodes: episodes,
      files: files,
      progress: progress,
      keeps: keeps,
    );
  }

  static Map _entity(Map row) => row['entity'] as Map;

  /// The work a preview entity belongs to: up through its parents, a file
  /// through the episode it is.
  static String? _workAbove(Map<String, Map> entities, String id) {
    var node = entities[id];
    for (var i = 0; i < 4 && node != null; i++) {
      final entity = _entity(node);
      if (entity['kind'] == 'work') return entity['id'] as String;
      if (entity['kind'] == 'file') {
        final episode = (node['associations'] as List)
            .cast<Map>()
            .map((a) => a['episode_id'] as String)
            .where(entities.containsKey)
            .firstOrNull;
        node = episode == null ? null : entities[episode];
      } else {
        final parent = entity['parent_id'] as String?;
        node = parent == null ? null : entities[parent];
      }
    }
    return null;
  }

  static int _watched(Map row) => (row['progress'] as List)
      .cast<Map>()
      .where((p) =>
          ((p['watchProgress'] as num?) ?? 0) > 0 ||
          ((p['lastPosition'] as num?) ?? 0) > 0)
      .length;
}

/// One device's part of a change: what it lets go of, what it matches,
/// and once previewed, each preview and plan.
final class _Part {
  _Part(this.owner, String releaseId, String bindId)
      : release = {'requestId': releaseId, 'entries': <JsonMap>[]},
        bind = {'requestId': bindId, 'entries': <JsonMap>[]};
  final WorkOwner owner;
  final JsonMap release, bind;

  /// The device's own work IDs, to the picked works they are.
  final works = <String, UiBatchWork>{};

  /// Files already in it.
  final files = <String>{};
  JsonMap? unbound, bound;
  bool released = false, applied = false;

  List<JsonMap> get releases => release['entries'] as List<JsonMap>;
  List<JsonMap> get binds => bind['entries'] as List<JsonMap>;
}

final class _Tally {
  _Tally(this.work, this.owner);
  final UiBatchWork? work;
  final WorkOwner? owner;
  Map? row;
  int episodes = 0, files = 0, progress = 0;

  UiAssociationGroup group(String id, (int, int)? fit) {
    final entity = row?['entity'] as Map?;
    return UiAssociationGroup(
      id: id,
      work: work?.work,
      title: work?.work.title ??
          (entity?['attributes'] as Map?)?['title'] as String?,
      device: work == null ? owner?.name : null,
      episodes: episodes,
      files: files,
      progress: progress,
      providers: [
        for (final s in (row?['sources'] as List? ?? const []).cast<Map>())
          if (s['status'] == 'accepted') s['provider'] as String
      ],
      away: work?.away ?? const [],
      fitted: fit?.$1,
      missed: fit?.$2,
    );
  }
}

/// A picked work: the devices that have it in their catalogue and answer
/// (this one first), what each one's own work is matched to, and why it
/// cannot be changed where it also is.
final class UiBatchWork {
  const UiBatchWork(this.work,
      {this.owners = const [], this.matches = const {}, this.away = const []});
  final UiWork work;
  final List<WorkOwner> owners;

  /// The provider objects each device's own work is matched to, as they
  /// came.
  final Map<WorkOwner, List<Map<String, Object?>>> matches;

  /// As said: “旧笔记本不在线”, “在共享来源里”.
  final List<String> away;

  bool get reachable => owners.isNotEmpty;
  bool get matched => matches.values.any((m) => m.isNotEmpty);

  /// Its matches' providers, for a word under it.
  List<String> get providers => {
        for (final refs in matches.values)
          for (final m in refs) m['provider'] as String
      }.toList();
}

/// A job a refresh started, on the device that runs it.
final class UiBatchJob {
  const UiBatchJob(this.owner, this.jobId);
  final WorkOwner owner;
  final String jobId;
}

/// A refresh asked of a work's sources: the jobs doing it, or why it
/// could not start.
final class UiRefreshStart {
  const UiRefreshStart(this.jobs, this.failure);
  final List<UiBatchJob> jobs;
  final Failure? failure;
}

enum UiJobStep { waiting, done, failed }

final class UiJobState {
  const UiJobState(this.step, {this.failure});
  final UiJobStep step;
  final Failure? failure;
}

/// A work a provider knows, as a search found it.
final class UiBatchCandidate {
  const UiBatchCandidate({
    required this.title,
    required this.ref,
    this.originalTitle,
    this.year,
    this.image,
    this.movie = false,
    this.inLibrary = false,
  });
  final String title;
  final String? originalTitle;
  final int? year;
  final String? image;
  final bool movie;

  /// A work of the library is matched to it already.
  final bool inLibrary;

  /// The provider's reference, handed back as it came; never shown.
  final Map<String, Object?> ref;
}

/// What a change of matches touches, per work: the picked ones first,
/// then others it reaches (already matched to the same).
final class UiAssociationPreview {
  UiAssociationPreview._({
    required List<_Part> parts,
    required Map<String, (int, int)>? fits,
    required this.works,
    required this.groups,
    required this.episodes,
    required this.files,
    required this.progress,
    required this.keeps,
  })  : _parts = parts,
        _fits = fits;

  final List<_Part> _parts;
  final Map<String, (int, int)>? _fits;
  final List<UiBatchWork> works;
  final List<UiAssociationGroup> groups;
  final int episodes, files, progress;

  /// Files on disk and watch progress stay as they are.
  final bool keeps;

  /// Nothing would change: no episode fits, nothing to let go of.
  bool get empty => _parts.every((p) => p.releases.isEmpty && p.binds.isEmpty);
}

final class UiAssociationGroup {
  const UiAssociationGroup({
    required this.id,
    required this.work,
    required this.title,
    required this.device,
    required this.episodes,
    required this.files,
    required this.progress,
    required this.providers,
    required this.away,
    this.fitted,
    this.missed,
  });
  final String id;

  /// The picked work; null for another the change reaches.
  final UiWork? work;
  final String? title;

  /// Where another work is, when not here.
  final String? device;
  final int episodes, files, progress;

  /// Providers it is matched to now.
  final List<String> providers;

  /// Why devices that also have it are left as they are.
  final List<String> away;

  /// For a match, its episodes the candidate's fit and those none does.
  final int? fitted, missed;
}
