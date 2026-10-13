import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/services/danmaku_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../capabilities/classic_action.dart';
import '../danmaku/files.dart';
import '../harness_hooks.dart';

final class SystemStorage implements Capability {
  SystemStorage(this.root, this.database, this.hooks);
  final Directory root;
  final Database database;
  final HarnessHooks hooks;
  final _plans = <String, JsonMap>{};
  Iterable<String> Function() libraryRoots = () => const [];
  bool Function() artworkBusy = () => false;
  bool Function() scanning = () => false;
  Future<void> _pending = Future.value();
  final _watches = <String, Timer>{};
  final _watchFacts = <String, JsonMap>{};
  final _watching = <String, Future<void>>{};
  final _activeWatches = <String>{};
  Future<void> close() async {
    for (final timer in _watches.values) {
      timer.cancel();
    }
    _watches.clear();
    _activeWatches.clear();
    await Future.wait(_watching.values.toList());
  }

  Future<bool> unwatch(String id) async {
    final timer = _watches.remove(id);
    timer?.cancel();
    _activeWatches.remove(id);
    await _watching[id];
    _watchFacts.remove(id);
    return timer != null;
  }

  Future<JsonMap> watch(JsonMap input) async {
    final app = (await directories())['app']!.path;
    final path = input['path'] as String? ?? app;
    if (path != app && !libraryRoots().contains(path)) {
      throw const Failure(FailureCode.invalidInput,
          'Use the app path or a registered library root from storage.status.');
    }
    final id = 'space-${DateTime.now().microsecondsSinceEpoch}';
    _activeWatches.add(id);
    final threshold = input['thresholdBytes'] as int;
    final interval = input['intervalMs'] as int? ?? 30000;
    var reading = false;
    Future<void> sample() async {
      if (reading) return;
      reading = true;
      try {
        final facts = await space(path);
        if (!_activeWatches.contains(id)) return;
        final available = facts['availableBytes'] as int?;
        final state = available == null
            ? 'unobserved'
            : available < threshold
                ? 'below'
                : 'above';
        final before = _watchFacts[id]?['state'];
        _watchFacts[id] = {
          'watchId': id,
          'state': state,
          'thresholdBytes': threshold,
          'intervalMs': interval,
          'observedAt': DateTime.now().toUtc().toIso8601String(),
          ...facts
        };
        if (state != before) {
          await hooks.emit('storage.space_changed', id, _watchFacts[id]!);
        }
      } finally {
        reading = false;
      }
    }

    await sample();
    _watches[id] = Timer.periodic(Duration(milliseconds: interval), (_) {
      final pending = sample();
      _watching[id] = pending;
      unawaited(pending.whenComplete(() {
        if (identical(_watching[id], pending)) _watching.remove(id);
      }));
    });
    return {
      'watch': _watchFacts[id],
      'lifetime': 'current process; explicit subscription only'
    };
  }

  static const disposable = [
    'classicDanmaku',
    'images',
    'thumbnails',
    'timeline',
    'nextDanmaku',
    'nextArtwork'
  ];

  Future<Map<String, Directory>> directories() async {
    final app = await StorageService.getAppStorageDirectory();
    return {
      'app': app,
      'next': root,
      'classicDanmaku': Directory('${app.path}/cache/danmaku'),
      'images': Directory('${app.path}/compressed_images'),
      'thumbnails': Directory('${app.path}/thumbnails'),
      'timeline': Directory('${app.path}/timeline_thumbnails'),
      'nextDanmaku': Directory('${root.path}/danmaku'),
      'nextArtwork': Directory('${root.path}/artwork'),
      'subtitles': Directory('${root.path}/subtitles'),
      'meshAssets': Directory('${root.path}/mesh-assets'),
      'meshArtwork': Directory('${root.path}/mesh-artwork'),
      'downloads': Directory('${app.path}/downloads')
    };
  }

  Future<List<JsonMap>> files(Directory dir) async {
    final rows = <JsonMap>[];
    if (!await dir.exists()) return rows;
    await for (final entry in dir.list(recursive: true, followLinks: false)) {
      final stat = await FileSystemEntity.type(entry.path, followLinks: false);
      if (stat != FileSystemEntityType.file) continue;
      final value = await entry.stat();
      rows.add({
        'path': entry.path,
        'bytes': value.size,
        'modified': value.modified.microsecondsSinceEpoch
      });
    }
    return rows;
  }

  Future<JsonMap> space(String path) async {
    try {
      if (Platform.isMacOS) {
        return Map<String, Object?>.from(
            await const MethodChannel('nipaplay/instance')
                    .invokeMapMethod<String, Object?>(
                        'storageSpace', {'path': path}) ??
                {});
      }
      if (Platform.isLinux) {
        final result = await Process.run('df', ['-Pk', path]);
        if (result.exitCode != 0) {
          return {'path': path, 'availableBytes': null, 'error': 'stat_failed'};
        }
        final columns = (result.stdout as String)
            .trim()
            .split('\n')
            .last
            .trim()
            .split(RegExp(r'\s+'));
        return {
          'path': path,
          'availableBytes': int.parse(columns[3]) * 1024,
          'totalBytes': int.parse(columns[1]) * 1024
        };
      }
      return {
        'path': path,
        'availableBytes': null,
        'error': 'host_not_supported'
      };
    } on PlatformException catch (error) {
      return {'path': path, 'availableBytes': null, 'error': error.code};
    } on MissingPluginException {
      return {
        'path': path,
        'availableBytes': null,
        'error': 'host_not_attached'
      };
    }
  }

  Future<JsonMap> status() async {
    final dirs = await directories();
    final roots = libraryRoots().where((path) => p.isAbsolute(path)).toSet();
    for (final path in roots) {
      dirs['library:$path'] = Directory(path);
    }
    final observations = <JsonMap>[];
    for (final entry in dirs.entries) {
      int? bytes;
      JsonMap? error;
      try {
        bytes = (await files(entry.value))
            .fold<int>(0, (n, r) => n + (r['bytes'] as int));
      } on FileSystemException {
        error = {
          'code': 'directory_unreadable',
          'retryable': true,
          'recoveryAction':
              'Check volume availability and filesystem permission.'
        };
      }
      observations.add({
        'role': entry.key,
        'path': entry.value.path,
        'bytes': bytes,
        'error': error,
        'disposable': disposable.contains(entry.key),
        'uniqueData': entry.key == 'nextDanmaku' ||
            entry.key == 'nextArtwork' ||
            !disposable.contains(entry.key),
        'overlap': entry.key == 'app' || entry.key == 'next'
            ? 'includes children; do not sum directories'
            : null
      });
    }
    return {
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'directories': observations,
      'volumes': [
        await space(dirs['app']!.path),
        for (final path in roots) await space(path)
      ],
      'preservation':
          'Imports, artwork, mesh assets, databases and user downloads are retained. nextDanmaku contains both cache and unique imports; prune checks storage_kind.'
    };
  }

  Future<JsonMap> plan(JsonMap input) async {
    final dirs = await directories();
    final kinds = (input['kinds'] as List? ?? disposable)
        .cast<String>()
        .map((kind) => kind == 'artwork' ? 'nextArtwork' : kind)
        .toSet();
    final entries = <JsonMap>[], retained = <JsonMap>[];
    final chunks = await database.query('danmaku_cache_chunks');
    final importedPaths = chunks
        .where((r) => r['storage_kind'] == 'imported')
        .map((r) => r['file_path'])
        .toSet();
    final seenPaths = <Object?>{};
    final recoverableArtwork = await _recoverableArtwork();
    for (final kind in kinds) {
      if (kind == 'nextDanmaku') {
        for (final row in chunks) {
          final item = {
            'kind': kind,
            'cacheKey': row['cache_key'],
            'path': row['file_path'],
            'bytes': row['byte_count']
          };
          if (importedPaths.contains(row['file_path'])) {
            retained.add({...item, 'reason': 'unique_import'});
          } else if (seenPaths.add(row['file_path'])) {
            entries.add(item);
          }
        }
      } else if (kind == 'nextArtwork' || kind == 'artwork') {
        for (final file in await files(dirs[kind]!)) {
          if (recoverableArtwork.contains(file['path'])) {
            entries.add({'kind': 'nextArtwork', ...file});
          } else {
            retained.add({
              'kind': kind,
              ...file,
              'reason': 'unique_or_source_unknown',
              'deletionRequiresDecision': true
            });
          }
        }
      } else if (disposable.contains(kind)) {
        for (final file in await files(dirs[kind]!)) {
          // Pending writes are never a cache reclamation target.
          if ((file['path'] as String).endsWith('.pending')) continue;
          entries.add({'kind': kind, ...file});
        }
      } else {
        for (final file in await files(dirs[kind]!)) {
          retained.add({
            'kind': kind,
            ...file,
            'reason': 'unique_or_reference_not_proven_disposable',
            'deletionRequiresDecision': true
          });
        }
      }
    }
    final id = sha256
        .convert(utf8.encode(
            jsonEncode([DateTime.now().microsecondsSinceEpoch, entries])))
        .toString();
    final result = <String, Object?>{
      'planId': id,
      'entries': entries,
      'retained': retained,
      'nextDanmakuKeys': chunks
          .where((r) => r['storage_kind'] != 'imported')
          .map((r) => r['cache_key'])
          .toSet()
          .toList(),
      'reclaimableBytes':
          entries.fold<int>(0, (n, e) => n + (e['bytes'] as int? ?? 0)),
      'maxBytes': (input['maxBytes'] as num?)?.toInt() ?? 0,
      'scope': 'recoverable caches only; user files excluded',
      'activeReferences':
          'At prune time: Next fetches defer collection; displayed image/thumbnail caches are retained while playback runs.'
    };
    _plans[id] = result;
    return result;
  }

  bool Function() playbackActive = () => false;
  Future<Set<String>> _recoverableArtwork() async {
    final urls = <String>{}, protected = <String>{};
    void visit(Object? value) {
      if (value is Map) {
        for (final v in value.values) {
          visit(v);
        }
      }
      if (value is List) {
        for (final v in value) {
          visit(v);
        }
      }
      if (value is String) {
        final uri = Uri.tryParse(value);
        if (uri != null &&
            {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty) {
          urls.add(value);
        }
        if (p.isAbsolute(value)) protected.add(p.normalize(value));
      }
    }

    for (final row
        in await database.query('media_snapshots', columns: ['fields'])) {
      visit(jsonDecode(row['fields'] as String));
    }
    for (final row
        in await database.query('media_overrides', columns: ['value'])) {
      visit(jsonDecode(row['value'] as String));
    }
    return {
      for (final url in urls)
        '${root.path}/artwork/${sha256.convert(utf8.encode(url))}${Uri.parse(url).path.endsWith('.png') ? '.png' : '.jpg'}'
    }.difference(protected);
  }

  Future<JsonMap> prune(String id) {
    final run = _pending.then((_) => _prune(id));
    _pending = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run;
  }

  Future<JsonMap> _prune(String id) async {
    return DanmakuCacheManager.maintainRecoverableCache(() => _pruneFiles(id));
  }

  Future<JsonMap> _pruneFiles(String id) async {
    final plan = _plans[id];
    if (plan == null) {
      throw const Failure(FailureCode.notFound,
          'Cache plan not found in this process. Create a new plan.');
    }
    final results = <JsonMap>[];
    var removed = 0;
    final entries = (plan['entries'] as List).cast<JsonMap>();
    final total = entries.fold<int>(0, (n, e) => n + (e['bytes'] as int? ?? 0));
    final otherBytes = entries
        .where((e) => e['kind'] != 'nextDanmaku')
        .fold<int>(0, (n, e) => n + (e['bytes'] as int));
    if (entries.any((e) => e['kind'] == 'nextDanmaku')) {
      final result = await DanmakuFiles(database).prune(
          maxBytes: ((plan['maxBytes'] as int) - otherBytes)
              .clamp(0, plan['maxBytes'] as int),
          cacheKeys: (plan['nextDanmakuKeys'] as List).cast<String>().toSet());
      removed += result['reclaimedBytes'] as int;
      results.add({'kind': 'nextDanmaku', ...result});
    }
    var remaining = total - removed;
    for (final entry in entries.where((e) => e['kind'] != 'nextDanmaku')) {
      if (remaining <= (plan['maxBytes'] as int)) break;
      final path = entry['path'] as String;
      bool busy() =>
          playbackActive() ||
          const {'images', 'thumbnails', 'timeline'}.contains(entry['kind']) &&
              scanning() ||
          entry['kind'] == 'images' &&
              (ImageCacheManager.instance.hasDiskActivity ||
                  ImageCacheManager.instance.diskFileReferenced(path));
      if (busy() ||
          entry['kind'] == 'nextArtwork' &&
              (artworkBusy() ||
                  !(await _recoverableArtwork()).contains(path))) {
        results
            .add({'path': path, 'removed': false, 'reason': 'active_playback'});
        continue;
      }
      try {
        if (await FileSystemEntity.type(path, followLinks: false) !=
            FileSystemEntityType.file) {
          results.add(
              {'path': path, 'removed': false, 'reason': 'changed_or_missing'});
          continue;
        }
        final file = File(path), stat = await File(path).stat();
        if (stat.size != entry['bytes'] ||
            stat.modified.microsecondsSinceEpoch != entry['modified']) {
          results.add({
            'path': path,
            'removed': false,
            'reason': 'changed_since_preview'
          });
          continue;
        }
        if (busy()) {
          results.add({
            'path': path,
            'removed': false,
            'reason': 'active_reference_or_write'
          });
          continue;
        }
        await file.delete();
        removed += stat.size;
        remaining -= stat.size;
        results.add({'path': path, 'removed': true, 'bytes': stat.size});
      } on FileSystemException {
        results.add(
            {'path': path, 'removed': false, 'reason': 'filesystem_failed'});
      }
    }
    _plans.remove(id);
    final result = {
      'planId': id,
      'removedBytes': removed,
      'results': results,
      'retained': plan['retained']
    };
    await hooks.emit('cache.pruned', id, result);
    return result;
  }

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'storage.watch',
                title: '订阅空间阈值变化',
                description:
                    '显式订阅应用卷或已登记根目录的空闲字节阈值。首次观察和 above/below/unobserved 转换发 storage.space_changed，可触发 hook/后续。仅当前进程有效，不自动订阅。',
                effect: Effect.write,
                input: ObjectSchema({
                  'path': StringSchema(minLength: 1),
                  'thresholdBytes': IntegerSchema(minimum: 0),
                  'intervalMs': IntegerSchema(minimum: 1000, maximum: 86400000)
                }, required: [
                  'thresholdBytes'
                ]),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => watch(input)),
        ClassicAction(
            const ActionSpec(
                id: 'storage.unwatch',
                title: '取消空间订阅',
                description: '停止当前进程的指定阈值订阅，不删除日志或缓存。',
                effect: Effect.write,
                input: ObjectSchema({'watchId': StringSchema(minLength: 1)},
                    required: ['watchId']),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async {
          return {
            'watchId': input['watchId'],
            'cancelled': await unwatch(input['watchId'] as String)
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'storage.status',
                title: '全局空间与缓存事实',
                description:
                    '读取应用、Next、缓存、附件、下载目录实际字节与所在卷可用容量。父目录包含子目录，不能相加。符号链接不遍历。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) => status()),
        ClassicAction(
            const ActionSpec(
                id: 'cache.plan',
                title: '分类缓存回收预览',
                description:
                    '预览可重取缓存和保留的唯一副本。maxBytes 是每个缓存池保留预算，默认 0。计划仅当前进程可用；用户文件、字幕和来源图片不会当作缓存删除。',
                effect: Effect.read,
                input: ObjectSchema({
                  'kinds': ArraySchema(
                      StringSchema(values: [
                        ...disposable,
                        'artwork',
                        'subtitles',
                        'meshAssets',
                        'meshArtwork',
                        'downloads'
                      ]),
                      minItems: 1),
                  'maxBytes': IntegerSchema(minimum: 0)
                }),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => plan(input)),
        ClassicAction(
            const ActionSpec(
                id: 'cache.prune',
                title: '回收预览中的可重取缓存',
                description:
                    '执行 cache.plan；重新核对文件变化与引用，逐项保留失败事实。仅回收可重新取得的缓存，无 NeedsDecision。唯一导入、用户文件和播放中的缓存保留。',
                effect: Effect.write,
                input: ObjectSchema({'planId': StringSchema(minLength: 1)},
                    required: ['planId']),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => prune(input['planId'] as String)),
      ];
}
