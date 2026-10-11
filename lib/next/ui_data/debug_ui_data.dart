import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';

import '../harness_redaction.dart';
import '../next_core.dart';
import 'ui_data.dart';

/// Registered only in a debug lab profile. Reads the same in-process UI facade.
void installDebugUiData(NextCore core) {
  final observations = <Object?>[];
  core.uiData.changes.listen((_) => observations.add(
      {'event': 'changes', 'at': DateTime.now().toUtc().toIso8601String()}));
  core.uiData.tasks().listen((tasks) => observations.add({
        'event': 'tasks',
        'at': DateTime.now().toUtc().toIso8601String(),
        'tasks': [for (final task in tasks) _task(task)]
      }));
  registerExtension('ext.nipaplay.uiData', (_, params) async {
    try {
      final Object? result;
      switch (params['op']) {
        case 'home':
          final home = await core.uiData.home();
          result = {
            'hero': home.hero == null
                ? null
                : {'work': _work(home.hero!.work), 'note': home.hero!.note},
            'shelves': [
              for (final s in home.shelves)
                {
                  'id': s.id,
                  'title': s.title,
                  'kind': s.kind.name,
                  'items': [
                    for (final i in s.items)
                      {
                        'work': _work(i.work),
                        'episode':
                            i.episode == null ? null : _episode(i.episode!),
                        'caption': i.caption,
                        'badge': i.badge
                      }
                  ]
                }
            ]
          };
        case 'work':
          result = await core.uiData
              .work(params['workId']!)
              .then((w) => w == null ? null : _work(w));
        case 'episodes':
          result = [
            for (final e in await core.uiData.episodes(params['workId']!))
              _episode(e)
          ];
        case 'cards':
          result = [
            for (final c in await core.uiData
                .cards(threadId: params['threadId']!, turnId: params['turnId']))
              _card(c)
          ];
        case 'observations':
          result = List.of(observations);
          observations.clear();
        case 'credential':
          await core.credentialVault.write(
              const CredentialRef('metadata', 'tmdb'),
              (await File('/tmp/nipa-next/tmdb.token').readAsString()).trim());
          result = {'configured': true};
        case 'session':
          final row = {
            'event': 'chat.turn_boundary',
            'origin': 'harness_cli:chat:${params['session']!}',
            'threadId': params['threadId']!,
            'turnId': params['turnId']!,
            'phase': params['phase'] ?? 'started',
            'status':
                params['phase'] == 'completed' ? 'completed' : 'inProgress',
            'startedAt': DateTime.now().toUtc().toIso8601String()
          };
          await File('${core.root.path}/journal.jsonl').writeAsString(
              '${jsonEncode(row)}\n',
              mode: FileMode.append,
              flush: true);
          result = row;
        case 'hook':
          final job =
              await core.hooks.emit('playback.started', params['workId']!, {});
          result = {'jobId': job?.jobId};
        case 'history':
          final path = await core.media.service.authorizedPath(params['path']!);
          final duration = int.parse(params['durationMs']!),
              position = int.parse(params['positionMs']!);
          await ServiceProvider.watchHistoryProvider.addOrUpdateHistory(
              WatchHistoryItem(
                  filePath: path,
                  animeName: '葬送的芙莉莲',
                  episodeTitle: '冒险的结束',
                  watchProgress: position / duration,
                  lastPosition: position,
                  duration: duration,
                  lastWatchTime: DateTime.now()));
          await ServiceProvider.watchHistoryProvider.refresh();
          result = {'recorded': true};
        case 'remove':
          await core.uiData
              .removeShelf(params['id']!, workId: params['workId']);
          result = {'removed': true};
        default:
          throw ArgumentError('Unknown lab UI operation');
      }
      return ServiceExtensionResponse.result(jsonEncode(result));
    } catch (error) {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          redactHarnessText(error.toString()));
    }
  });
}

Map<String, Object?> _art(UiArtwork a) => {
      'backdrop': a.backdrop,
      'poster': a.poster,
      'logo': a.logo,
      'tint': a.tint
    };
Map<String, Object?> _work(UiWork w) => {
      'workId': w.workId,
      'title': w.title,
      'originalTitle': w.originalTitle,
      'year': w.year,
      'genres': w.genres,
      'episodeCount': w.episodeCount,
      'studio': w.studio,
      'overview': w.overview,
      'ratings': [
        for (final r in w.ratings) {'source': r.source, 'value': r.value}
      ],
      'artwork': _art(w.artwork),
      'next': w.next == null ? null : _episode(w.next!)
    };
Map<String, Object?> _episode(UiEpisode e) => {
      'episodeId': e.episodeId,
      'workId': e.workId,
      'number': e.number,
      'season': e.season,
      'title': e.title,
      'runtimeMs': e.runtime?.inMilliseconds,
      'still': e.still,
      'progress': e.progress,
      'heat': e.heat,
      'playable': e.playable
    };
Map<String, Object?> _task(UiTask t) => {
      'taskId': t.taskId,
      'title': t.title,
      'state': t.state.name,
      'artwork': t.artwork == null ? null : _art(t.artwork!),
      'progress': t.progress,
      'remainingMs': t.remaining?.inMilliseconds
    };
Map<String, Object?> _card(UiCard c) => switch (c) {
      UiWorkCard() => {'kind': 'work', 'work': _work(c.work)},
      UiEpisodeCard() => {
          'kind': 'episode',
          'work': _work(c.work),
          'episode': _episode(c.episode)
        },
      UiTaskCard() => {'kind': 'task', 'task': _task(c.task)},
      UiCandidatesCard() => {
          'kind': 'candidates',
          'items': [
            for (final i in c.items) {'work': _work(i.work), 'reason': i.reason}
          ]
        },
      UiPreparationCard() => {
          'kind': 'preparation',
          'title': c.title,
          'work': c.work == null ? null : _work(c.work!),
          'steps': [
            for (final s in c.steps)
              {
                'label': s.label,
                'state': s.state.name,
                'detail': s.detail,
                'progress': s.progress
              }
          ]
        },
    };
