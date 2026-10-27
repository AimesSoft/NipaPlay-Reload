import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/utils/linux_storage_migration.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:url_launcher/url_launcher.dart';
import '../capabilities/classic_action.dart';
import '../harness_redaction.dart';
import '../media/media_service.dart';
import '../network/observations.dart';
import '../settings/system_settings.dart';
import '../settings/registry.dart';
import 'storage.dart';
import 'alpha_updates.dart';

final class SystemDiagnostics implements Capability {
  SystemDiagnostics(
      this.database, this.media, this.storage, this.automatic, this.settings);
  final Database database;
  final MediaService media;
  final SystemStorage storage;
  final SystemSettings automatic;
  final SettingsRegistry settings;
  Future<JsonMap> Function() playerFacts =
      () async => {'available': false, 'reason': 'player_host_not_attached'};
  Future<JsonMap>? _checking;
  JsonMap? _update;
  Future<JsonMap> checkUpdate() {
    return _checking ??= _checkUpdate().whenComplete(() => _checking = null);
  }

  Future<JsonMap> _checkUpdate() async {
    final info = await checkNextUpdate();
    final url = Uri.tryParse(info.releaseUrl);
    final safeRelease = url != null &&
        url.scheme == 'https' &&
        url.host == 'github.com' &&
        url.path.startsWith('/AimesSoft/NipaPlay-Reload/releases/') &&
        url.userInfo.isEmpty &&
        !url.hasQuery &&
        !url.hasFragment;
    _update = publicHarnessFacts({
      'currentVersion': info.currentVersion,
      'latestVersion': info.error == null ? info.latestVersion : null,
      'hasUpdate': info.error == null ? info.hasUpdate : null,
      'releaseName': info.releaseName,
      'releaseNotes': info.releaseNotes,
      'publishedAt': info.publishedAt,
      'publicReleaseUrl': safeRelease ? info.releaseUrl : null,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'error': info.error == null
          ? null
          : {
              'code': 'update_check_failed',
              'stage': 'release_lookup',
              'message': SecretRedactor.text(info.error!),
              'retryable': true
            },
      'installationSupported': false
    }) as JsonMap;
    return _update!;
  }

  Future<JsonMap> fileLogs(JsonMap input) async {
    final path = await FileLogService().getLogDirectoryPath();
    if (path == null) {
      return {
        'files': [],
        'lines': [],
        'nextCursor': null,
        'reason': 'file_logs_unavailable'
      };
    }
    final dir = Directory(path);
    final candidates = <File>[];
    if (await dir.exists()) {
      await for (final entry in dir.list(followLinks: false)) {
        if (await FileSystemEntity.type(entry.path, followLinks: false) ==
                FileSystemEntityType.file &&
            p.extension(entry.path) == '.log') {
          candidates.add(File(entry.path));
        }
      }
    }
    candidates.sort((a, b) => b.path.compareTo(a.path));
    final id = input['fileId'] as String?;
    final file = id == null
        ? candidates.firstOrNull
        : candidates.where((f) => p.basename(f.path) == id).firstOrNull;
    if (id != null && file == null) {
      throw const Failure(FailureCode.notFound,
          'Log fileId is not in the current log directory.');
    }
    final output = <String, Object?>{
      'files': [
        for (final f in candidates)
          {'fileId': p.basename(f.path), 'bytes': await f.length()}
      ],
      'lines': <String>[],
      'nextCursor': null
    };
    if (file == null) return output;
    final offset = (input['cursor'] as num?)?.toInt() ?? 0,
        limit = (input['limit'] as num?)?.toInt() ?? 100;
    final length = await file.length();
    final lines = <String>[];
    var consumed = 0, characters = 0, privateKey = false, hasMore = false;
    // Read preceding lines too, so a cursor inside a PEM block cannot expose it.
    await for (final raw in file
        .openRead(0, length)
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())) {
      if (RegExp(r'-----BEGIN .*PRIVATE KEY-----').hasMatch(raw)) {
        privateKey = true;
      }
      final line =
          privateKey ? '[redacted private key]' : redactHarnessText(raw);
      if (RegExp(r'-----END .*PRIVATE KEY-----').hasMatch(raw)) {
        privateKey = false;
      }
      if (consumed < offset) {
        consumed++;
        continue;
      }
      if (lines.length >= limit || characters >= 256 * 1024) {
        hasMore = true;
        break;
      }
      consumed++;
      if (input['filter'] == null || line.contains(input['filter'] as String)) {
        final bounded = line.length > 16384
            ? '${line.substring(0, 16384)}[truncated]'
            : line;
        lines.add(bounded);
        characters += bounded.length;
      }
    }
    if (consumed < offset) {
      throw const Failure(FailureCode.conflict,
          'Log was rotated or truncated; read from cursor 0.');
    }
    output.addAll({
      'fileId': p.basename(file.path),
      'lines': lines,
      'nextCursor': hasMore ? consumed : null,
      'snapshotBytes': length,
      'cursorUnit': 'lines'
    });
    return output;
  }

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.status',
                title: '健康检查与运行诊断',
                description:
                    '读取 SQLite quick_check、实际后台任务、内存、平台版本、日志、来源最近失败及迁移状态。player 给播放器简要事实；player.details 与 playback.info 来自同一次内核查询：videoCodec、audioCodec、videoWidth、videoHeight、fps、hwdec（正在使用的硬解方式，软解为 no）、decoder、hardwareDecoding、droppedFrames、buffering，内核未提供的为 null。无自动修复、不返回播放器实际认证 URL。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          final build = await PackageInfo.fromPlatform();
          return {
            'observedAt': DateTime.now().toUtc().toIso8601String(),
            'build': {
              'version': build.version,
              'buildNumber': build.buildNumber,
              'packageName': build.packageName
            },
            'dependencies': {
              'dart': Platform.version.split(' ').first,
              'os': Platform.operatingSystem,
              'osVersion': Platform.operatingSystemVersion,
              'torrent': 'bundled librqbit',
              'unobservedVersions': [
                'Flutter engine',
                'player native libraries'
              ]
            },
            'resources': {
              'processId': pid,
              'rssBytes': ProcessInfo.currentRss,
              'maxRssBytes': ProcessInfo.maxRss
            },
            'player': await playerFacts(),
            'health': {
              'database': await database.rawQuery('PRAGMA quick_check'),
              'pendingProjections':
                  (await media.store.pendingProjections()).length,
              'networkFailures': NetworkObservations.facts
                  .where((r) => r['error'] != null)
                  .toList()
            },
            'logs': {
              'collecting': DebugLogService().isCollecting,
              'fileWriterRunning': FileLogService().isRunning
            },
            'storageMigration': Platform.isLinux
                ? {
                    'needed': await LinuxStorageMigration.needsMigration(),
                    'applySupported': false,
                    'reason':
                        'Personal-file migration needs a per-file conflict and recovery plan.'
                  }
                : {'applicable': false},
            'recoveries': [
              'logs.restart',
              'media.projections.reconcile',
              'indexers.reconcile'
            ]
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.file_logs',
                title: '脱敏持久日志摘录',
                description:
                    '只读取当前文件日志目录中列出的 fileId。cursor 为行偏移，单页最多 256 KiB；先脱敏再过滤，私钥块跨页也隐藏。不会上传或分享日志。',
                effect: Effect.read,
                input: ObjectSchema({
                  'fileId': StringSchema(minLength: 1),
                  'cursor': IntegerSchema(minimum: 0),
                  'limit': IntegerSchema(minimum: 1, maximum: 1000),
                  'filter': StringSchema()
                }),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => fileLogs(input)),
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.recover',
                title: '运行常见恢复操作',
                description:
                    '显式重启日志写入、排空持久投影 outbox 或立即检查自动索引器。保留用户文件、设置、任务和历史；不自动改变登录、迁移或路由。',
                effect: Effect.write,
                input: ObjectSchema({
                  'operation': StringSchema(values: [
                    'logs.restart',
                    'media.projections.reconcile',
                    'indexers.reconcile'
                  ])
                }, required: [
                  'operation'
                ]),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async {
          switch (input['operation']) {
            case 'logs.restart':
              await FileLogService().stop();
              final enabled = await SettingsStorage.loadBool('enable_file_log',
                  defaultValue: true);
              if (enabled) await FileLogService().start();
              return {
                'enabled': enabled,
                'running': FileLogService().isRunning
              };
            case 'media.projections.reconcile':
              await media.mutate(() => media.projection.drain());
              return {
                'remaining': (await media.store.pendingProjections()).length
              };
            default:
              await automatic.sidecars.reconcile();
              await automatic.subtitles.reconcile();
              return {
                'workers': [
                  automatic.sidecars.status,
                  automatic.subtitles.status
                ]
              };
          }
        }),
        ClassicAction(
            const ActionSpec(
                id: 'media.indexers.status',
                title: '自动行为实际状态',
                description:
                    '读取独立开关、队列、正在排空的文件、上次运行和错误。策略值与工作器生效状态分别返回。Next 启动只索引本地文件，识别与弹幕获取由 Agent 显式调用。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async => {
                  'workers': [
                    automatic.sidecars.status,
                    automatic.subtitles.status
                  ],
                  'startupScan': {
                    'enabled': automatic.startupScanEnabled,
                    'applies':
                        'Next local file indexing only; no Classic recognition',
                    'lastRun': automatic.startupScanStatus,
                    'stopsRunningScan': false
                  },
                  'policies': {
                    for (final key in [
                      'danmaku.autoLoadStrategy',
                      'danmaku.skipMatching',
                      'download.autoScanCompletedTasks'
                    ])
                      key: await settings.get(key)
                  },
                }),
        ClassicAction(
            const ActionSpec(
                id: 'app.update.check',
                title: '立即检查应用更新',
                description:
                    '复用 Classic GitHub 发布客户端立即检查。失败的 hasUpdate/latestVersion 为 null，保留错误与检查时间；只查发布信息，不下载安装或重启。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) => checkUpdate()),
        ClassicAction(
            const ActionSpec(
                id: 'app.update.status',
                title: '上次更新检查',
                description: '读取本次进程最后一次显式更新检查；尚未检查时 checked=false。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async => {
                  'checking': _checking != null,
                  'checked': _update != null,
                  'result': _update
                }),
        ClassicAction(
            const ActionSpec(
                id: 'app.update.open',
                title: '打开已核对的发布页',
                description:
                    '打开本次进程 app.update.check 已核对的公开 GitHub 发布页。未成功检查时拒绝；不下载、安装或重启。',
                effect: Effect.write,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          final url = _update?['publicReleaseUrl'] as String?;
          if (url == null || _update?['error'] != null) {
            throw const Failure(FailureCode.conflict,
                'No verified release page. Run app.update.check.');
          }
          return {
            'opened': await launchUrl(Uri.parse(url),
                mode: LaunchMode.externalApplication),
            'publicReleaseUrl': url
          };
        }),
      ];
}
