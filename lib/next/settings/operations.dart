import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/backup_service.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:path/path.dart' as p;

import 'classic_settings.dart';
import 'registry.dart';
import 'denylist.dart';

const _path = StringSchema(minLength: 1);
const _id = StringSchema(minLength: 1);
const _output = ObjectSchema({}, additionalProperties: true);
final _categories = ArraySchema(
    StringSchema(values: BackupCategory.values.map((e) => e.name).toList()));

final class ClassicOperations implements Capability {
  ClassicOperations(this.registry,
      {FullBackupService? backup,
      BackupService? history,
      DebugLogService? logs,
      Future<void> Function()? reloadHistory})
      : backup = backup ?? FullBackupService(allowInlineCredentials: false),
        history = history ?? BackupService(),
        logs = logs ?? DebugLogService(),
        reloadHistory = reloadHistory ??
            (() async {
              ServiceProvider.watchHistoryProvider.clearInvalidPathCache();
              await ServiceProvider.watchHistoryProvider.loadHistory();
            }) {
    actions = [
      _action(
          'backup.export',
          '导出全量备份',
          Effect.write,
          {'path': _path, 'categories': _categories},
          ['path', 'categories'],
          '写入 Classic .npb 文件。类别可选 preferences、mediaLibraries、watchHistory、episodeMatches、accounts。凭据沿用 Classic 的便携引用，不导出登录秘密；不覆盖已有文件。',
          (input) async {
        final path = await destination(input['path'] as String);
        final exported = await this
            .backup
            .exportBackupToFile(filePath: path, categories: categories(input));
        if (exported == null) {
          throw const Failure(
              FailureCode.unavailable, 'Classic backup export failed.');
        }
        return {'path': exported, 'bytes': await File(exported).length()};
      }),
      _action('backup.preview', '预览全量备份', Effect.read, {'path': _path},
          ['path'], '读取备份版本、类别与记录数量，不执行恢复。', (input) async {
        final path =
            await ClassicSettings.authorizedPath(input['path'] as String);
        final preview = await this.backup.previewBackup(path);
        if (preview == null) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid Classic backup.');
        }
        return {
          'version': preview.version,
          'timestamp': preview.timestamp,
          'appVersion': preview.appVersion,
          'categories': [
            if (preview.hasPreferences) 'preferences',
            if (preview.hasMediaLibraries) 'mediaLibraries',
            if (preview.hasWatchHistory) 'watchHistory',
            if (preview.hasEpisodeMatches) 'episodeMatches',
            if (preview.hasAccounts) 'accounts'
          ],
          'watchHistoryCount': preview.watchHistoryCount,
          'episodeMatchCount': preview.episodeMatchCount,
          'serverProfileCount': preview.serverProfileCount,
          'localLibraryCount': preview.localLibraryCount,
          'webdavConnectionCount': preview.webdavConnectionCount,
          'smbConnectionCount': preview.smbConnectionCount
        };
      }),
      _action(
          'backup.restore',
          '恢复全量备份',
          Effect.destructive,
          {'path': _path, 'categories': _categories},
          ['path', 'categories'],
          '按选定类别调用 Classic .npb 恢复，会合并或改写持久数据。禁止设置保留现值并返回 forbidden_setting；注册设置经过 settings.set 的 Classic 校验与交互。凭据只能恢复本机已有引用，不能输入新的登录秘密。返回各类别实际结果；部分服务需要重启应用生效。来源记录保留本次调用者、时间与原因。',
          (input) async {
        final path =
            await ClassicSettings.authorizedPath(input['path'] as String);
        final preview = await this.backup.previewBackup(path);
        if (preview == null || preview.version > 2) {
          throw const Failure(
              FailureCode.invalidInput, 'Invalid or unsupported backup.');
        }
        final result = await this
            .backup
            .importBackup(filePath: path, categories: categories(input),
                preferenceKeyAllowed: (key) => !isSettingDenied(key),
                preferenceRestorer: (storageKey, value) async {
                  final entries = registry.entries.where(
                      (entry) => entry.storageKey == storageKey).toList();
                  if (entries.isEmpty) return false;
                  final invocation = Zone.current[SettingsAccess.invocationKey] as Invocation;
                  for (final entry in entries) {
                    final restored = entry.decodeStorage(value);
                    if (jsonEncode(await entry.read()) == jsonEncode(restored)) continue;
                    await registry.set(entry.key, restored, invocation,
                        reason: Zone.current[SettingsAccess.reasonKey] as String?);
                  }
                  return true;
                });
        if (result.watchHistoryResult != null || result.episodeMatchesResult != null) {
          await this.reloadHistory();
        }
        return {
          'success': result.success,
          'status': result.status,
          'error': result.errorMessage,
          'restoredCount': result.totalRestoredCount,
          'skippedCount': result.totalSkippedCount,
          'apply': 'restart_app',
          'categories': {
            if (result.preferencesResult != null)
              'preferences': categoryResult(result.preferencesResult!),
            if (result.mediaLibrariesResult != null)
              'mediaLibraries': categoryResult(result.mediaLibrariesResult!),
            if (result.watchHistoryResult != null)
              'watchHistory': categoryResult(result.watchHistoryResult!),
            if (result.episodeMatchesResult != null)
              'episodeMatches': categoryResult(result.episodeMatchesResult!),
            if (result.accountsResult != null)
              'accounts': categoryResult(result.accountsResult!),
          },
        };
      }),
      _action('backup.history_export', '导出观看进度', Effect.write, {'path': _path},
          ['path'], '通过 Classic 导出 .nph 观看历史；不覆盖已有文件。', (input) async {
        final path = await destination(input['path'] as String);
        final result = await this.history.exportWatchHistoryToFile(path);
        if (result == null) {
          throw const Failure(FailureCode.unavailable, 'No history exported.');
        }
        return {'path': result, 'bytes': await File(result).length()};
      }),
      _action(
          'backup.history_restore',
          '恢复观看进度',
          Effect.destructive,
          {'path': _path},
          ['path'],
          '通过 Classic 从 .nph 恢复观看历史，会改写已有观看进度；沿用本地文件存在性检查。', (input) async {
        final path =
            await ClassicSettings.authorizedPath(input['path'] as String);
        final count = await this.history.importWatchHistory(path);
        await this.reloadHistory();
        return {'restoredCount': count};
      }),
      _action('plugins.list', '查询已安装插件', Effect.read, {}, [],
          '返回安装、启用、载入、错误、版本与插件 UI 动作。插件开关和非秘密文本设置在 settings.describe 的 plugins 域。',
          (_) async {
        await ClassicSettings.current.plugins.ready;
        return {
          'plugins': [
            for (final plugin in ClassicSettings.current.plugins.plugins)
              describePlugin(plugin)
          ]
        };
      }),
      _action(
          'plugins.market',
          '查询市场与更新',
          Effect.read,
          {'refresh': const BooleanSchema()},
          [],
          '复用 Classic 插件索引与 GitHub 代理；refresh=true 时刷新远程索引。', (input) async {
        final service = ClassicSettings.current.plugins;
        await service.ready;
        if (input['refresh'] == true) {
          await service.fetchRemotePlugins(
              proxyUrl: (await registry.get('plugins.githubProxyUrl'))['value']
                  as String);
        }
        return {
          'plugins': [
            for (final plugin in service.remotePlugins.values)
              {...plugin.toJson(), 'downloadUrl': plugin.resolvedDownloadUrl}
          ],
          'updates': {
            for (final plugin in service.plugins)
              plugin.manifest.id:
                  service.getAvailableUpdateVersion(plugin.manifest.id)
          }
        };
      }),
      _action(
          'plugins.install',
          '安装或更新插件',
          Effect.destructive,
          {'path': _path, 'remoteId': _id, 'updateForId': _id},
          [],
          '从已授权的本地 .js 文件或 Classic 市场 remoteId 安装/更新插件。必须恰好提供 path 或 remoteId。安装会执行插件代码；同标识更新可改写脚本。改变既有插件标识时，先 plugins.delete 并等待用户在应用内同意，再安装新插件；安装不能静默删除旧脚本。',
          (input) async {
        if (input.containsKey('path') == input.containsKey('remoteId')) {
          throw const Failure(
              FailureCode.invalidInput, 'Use path or remoteId.');
        }
        final service = ClassicSettings.current.plugins;
        await service.ready;
        final String? id;
        if (input.containsKey('path')) {
          final path =
              await ClassicSettings.authorizedPath(input['path'] as String);
          id = await service.importPluginFromContent(
              await File(path).readAsString(),
              updateForId: input['updateForId'] as String?, allowScriptRemoval: false);
        } else {
          id = await service.installRemotePlugin(input['remoteId'] as String,
              proxyUrl: (await registry.get('plugins.githubProxyUrl'))['value']
                  as String,
              updateForId: input['updateForId'] as String?, allowScriptRemoval: false);
        }
        if (id == null) {
          throw const Failure(FailureCode.unavailable,
              'Classic could not load the imported plugin.');
        }
        return describePlugin(plugin(id));
      }),
      _action(
          'plugins.set_enabled',
          '启用或停用插件',
          Effect.write,
          {'id': _id, 'enabled': const BooleanSchema()},
          ['id', 'enabled'],
          '复用 Classic 插件生命周期和启用列表；返回实际载入状态，载入错误不会被当作成功运行。', (input) async {
        final id = input['id'] as String;
        plugin(id);
        final invocation =
            Zone.current[SettingsAccess.invocationKey] as Invocation;
        await registry.set('plugins.enabled.${Uri.encodeComponent(id)}',
            input['enabled'], invocation,
            reason: Zone.current[SettingsAccess.reasonKey] as String?);
        return describePlugin(plugin(id));
      }),
      _action('plugins.delete', '删除插件', Effect.destructive, {'id': _id}, ['id'],
          '停用并删除本地插件脚本和索引；Classic 内置插件不能删除。', (input) async {
        final id = input['id'] as String;
        final descriptor = plugin(id);
        if (descriptor.isBuiltin) {
          throw const Failure(
              FailureCode.invalidInput, 'Builtin plugins cannot be deleted.');
        }
        final deleted = await ClassicSettings.current.plugins.deletePlugin(id);
        if (!deleted) {
          throw const Failure(
              FailureCode.unavailable, 'Plugin deletion failed.');
        }
        if (descriptor.assetPath.startsWith('file:') &&
            await File(descriptor.assetPath.substring(5)).exists()) {
          throw const Failure(FailureCode.unavailable,
              'The plugin was unloaded but its script file was not deleted.');
        }
        return {'id': id, 'deleted': true};
      }),
      _action(
          'plugins.invoke',
          '执行插件 UI 动作',
          Effect.destructive,
          {'id': _id, 'actionId': _id},
          ['id', 'actionId'],
          '调用已启用插件的 Classic UI 动作。插件决定副作用，因此按 destructive 标注；登录秘密由用户在 GUI 中输入。',
          (input) async {
        final id = input['id'] as String,
            actionId = input['actionId'] as String;
        if (!plugin(id).uiEntries.any((e) => e.id == actionId && e.isAction)) {
          throw const Failure(FailureCode.notFound, 'Plugin action not found.');
        }
        final result = await ClassicSettings.current.plugins
            .invokePluginUiAction(id, actionId);
        return {
          'id': id,
          'actionId': actionId,
          'result': result == null
              ? null
              : {
                  'type': result.type,
                  'title': result.title,
                  'content': SecretRedactor.text(result.content)
                }
        };
      }),
      _action(
          'diagnostics.logs',
          '读取诊断日志',
          Effect.read,
          {
            'tag': const StringSchema(),
            'level': const StringSchema(),
            'offset': const IntegerSchema(minimum: 0),
            'limit': const IntegerSchema(minimum: 1, maximum: 1000)
          },
          [],
          '读取 Classic 已收集的日志与统计，按 tag/level 过滤并分页。秘密沿用 Classic 的日志脱敏。',
          (input) async {
        final rows = this
            .logs
            .logEntries
            .where((e) =>
                (input['tag'] == null || input['tag'] == e.tag) &&
                (input['level'] == null || input['level'] == e.level))
            .toList();
        final offset = (input['offset'] as num?)?.toInt() ?? 0,
            limit = (input['limit'] as num?)?.toInt() ?? 100;
        return {
          'statistics': this.logs.getLogStatistics(),
          'collecting': this.logs.isCollecting,
          'logs': [
            for (final entry in rows.skip(offset).take(limit))
              {
                'timestamp': entry.timestamp.toUtc().toIso8601String(),
                'tag': entry.tag,
                'level': entry.level,
                'message': SecretRedactor.text(entry.message)
              }
          ],
          'nextOffset': offset + limit < rows.length ? offset + limit : null
        };
      }),
      _action(
          'diagnostics.export',
          '导出诊断日志',
          Effect.write,
          {'path': _path},
          ['path'],
          '使用 Classic exportLogs 输出脱敏文本到已授权文件；不覆盖已有文件。', (input) async {
        final path = await destination(input['path'] as String);
        await File(path).writeAsString(
            SecretRedactor.text(this.logs.exportLogs()),
            flush: true);
        return {
          'path': path,
          'entries': this.logs.logCount,
          'bytes': await File(path).length()
        };
      }),
      _action('diagnostics.clear', '清空诊断日志', Effect.destructive, {}, [],
          '清空 Classic 内存日志缓冲；沿用 Classic 的“日志已清空”记录。', (_) async {
        this.logs.clearLogs();
        return {'entries': this.logs.logCount};
      }),
      _action(
          'diagnostics.directory',
          '查询日志目录',
          Effect.read,
          {},
          [],
          '返回 Classic 日志文件目录。',
          (_) async => {'path': await FileLogService().getLogDirectoryPath()}),
      _action('webdav_quick.reset', '重置 WebDAV 快捷设置', Effect.destructive, {},
          [], '调用 Classic 子页的重置操作，恢复全部 20 个持久键（包括共享默认主页），保留来源记录。', (_) async {
        await ClassicSettings.current.webdav.resetSettings();
        return {'reset': true};
      }),
      _action('appearance.reset_home_sections', '重置首页分区', Effect.write, {}, [],
          '调用 Classic 的首页分区恢复默认操作。', (_) async {
        await ClassicSettings.current.home.restoreDefaults();
        return {'reset': true};
      }),
      _action('shortcuts.reset', '恢复默认快捷键', Effect.write, {}, [],
          '通过注册表恢复全部 19 个 Classic 快捷键默认值，保留每项来源记录。', (_) async {
        final invocation =
            Zone.current[SettingsAccess.invocationKey] as Invocation;
        final entries =
            registry.entries.where((e) => e.domain == 'shortcuts').toList();
        for (final entry in entries) {
          await registry.set(entry.key, entry.defaultValue, invocation,
              reason: Zone.current[SettingsAccess.reasonKey] as String?);
        }
        return {'resetCount': entries.length};
      }),
    ];
  }
  final SettingsRegistry registry;
  final FullBackupService backup;
  final BackupService history;
  final DebugLogService logs;
  final Future<void> Function() reloadHistory;
  @override
  late final List<Action> actions;

  _Operation _action(
          String id,
          String title,
          Effect effect,
          Map<String, Schema> properties,
          List<String> required,
          String description,
          Future<JsonMap> Function(JsonMap) run) =>
      _Operation(id, title, effect,
          ObjectSchema(properties, required: required), description, run);

  Set<BackupCategory> categories(JsonMap input) {
    final selected = (input['categories'] as List)
        .map((e) => BackupCategory.values.byName(e as String))
        .toSet();
    if (selected.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Select at least one backup category.');
    }
    return selected;
  }

  static JsonMap categoryResult(CategoryRestoreResult r) => {
        'success': r.success,
        'status': r.status,
        'restoredCount': r.restoredCount,
        'skippedCount': r.skippedCount,
        'skippedItems': r.skippedItems,
        'error': r.errorMessage,
        'localLibraryCount': r.localLibraryCount,
        'serverProfileCount': r.serverProfileCount,
        'serverAccountCount': r.serverAccountCount,
        'dandanplayRestored': r.dandanplayRestored,
        'bangumiRestored': r.bangumiRestored,
      };

  static Future<String> destination(String path) async {
    final parent =
        await ClassicSettings.authorizedPath(p.dirname(path), directory: true);
    final file = File(p.join(parent, p.basename(path)));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const Failure(FailureCode.conflict, 'Destination already exists.');
    }
    return file.path;
  }

  static PluginDescriptor plugin(String id) =>
      ClassicSettings.current.plugins.plugins.firstWhere(
          (e) => e.manifest.id == id,
          orElse: () =>
              throw Failure(FailureCode.notFound, 'Plugin not found: $id'));

  static JsonMap describePlugin(PluginDescriptor plugin) => {
        'id': plugin.manifest.id,
        'name': plugin.manifest.name,
        'version': plugin.manifest.version,
        'builtin': plugin.isBuiltin,
        'enabled': plugin.enabled,
        'loaded': plugin.loaded,
        'error': plugin.errorMessage,
        'description': plugin.manifest.description,
        'actions': [
          for (final entry in plugin.uiEntries.where((e) => e.isAction))
            {
              'id': entry.id,
              'title': entry.title,
              'description': entry.description
            }
        ],
      };
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Operation extends Action<_Json, _Json> {
  _Operation(this.id, this.title, this.effect, this.itemSchema,
      this.description, this.perform);
  final String id, title, description;
  final Effect effect;
  final ObjectSchema itemSchema;
  final Future<JsonMap> Function(JsonMap) perform;
  ObjectSchema get operationSchema => ObjectSchema({
        ...itemSchema.properties,
        'reason': const StringSchema(),
      }, required: itemSchema.required);
  @override
  ActionSpec get spec => ActionSpec(
      id: id,
      title: title,
      description: '$description 支持 operations 批量；每项可附 reason，成功项不会因其他项失败回滚。',
      effect: effect,
      input: ObjectSchema({
        ...operationSchema.properties,
        'operations': ArraySchema(operationSchema)
      },
          oneOfRequired: itemSchema.required.isEmpty
              ? const []
              : [
                  itemSchema.required,
                  ['operations']
                ]),
      output: _output);
  @override
  _Json decodeInput(JsonMap json) {
    if (json.containsKey('operations') && json.length != 1) {
      throw const Failure(
          FailureCode.invalidInput, 'Batch fields belong to each operation.');
    }
    return _Json(json);
  }

  Future<JsonMap> invoke(JsonMap json, Invocation invocation) async {
    final violations = operationSchema.validate(json);
    if (violations.isNotEmpty) {
      throw Failure(FailureCode.invalidInput, 'Invalid operation.',
          violations: violations);
    }
    return runZoned(() => perform(json), zoneValues: {
      SettingsAccess.invocationKey: invocation,
      SettingsAccess.reasonKey: json['reason'],
    });
  }

  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    if (!input.value.containsKey('operations')) {
      return Completed(_Json(await invoke(input.value, invocation)));
    }
    final results = <JsonMap>[];
    final items = (input.value['operations'] as List).cast<JsonMap>();
    for (var i = 0; i < items.length; i++) {
      try {
        results.add({
          'index': i,
          'status': 'completed',
          'result': await invoke(items[i], invocation)
        });
      } on Failure catch (error) {
        results.add({'index': i, 'status': 'failed', 'error': error.toJson()});
      } catch (error) {
        results.add({
          'index': i,
          'status': 'failed',
          'error': Failure(
                  FailureCode.internal, SecretRedactor.text(error.toString()))
              .toJson()
        });
      }
    }
    return Completed(_Json({'results': results}));
  }
}
