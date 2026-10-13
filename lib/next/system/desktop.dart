import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/nipaplay_lan_discovery.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import '../capabilities/classic_action.dart';
import '../harness_hooks.dart';
import '../harness_redaction.dart';
import '../media/media_service.dart';

final class DesktopSystem extends WindowListener implements Capability {
  DesktopSystem(this.media, this.root, this.hooks);
  final MediaService media;
  final Directory root;
  final HarnessHooks hooks;
  static const _native = MethodChannel('nipaplay/instance');
  final _shares = <String, JsonMap>{};
  Timer? _boundsTimer;
  JsonMap? _lastBounds;
  bool get desktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  void attach() {
    if (desktop) windowManager.addListener(this);
  }

  void detach() {
    if (desktop) windowManager.removeListener(this);
    _boundsTimer?.cancel();
  }

  @override
  void onWindowMove() => _queueBounds();
  @override
  void onWindowResize() => _queueBounds();
  void _queueBounds() {
    _boundsTimer?.cancel();
    _boundsTimer = Timer(const Duration(milliseconds: 250), () async {
      final bounds = await _bounds();
      if (bounds.toString() != _lastBounds.toString()) {
        _lastBounds = bounds;
        await hooks.emit('window.bounds_changed', 'main', bounds);
      }
    });
  }

  Future<JsonMap> _bounds() async {
    final r = await windowManager.getBounds();
    return {
      'target': 'main',
      'bounds': {'x': r.left, 'y': r.top, 'width': r.width, 'height': r.height},
      'coordinateSystem':
          'window_manager logical pixels; screen origin top-left'
    };
  }

  Future<JsonMap> _notification(String operation, JsonMap input) async {
    if (!Platform.isMacOS) {
      return {
        'supported': false,
        'deliveryState': 'unavailable',
        'reason': 'native_backend_not_implemented'
      };
    }
    final args = {...input};
    if (operation == 'send') {
      args['id'] ??= 'nipa-${DateTime.now().microsecondsSinceEpoch}';
    }
    return Map<String, Object?>.from(
        await _native.invokeMapMethod<String, Object?>(
                'notification.$operation', args) ??
            {});
  }

  Future<JsonMap> _discover(int milliseconds) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final rows = <String, JsonMap>{};
    socket.broadcastEnabled = true;
    final listener = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final server = NipaPlayLanDiscoveryProtocol.tryParseResponse(datagram!);
        if (server != null) {
          rows[server.baseUrl] = {
            'address': server.baseUrl,
            'kind': 'nipaplay_shared',
            'name': server.hostname,
            'discovery': 'udp_unverified'
          };
        }
      }
    });
    try {
      final packet = NipaPlayLanDiscoveryProtocol.buildRequestBytes();
      socket.send(
          packet, InternetAddress('255.255.255.255'), nipaplayLanDiscoveryPort);
      await Future<void>.delayed(Duration(milliseconds: milliseconds));
      return {
        'candidates': rows.values.toList(),
        'observedAt': DateTime.now().toUtc().toIso8601String(),
        'registered': false,
        'protocol':
            'Classic UDP v1; old servers without discovery responder are not included'
      };
    } finally {
      await listener.cancel();
      socket.close();
    }
  }

  @override
  List<Action> get actions => [
        for (final operation in ['status', 'send', 'list', 'cancel'])
          ClassicAction(
              ActionSpec(
                  id: 'notification.$operation',
                  title: '系统通知 $operation',
                  description:
                      'macOS 原生通知；遵守系统授权和声音设置。send 返回 OS 受理事实，list 可查询 delivered/pending。未授权默认 blocked；requestPermission=true 显式让系统询问用户。不会激活窗口。其他宿主返回 unsupported。',
                  effect: operation == 'status' || operation == 'list'
                      ? Effect.read
                      : Effect.write,
                  input: operation == 'send'
                      ? const ObjectSchema({
                          'id': StringSchema(minLength: 1, maxLength: 128),
                          'title': StringSchema(minLength: 1, maxLength: 200),
                          'body': StringSchema(maxLength: 4000),
                          'sound': BooleanSchema(),
                          'requestPermission': BooleanSchema()
                        }, required: [
                          'title',
                          'body'
                        ])
                      : operation == 'cancel'
                          ? const ObjectSchema(
                              {'id': StringSchema(minLength: 1)},
                              required: ['id'])
                          : const ObjectSchema({}),
                  output: const ObjectSchema({}, additionalProperties: true)),
              (input, _) => _notification(operation, input)),
        ClassicAction(
            const ActionSpec(
                id: 'media.sources.discover',
                title: '发现局域网共享来源',
                description:
                    '使用 Classic UDP 协议有界发现共享服务器。返回候选与观察时间，不登录、不登记来源；候选由对端声明，尚未验证。',
                effect: Effect.read,
                input: ObjectSchema(
                    {'timeoutMs': IntegerSchema(minimum: 100, maximum: 10000)}),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) =>
                _discover((input['timeoutMs'] as num?)?.toInt() ?? 2000)),
        ClassicAction(
            const ActionSpec(
                id: 'window.bounds.get',
                title: '读取主窗口位置与尺寸',
                description: '读取当前进程主窗口的准确 bounds（逻辑像素），不改变窗口。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          if (!desktop) {
            throw const Failure(
                FailureCode.unavailable, 'This host has no desktop window.');
          }
          return _bounds();
        }),
        ClassicAction(
            const ActionSpec(
                id: 'window.bounds.set',
                title: '主窗口位置与尺寸',
                description:
                    '设置当前进程主窗口的准确 bounds（逻辑像素），返回设置后读回值。不激活或抢前台；现有 fullscreen/PiP 用 window.control。',
                effect: Effect.write,
                input: ObjectSchema({
                  'bounds': ObjectSchema({
                    'x': NumberSchema(),
                    'y': NumberSchema(),
                    'width': NumberSchema(minimum: 100),
                    'height': NumberSchema(minimum: 100)
                  }, required: [
                    'x',
                    'y',
                    'width',
                    'height'
                  ])
                }, required: ['bounds']),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async {
          if (!desktop) {
            throw const Failure(
                FailureCode.unavailable, 'This host has no desktop window.');
          }
          final bounds = input['bounds'] as Map;
          await windowManager.setBounds(Rect.fromLTWH(
              (bounds['x'] as num).toDouble(),
              (bounds['y'] as num).toDouble(),
              (bounds['width'] as num).toDouble(),
              (bounds['height'] as num).toDouble()));
          return _bounds();
        }),
        ClassicAction(
            const ActionSpec(
                id: 'share.prepare',
                title: '预览系统分享内容',
                description:
                    '准备文字、公开 URL 或一份本地文件的系统分享面板。文件须在媒体授权范围或本应用目录；不会上传或打开面板。秘密先脱敏，不发送认证链接。',
                effect: Effect.read,
                input: ObjectSchema({
                  'text': StringSchema(maxLength: 10000),
                  'url': StringSchema(),
                  'filePath': StringSchema(),
                  'subject': StringSchema(maxLength: 200)
                }),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async {
          if (input['text'] == null &&
              input['url'] == null &&
              input['filePath'] == null) {
            throw const Failure(
                FailureCode.invalidInput, 'Provide text, url or filePath.');
          }
          final safe = publicHarnessFacts(input) as JsonMap;
          if (input['url'] != safe['url']) {
            throw const Failure(
                FailureCode.invalidInput, 'Only public URLs can be shared.');
          }
          if (input['url'] case final String text) {
            final url = Uri.tryParse(text);
            if (url == null ||
                !{'http', 'https'}.contains(url.scheme) ||
                url.host.isEmpty) {
              throw const Failure(
                  FailureCode.invalidInput, 'Use a public HTTP(S) URL.');
            }
          }
          if (input['filePath'] case final String file) {
            final canonical = await File(file).resolveSymbolicLinks();
            if (!p.isWithin('${root.parent.path}/temp', canonical) &&
                !p.isWithin('${root.path}/exports', canonical)) {
              await media.authorizedPath(canonical);
            }
            final stat = await File(canonical).stat();
            safe.addAll({
              'filePath': canonical,
              'bytes': stat.size,
              'modified': stat.modified.microsecondsSinceEpoch
            });
          }
          final id = 'share-${DateTime.now().microsecondsSinceEpoch}';
          _shares[id] = safe;
          return {
            'planId': id,
            'content': safe,
            'supported': SystemShareService.isSupported,
            'destination': 'user chooses in OS share panel'
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'share.open',
                title: '打开预览的系统分享面板',
                description:
                    '打开 share.prepare 对应的 OS 面板；用户选择目标。重新核对文件变化，返回 panelOpened，不宣称已公开发布。',
                effect: Effect.write,
                input: ObjectSchema({'planId': StringSchema(minLength: 1)},
                    required: ['planId']),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async {
          final plan = _shares[input['planId']];
          if (plan == null) {
            throw const Failure(
                FailureCode.notFound, 'Share plan unavailable; prepare again.');
          }
          if (plan['filePath'] case final String file) {
            final stat = await File(file).stat();
            if (stat.size != plan['bytes'] ||
                stat.modified.microsecondsSinceEpoch != plan['modified']) {
              throw const Failure(
                  FailureCode.conflict, 'Share file changed after preview.');
            }
          }
          await SystemShareService.share(
              text: plan['text'] as String?,
              url: plan['url'] as String?,
              filePath: plan['filePath'] as String?,
              subject: plan['subject'] as String?);
          _shares.remove(input['planId']);
          return {
            'planId': input['planId'],
            'panelOpened': true,
            'publication': 'not observed'
          };
        }),
      ];
}
