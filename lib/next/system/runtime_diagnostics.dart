import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';

import '../capabilities/classic_action.dart';
import '../capabilities/player_facts.dart';
import 'player_native_log.dart';
import 'uncaught_errors.dart';

/// Uncaught errors, unclean exits and the player kernel's own log, for the
/// GUI host whose player and process they are.
final class RuntimeDiagnosticsCapability implements Capability {
  RuntimeDiagnosticsCapability({
    required this.errors,
    required this.log,
    required this.player,
    required this.logDirectory,
  });

  final UncaughtErrors errors;
  final PlayerNativeLog log;
  final Player Function() player;
  final Directory logDirectory;

  JsonMap _kernel() {
    final name = player().getPlayerKernelName();
    return {'id': playerKernelId(name), 'name': name};
  }

  Future<JsonMap> readLog(JsonMap input) async {
    if (input['file'] == true) {
      final file = log.file ?? await _latestFile();
      if (file == null) {
        return {'path': null, 'exists': false, 'lines': <String>[],
          'nextCursor': null, 'writing': false};
      }
      return {
        ...await PlayerNativeLog.readFile(file,
            cursor: input['cursor'] as int? ?? 0,
            limit: input['limit'] as int? ?? 200,
            contains: input['contains'] as String?),
        'writing': log.file?.path == file.path,
      };
    }
    return {
      'kernel': _kernel(),
      ...log.read(
          afterSequence: input['afterSequence'] as int? ?? 0,
          levels: (input['levels'] as List?)?.cast<String>(),
          contains: input['contains'] as String?,
          limit: input['limit'] as int? ?? 200,
          currentInstance: player().kernelInstance),
      'file': log.file?.path,
    };
  }

  Future<File?> _latestFile() async {
    if (!await logDirectory.exists()) return null;
    final files = [
      await for (final entry in logDirectory.list())
        if (entry is File && entry.path.endsWith('.log')) entry
    ]..sort((a, b) => b.path.compareTo(a.path));
    return files.firstOrNull;
  }

  Future<JsonMap> setLogFile(JsonMap input) async {
    if (input['enabled'] != true) {
      final path = log.file?.path;
      await log.stopFile();
      return {'kernel': _kernel(), 'writing': false, 'path': path};
    }
    if (!log.recording) {
      throw const Failure(FailureCode.unavailable,
          'Player diagnostics are recorded only while Next is on.');
    }
    final file = await log.startFile(player(), logDirectory);
    if (file == null) {
      return {
        'kernel': _kernel(),
        'writing': false,
        'path': null,
        'reason': 'kernel_without_log_file'
      };
    }
    return {
      'kernel': _kernel(),
      'writing': true,
      'path': file.path,
      'exists': await file.exists(),
    };
  }

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.errors',
                title: '未捕获错误与异常退出',
                description:
                    'Next 开启期间本进程的未捕获错误，以及上一次（Next 开启时）没有经过 NipaPlay 退出流程就结束的运行（崩溃、被强制结束、被系统结束都属于此类），新的在前。uncaught_error：channels（flutter=框架错误，platform_dispatcher=未捕获的异步错误，isolate=isolate 错误监听）、type、message、stack（前 16 行）、library、context、firstAt、lastAt、count（同一错误再次出现累计）、playback（当时播放的状态、路径、内核）。unclean_exit：firstAt 为那次运行开始，lastAt 为最后一次记录，processId、appVersion、playback 为那次最后记下的播放。原生崩溃本身没有堆栈，只表现为 unclean_exit。原有错误处理照常运行；Next 关闭期间不记录。文本已脱敏。recording 表示当前是否在记录。',
                effect: Effect.read,
                input: ObjectSchema({
                  'limit': IntegerSchema(minimum: 1, maximum: 200),
                  'kind': StringSchema(values: ['uncaught_error', 'unclean_exit']),
                }),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => errors.read(
                limit: input['limit'] as int? ?? 50,
                kind: input['kind'] as String?)),
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.player_log',
                title: '播放器内核日志',
                description:
                    '读取 Next 开启以来播放内核交给应用的最近若干行（容量 capacity，超出的旧行计入 evicted）：Media Kit 为 mpv 日志消息（默认只有 error 级），MDK 为媒体事件与媒体状态（invalid 状态记为 error），Erika 为播放错误与解码器切换。每行有 sequence、at、kernel、currentPlayer（是否来自当前播放器实例，时间轴预览等实例为 false）、level、source、text（读取时脱敏）。afterSequence 续读，nextSequence 为已检查位置；levels、contains 过滤。file=true 时改为读取 diagnostics.player_log_file 写出的 mpv 完整日志（没有正在写的就读最近一份），cursor 为行偏移，单页至多 256 KiB。',
                effect: Effect.read,
                input: ObjectSchema({
                  'afterSequence': IntegerSchema(minimum: 0),
                  'levels': ArraySchema(StringSchema(), minItems: 1),
                  'contains': StringSchema(minLength: 1),
                  'limit': IntegerSchema(minimum: 1, maximum: 1000),
                  'file': BooleanSchema(),
                  'cursor': IntegerSchema(minimum: 0),
                }),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => readLog(input)),
        ClassicAction(
            const ActionSpec(
                id: 'diagnostics.player_log_file',
                title: '播放器完整日志文件',
                description:
                    'enabled=true 让当前 Media Kit 播放器把 mpv 的完整日志（debug 级，含解码、网络、渲染细节）写到 NipaPlay 数据目录 next/diagnostics/player-logs/ 下的新文件，返回 path 与 exists（文件是否已出现）；enabled=false 停止。只作用于当前播放器实例，换内核后不延续；Next 关闭时自动停止。写日志会增加磁盘写入，播放越久文件越大。其他内核返回 writing=false 与 reason=kernel_without_log_file。不改变界面上的日志设置。',
                effect: Effect.write,
                input: ObjectSchema({'enabled': BooleanSchema()},
                    required: ['enabled']),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) => setLogFile(input)),
      ];
}
