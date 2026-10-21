import 'package:nipa_harness/nipa_harness.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../capabilities/classic_action.dart';
import '../downloads/download_service.dart';
import '../settings/registry.dart';
import '../chat/helpers.dart';

final class TaskResources implements Capability {
  TaskResources(this.engine, this.downloads, this.helpers);
  final TaskEngine engine;
  final DownloadService downloads;
  final Helpers helpers;
  int scanConcurrency = 1, metadataConcurrency = 4;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    scanConcurrency = prefs.getInt('next_scan_concurrency') ?? 1;
    metadataConcurrency = prefs.getInt('next_metadata_concurrency') ?? 4;
    helpers.capacity = prefs.getInt('next_helper_concurrency') ?? Helpers.limit;
    _apply();
  }

  void _apply() {
    engine.setCapacity('media.scan', scanConcurrency);
    // Classic's scanner has one mutable diff/progress state.
    engine.setCapacity('media.scan_classic', 1);
    engine.setCapacity('media.metadata.refresh', metadataConcurrency);
  }

  List<SettingEntry> settings() => [
        for (final kind in ['scan', 'metadata', 'helper'])
          SettingEntry(
              key: 'tasks.${kind}Concurrency',
              title: '$kind 并发',
              description: kind == 'scan'
                  ? 'Next 文件索引任务的容量；Classic 扫描器固定一个目录任务。降低容量不停止已运行工作。'
                  : kind == 'metadata'
                      ? 'Next 资料刷新任务和新 Classic 扫描的识别并发；不改变来源请求间隔与限流。'
                      : '宿主派发回合的容量；原生子代理的容量由运行它的 agent 程序管理。运行中的回合不受影响。',
              schema: const IntegerSchema(minimum: 1),
              defaultValue: kind == 'metadata'
                  ? 4
                  : kind == 'helper'
                      ? 2
                      : 1,
              storageKey: 'next_${kind}_concurrency',
              reader: 'TaskResources',
              writer: 'TaskResources',
              read: () async => switch (kind) {
                    'scan' => scanConcurrency,
                    'metadata' => metadataConcurrency,
                    _ => helpers.capacity,
                  },
              write: (value) async {
                final number = value as int;
                final prefs = await SharedPreferences.getInstance();
                await SettingsAccess.persist('next_${kind}_concurrency',
                    () => prefs.setInt('next_${kind}_concurrency', number));
                switch (kind) {
                  case 'scan':
                    scanConcurrency = number;
                  case 'metadata':
                    metadataConcurrency = number;
                  case 'helper':
                    helpers.capacity = number;
                }
                _apply();
              },
              decodeStorage: (v) => v),
      ];

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'task.resources',
                title: '后台容量与占用',
                description:
                    '读取实际容量、占用与排队任务。通过 tasks.*Concurrency 设置调整本机容量。下载限速由 download.limits.get/set 返回原生支持与读回值。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          final jobs = await engine.list();
          return {
            'pools': [
              for (final type in [
                'media.scan',
                'media.scan_classic',
                'media.metadata.refresh',
                'agent.helper'
              ])
                {
                  'type': type,
                  'capacity': type == 'agent.helper'
                      ? helpers.capacity
                      : engine.capacity(type),
                  'active': type == 'agent.helper'
                      ? helpers.activeCount
                      : engine.activeCount(type),
                  'queued': jobs
                      .where((j) =>
                          j.type == type &&
                          !j.state.isTerminal &&
                          {
                            JobState.queued,
                            JobState.waitingRetry,
                            JobState.interrupted
                          }.contains(j.state))
                      .length
                },
            ],
            'classicMatching': {
              'capacity': metadataConcurrency,
              'applies': 'new scan'
            },
            'downloadLimits': await downloads.bandwidth({}),
            'nativeHelpers': {'capacityOwner': 'Codex'}
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'task.control',
                title: '批量控制后台任务',
                description:
                    '暂停、恢复、取消任务。逐项返回受理快照及支持事实。扫描排空当前文件，在文件边界停止；宿主派发的回合中断当前回合，恢复在同线程继续原任务。原生子代理、hook 和程序不支持安全暂停。取消保留已提交事实，终态回执不会改写。',
                effect: Effect.write,
                input: ObjectSchema({
                  'entries': ArraySchema(
                      ObjectSchema({
                        'jobId': StringSchema(minLength: 1),
                        'command':
                            StringSchema(values: ['pause', 'resume', 'cancel']),
                        'expectedRevision': IntegerSchema(minimum: 0),
                      }, required: [
                        'jobId',
                        'command'
                      ]),
                      minItems: 1,
                      maxItems: 100)
                }, required: [
                  'entries'
                ]),
                output: ObjectSchema({
                  'results': ArraySchema(ObjectSchema({
                    'index': IntegerSchema(minimum: 0),
                    'jobId': StringSchema(),
                    'command': StringSchema(),
                    'accepted': BooleanSchema(),
                    'controlSupported': BooleanSchema(),
                    'job': ObjectSchema({}, additionalProperties: true),
                    'error': ObjectSchema({}, additionalProperties: true),
                    'reason': StringSchema(),
                    'draining': BooleanSchema(),
                  }, required: [
                    'index',
                    'jobId',
                    'command',
                    'accepted'
                  ], additionalProperties: true))
                }, required: [
                  'results'
                ])), (input, _) async {
          final results = <JsonMap>[];
          for (final raw in input['entries'] as List) {
            final entry = raw as Map;
            final id = entry['jobId'] as String,
                command = entry['command'] as String;
            try {
              final job = await engine.get(id);
              if (entry['expectedRevision'] != null &&
                  entry['expectedRevision'] != job.revision) {
                throw const Failure(
                    FailureCode.conflict, 'Task revision changed.');
              }
              final resumable = const {
                'download',
                'media.scan',
                'media.scan_classic',
                'media.metadata.refresh',
                'media.project'
              }.contains(job.type);
              final hostHelper = job.type == 'agent.helper' &&
                  job.input['source'] != 'codexNative';
              if (command != 'cancel' && !resumable && !hostHelper) {
                results.add({
                  'jobId': id,
                  'command': command,
                  'accepted': false,
                  'controlSupported': false,
                  'reason':
                      'Executor cannot safely pause/resume existing external effects.',
                  'job': job.toJson()
                });
                continue;
              }
              final updated = switch (command) {
                'cancel' => await engine.cancel(id),
                'pause' => job.type == 'download'
                    ? await downloads.pause(id)
                    : await engine.pause(id),
                _ => job.type == 'download'
                    ? await downloads.resume(id)
                    : await engine.resume(id,
                        checkpoint: hostHelper
                            ? {
                                ...job.checkpoint,
                                'resumeToken': '${job.jobId}:${job.revision}',
                              }
                            : null),
              };
              results.add({
                'jobId': id,
                'command': command,
                'accepted': true,
                'controlSupported': true,
                'job': updated.toJson(),
                'draining':
                    engine.isActive(id) && updated.state == JobState.paused
              });
            } on Failure catch (error) {
              results.add({
                'jobId': id,
                'command': command,
                'accepted': false,
                'error': error.toJson()
              });
            }
          }
          return {
            'results': [
              for (var i = 0; i < results.length; i++)
                {'index': i, ...results[i]}
            ]
          };
        }),
      ];
}
