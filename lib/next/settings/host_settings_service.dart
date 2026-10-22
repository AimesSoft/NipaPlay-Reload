import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/system_proxy_service.dart';

import '../chat/chat_host.dart';
import '../chat/model_launch.dart';
import '../mesh/runtime.dart';
import '../programs/runtime.dart';
import '../runtime/codex_runtime.dart';
import '../state/change_history.dart';
import '../ui_data/host_settings.dart';
import 'responses_probe.dart';

final class HostSettingsService implements NextHostSettings, NextHostDeviceSettings, NextHostRuntimeSettings {
  HostSettingsService(
      {required this.root,
      required this.vault,
      required this.meshRuntime,
      required this.programs,
      required this.history,
      required this.chat,
      required this.chatProblem,
      required this.repository,
      required this.codexHome,
      required this.checkCodex,
      required this.modelSaved,
      this.device,
      this.codex,
      this.httpClient = HttpClient.new}) {
    _meshEvents = meshRuntime.hostChanges.listen((_) => notify());
  }
  final Directory root, codexHome;
  final CodexRuntime? codex;
  CodexRuntime get _codex => codex ?? (throw UnsupportedError('实验配置沿用外部 Codex'));
  @override
  Future<UiCodexRuntime> codexRuntime() => _codex.state();
  @override
  Future<void> installCodex() async {
    await _codex.install();
    if ((await _codex.state()).status == UiCodexStatus.ready) await modelSaved();
  }
  @override
  Future<void> cancelCodexInstall() => _codex.cancel();
  @override
  Future<void> removeCodex() => _codex.remove();
  @override
  Future<void> setCodexRuntime(UiCodexRuntimeChoice choice) =>
      _write(() => _codex.configure(choice)).then((_) => modelSaved());
  final CredentialVault vault;
  final MeshRuntime meshRuntime;
  final ProgramRuntime programs;
  final ChangeHistory history;
  final ChatHost? Function() chat;
  final String? Function() chatProblem;
  final String Function() repository;
  final Future<UiModelCheck> Function() checkCodex;
  final Future<void> Function() modelSaved;
  final NextHostDeviceSettings? device;
  NextHostDeviceSettings get _device => device ??
      (throw UnsupportedError('此宿主未接入设备设置'));
  @override
  Future<UiHostKeys> keys() => _device.keys();
  @override
  Future<void> setKeys({String? spoilerAi, String? tmdb}) => _write(() async {
    await _device.setKeys(spoilerAi: spoilerAi, tmdb: tmdb);
    notify();
  });
  @override
  Future<UiRemoteAccess> remoteAccess() => _device.remoteAccess();
  @override
  Future<void> setRemoteAccess(UiRemoteAccessChoice choice) => _write(() async {
    await _device.setRemoteAccess(choice);
    notify();
  });
  @override
  Future<void> forgetRemoteDevice(String clientKey) => _write(() async {
    await _device.forgetRemoteDevice(clientKey);
    notify();
  });
  final HttpClient Function() httpClient;
  final _changes = StreamController<void>.broadcast();
  Future<void> _writes = Future.value();
  String? _checkProblem;
  StreamSubscription<void>? _meshEvents;
  @override
  Stream<void> get changes => _changes.stream;
  void notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<T> _write<T>(Future<T> Function() operation) {
    final next = _writes.then((_) => operation());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<JsonMap> _read(String name) async {
    final file = File('${root.path}/$name');
    return await file.exists()
        ? Map<String, Object?>.from(
            jsonDecode(await file.readAsString()) as Map)
        : {};
  }

  Future<void> _save(String name, JsonMap value) async {
    await root.create(recursive: true);
    final file = File('${root.path}/$name.pending');
    await file.writeAsString(jsonEncode(value), flush: true);
    await file.rename('${root.path}/$name');
  }

  /// Where the key of the model set up in NipaPlay is kept in the vault.
  static CredentialRef modelKey(Directory root, JsonMap value) => CredentialRef(
      'next_model',
      sha256
          .convert(utf8.encode(jsonEncode(
              [root.absolute.path, value['provider'], value['baseUrl']])))
          .toString());
  CredentialRef _key(JsonMap value) => modelKey(root, value);
  UiModelSource _source(JsonMap value) => value['source'] == 'nipaplay' ||
      (value['source'] == null && codex != null)
      ? UiModelSource.nipaplay
      : UiModelSource.codex;
  Future<String?> _secret(JsonMap value) async {
    final key = await vault.read(_key(value));
    if (key != null) SecretRedactor.remember(_key(value), key);
    return key;
  }

  static String _text(String? value, String field) {
    if (value == null ||
        value.trim().isEmpty ||
        value.length > 512 ||
        value.contains(RegExp(r'[\x00-\x1f]')) ||
        SecretRedactor.text(value) != value) {
      throw FormatException('$field 填写不正确');
    }
    return value.trim();
  }

  static Uri _url(String? value) {
    final uri = Uri.tryParse(_text(value, '地址'));
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('地址需为不含认证信息的 HTTP 或 HTTPS 地址');
    }
    return uri;
  }

  @override
  Future<UiModelSetup> model() async {
    await _writes;
    final value = await _read('model.json');
    final source = _source(value);
    final exists = await File('${codexHome.path}/config.toml').exists();
    final key = source == UiModelSource.nipaplay ? await _secret(value) : null;
    final host = chat();
    final missing = source == UiModelSource.codex
        ? exists
            ? null
            : '这台电脑还没有 Codex 配置'
        : value['model'] == null || value['baseUrl'] == null
            ? '请先填写地址和模型名'
            : key == null || key.isEmpty
                ? '请先填写密钥'
                : null;
    return UiModelSetup(
        source: source,
        codexAvailable: exists,
        provider: value['provider'] as String?,
        baseUrl: value['baseUrl'] as String?,
        model: value['model'] as String?,
        hasKey: key != null && key.isNotEmpty,
        inUse: host?.available == true ? host!.model : null,
        problem: host?.available == true &&
                host!.threadLiveness.keys.any(host.busyFor) &&
                host.activeModelRevision != value['revision']
            ? null
            : missing ??
                _checkProblem ??
                (chatProblem() == null ? _liveProblem(host) : '模型服务未能启动'));
  }

  String? _liveProblem(ChatHost? host) {
    if (host == null) return '模型服务尚未启动';
    final error = host.liveness.latestError;
    return error == null
        ? host.available
            ? null
            : '模型服务已断开'
        : modelFailureMessage(error);
  }

  @override
  Future<void> setModel(UiModelChoice choice) => _write(() async {
        if (choice.apiKey case final key?) {
          SecretRedactor.remember(
              const CredentialRef('next_model', 'input'), key);
        }
        final before = await _read('model.json');
        final value = <String, Object?>{
          ...before,
          'source': choice.source.name,
          'revision': (before['revision'] as int? ?? 0) + 1
        };
        if (choice.source == UiModelSource.nipaplay) {
          value['provider'] = _text(choice.provider?.trim().isNotEmpty == true
              ? choice.provider : '自定义', '提供方');
          value['baseUrl'] =
              _url(choice.baseUrl).toString().replaceFirst(RegExp(r'/$'), '');
          value['model'] = _text(choice.model, '模型');
          if (choice.apiKey case final key?) {
            if (key.contains(RegExp(r'[\x00-\x20]')) || key.length > 16384) {
              throw const FormatException('密钥填写不正确');
            }
            if (key.isEmpty) {
              await vault.delete(_key(value));
            } else {
              SecretRedactor.remember(_key(value), key);
              await vault.write(_key(value), key);
              if (await vault.read(_key(value)) != key) {
                throw StateError('保险库未能保存密钥');
              }
            }
          }
        }
        await _save('model.json', value);
        _record('model', before, value);
        _checkProblem = null;
        notify();
        // The live host reads this snapshot only at the next turn boundary.
      }).then((_) => modelSaved());

  Future<ModelLaunch> launch() async {
    // Installation can outlast a settings edit. Read the selected model only
    // after it completes so first-use input takes effect on this launch.
    final executable = await codex?.executable();
    await _writes;
    final value = await _read('model.json');
    final revision = value['revision'] as int? ?? 0;
    if (_source(value) == UiModelSource.codex) {
      return ModelLaunch(revision: revision, executable: executable);
    }
    final key = await _secret(value);
    if (key == null || key.isEmpty) throw StateError('请先填写密钥');
    final provider = _text(value['provider'] as String?, '提供方');
    final url = responsesBase(_url(value['baseUrl'] as String?));
    final model = _text(value['model'] as String?, '模型');
    final home = Directory('${root.path}/codex-home');
    return ModelLaunch(
        revision: revision,
        executable: executable,
        home: home,
        model: model,
        provider: 'nipaplay',
        environment: {'NIPAPLAY_MODEL_API_KEY': key},
        prepare: () async {
          await home.create(recursive: true);
          final config = File('${home.path}/config.toml.pending');
          // JSON string syntax is a subset of TOML basic string syntax here.
          await config.writeAsString(
              'model = ${jsonEncode(model)}\n'
              'model_provider = "nipaplay"\n'
              'cli_auth_credentials_store = "ephemeral"\n'
              '[features]\nshell_snapshot = false\n'
              '[model_providers.nipaplay]\nname = ${jsonEncode(provider)}\n'
              'base_url = ${jsonEncode(url.toString())}\nwire_api = "responses"\n'
              'env_key = "NIPAPLAY_MODEL_API_KEY"\nrequires_openai_auth = false\n'
              '[shell_environment_policy]\nexclude = ["NIPAPLAY_MODEL_API_KEY"]\n'
              '[projects.${jsonEncode(repository())}]\ntrust_level = "trusted"\n',
              flush: true);
          await config.rename('${home.path}/config.toml');
        });
  }

  @override
  Future<UiModelCheck> checkModel() async {
    await _writes;
    final value = await _read('model.json');
    final watch = Stopwatch()..start();
    UiModelCheck result;
    if (_source(value) == UiModelSource.codex) {
      result = await checkCodex();
    } else {
      final key = await _secret(value);
      if (key == null || key.isEmpty) {
        result = const UiModelCheck(ok: false, message: '请先填写密钥');
      } else {
        final client = httpClient();
        try {
          await SystemProxyService.instance.initialize();
          client.findProxy = (uri) => uri.host == 'localhost' ||
              InternetAddress.tryParse(uri.host)?.isLoopback == true ? 'DIRECT' :
              AppHttpProxy.findProxy(uri, SystemProxyService.instance.findProxy);
          client.connectionTimeout = const Duration(seconds: 15);
          result = await probeResponses(client, _url(value['baseUrl'] as String?),
              _text(value['model'] as String?, '模型'), key)
              .timeout(const Duration(seconds: 30));
        } on TimeoutException {
          result = const UiModelCheck(ok: false, message: '服务器响应超时');
        } on SocketException {
          result = const UiModelCheck(ok: false, message: '连不上服务器');
        } on HandshakeException {
          result = const UiModelCheck(ok: false, message: '服务器证书无法验证');
        } on HttpException {
          result = const UiModelCheck(ok: false, message: '服务器连接中断');
        } on FormatException {
          result = const UiModelCheck(ok: false, message: '地址或响应格式不正确');
        } finally {
          client.close(force: true);
        }
      }
    }
    // A failed check is a saved-choice fact, never an error on an old live turn.
    _checkProblem = result.ok ? null : result.message;
    notify();
    return UiModelCheck(
        ok: result.ok,
        message: result.message,
        latency: result.latency ?? watch.elapsed);
  }

  @override
  Future<bool> remotePrograms() async {
    await _writes;
    return loadProgramPermission(root);
  }

  @override
  Future<void> setRemotePrograms(bool allowed) => _write(() async {
        final before = await _read('program.json');
        final value = <String, Object?>{...before, 'enabled': allowed};
        await _save('program.json', value);
        programs.enabled = allowed;
        _record('program', before, value);
        notify();
      });
  @override
  Future<UiMeshSetup> mesh() async {
    await _writes;
    final value = await _read('mesh.json');
    final listed = await meshRuntime.settingsDevices();
    return UiMeshSetup(
        joined: meshRuntime.status == 'online',
        available: meshRuntime.issuerAvailable,
        problem: !meshRuntime.issuerAvailable
            ? '此版本尚未配置组网签发者'
            : switch (meshRuntime.status) {
                'online' || 'disabled' => null,
                'sign_in_required' => '请先登录弹弹play账号',
                'device_revoked' => '这台设备的组网资格已撤销',
                _ => '暂时无法加入组网',
              },
        name: value['name'] as String?,
        coordinator: value['coordinator'] as String?,
        port: value['port'] as int?,
        loopbackOnly: value['loopbackOnly'] == true,
        broadcastDiscovery: value['broadcastDiscovery'] as bool? ?? true,
        addresses: [
          for (final address in value['addresses'] as List? ?? [])
            _addressText(address as Map)
        ],
        fileProxyPort: value['fileProxyPort'] as int?,
        devices: [
          for (final device in listed)
            UiMeshDevice(
                name: device['name'] as String? ??
                    device['device_name'] as String? ??
                    '未命名设备',
                online: device['online'] == true,
                self: device['deviceId'] == meshRuntime.identity?.deviceId,
                roles: (device['roles'] as List?)?.cast<String>() ?? const [],
                remotePrograms: device['remotePrograms'] == true)
        ]);
  }

  static String _addressText(Map address) {
    final host = address['host'] as String;
    return '${host.contains(':') ? '[$host]' : host}:${address['port']}';
  }

  @override
  Future<void> setMesh(UiMeshChoice choice) => _write(() async {
        if (choice.port != null && (choice.port! < 0 || choice.port! > 65535) ||
            choice.fileProxyPort != null &&
                choice.fileProxyPort != 0 &&
                (choice.fileProxyPort! < 1024 ||
                    choice.fileProxyPort! > 65535)) {
          throw const FormatException('端口范围不正确');
        }
        final addresses = [
          for (final text in choice.addresses)
            () {
              final uri = Uri.tryParse('http://$text');
              if (uri == null ||
                  uri.host.isEmpty ||
                  !uri.hasPort ||
                  uri.port < 1 ||
                  uri.port > 65535 ||
                  uri.userInfo.isNotEmpty ||
                  uri.path.isNotEmpty ||
                  uri.hasQuery ||
                  uri.hasFragment) {
                throw const FormatException('设备地址需为 host:port 或 [IPv6]:port');
              }
              return <String, Object?>{
                'kind': 'manual',
                'host': uri.host.replaceAll(RegExp(r'[\[\]]'), ''),
                'port': uri.port
              };
            }()
        ];
        if (meshAddressViolations(addresses).isNotEmpty) {
          throw const FormatException('最多填写 16 个有效设备地址');
        }
        final before = await _read('mesh.json');
        final value = <String, Object?>{
          ...before,
          'enabled': choice.joined,
          if (choice.name != null) 'name': _text(choice.name, '设备名称'),
          if (choice.coordinator != null)
            'coordinator': _url(choice.coordinator).toString(),
          'port': choice.port ?? 0,
          'loopbackOnly': choice.loopbackOnly,
          'broadcastDiscovery': choice.broadcastDiscovery,
          'addresses': addresses,
          'fileProxyPort': choice.fileProxyPort ?? 0
        };
        if (choice.joined && value['coordinator'] == null) {
          throw const FormatException('请填写协调服务地址');
        }
        await _save('mesh.json', value);
        _record('mesh', before, value);
        await meshRuntime.restartConfigured();
        notify();
      });
  void _record(String kind, JsonMap before, JsonMap after) {
    final collection = 'host_settings:$kind';
    final old = SecretRedactor.json({'id': kind, ...before}) as JsonMap;
    final next = SecretRedactor.json({'id': kind, ...after}) as JsonMap;
    history.seed(collection, [old]);
    history.observe(collection, [next], Invocation(origin: 'gui'));
  }

  Future<void> close() async {
    await codex?.cancel();
    await _writes;
    await _meshEvents?.cancel();
    await _changes.close();
  }
}

String modelFailureMessage(String error) {
  if (RegExp(r'401|403|unauthori[sz]ed|invalid.*key', caseSensitive: false)
      .hasMatch(error)) {
    return '密钥无效或没有权限';
  }
  if (RegExp(r'429|quota|rate.limit', caseSensitive: false).hasMatch(error)) {
    return '额度不足或请求过多';
  }
  if (RegExp(r'connect|network|dns', caseSensitive: false).hasMatch(error)) {
    return '连不上服务器';
  }
  return '模型服务暂时无法工作';
}

/// Lab model keys stay in memory: the existing lab vault writes plaintext files.
/// This disposable backend never contacts the user's login Keychain.
final class LabModelVault implements CredentialVault {
  final _values = <CredentialRef, String>{};
  @override
  Future<String?> read(CredentialRef ref) async => _values[ref];
  @override
  Future<void> write(CredentialRef ref, String secret) async {
    _values[ref] = secret;
  }

  @override
  Future<void> delete(CredentialRef ref) async {
    _values.remove(ref);
  }
}

/// The settings page can subscribe before the application core is ready.
final class PendingHostSettings implements NextHostSettings, NextHostDeviceSettings, NextHostRuntimeSettings {
  PendingHostSettings(this.ready) {
    ready.then((value) {
      _subscription = value.changes.listen((_) => _changes.add(null));
    });
  }
  final Future<NextHostSettings> ready;
  @override
  Future<UiCodexRuntime> codexRuntime() async => (await ready).runtimeSettings.codexRuntime();
  @override
  Future<void> installCodex() async => (await ready).runtimeSettings.installCodex();
  @override
  Future<void> cancelCodexInstall() async => (await ready).runtimeSettings.cancelCodexInstall();
  @override
  Future<void> removeCodex() async => (await ready).runtimeSettings.removeCodex();
  @override
  Future<void> setCodexRuntime(UiCodexRuntimeChoice choice) async =>
      (await ready).runtimeSettings.setCodexRuntime(choice);
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<void>? _subscription;
  @override
  Stream<void> get changes => _changes.stream;
  @override
  Future<UiModelSetup> model() async => (await ready).model();
  @override
  Future<void> setModel(UiModelChoice choice) async =>
      (await ready).setModel(choice);
  @override
  Future<UiModelCheck> checkModel() async => (await ready).checkModel();
  @override
  Future<UiMeshSetup> mesh() async => (await ready).mesh();
  @override
  Future<void> setMesh(UiMeshChoice choice) async =>
      (await ready).setMesh(choice);
  @override
  Future<bool> remotePrograms() async => (await ready).remotePrograms();
  @override
  Future<void> setRemotePrograms(bool allowed) async =>
      (await ready).setRemotePrograms(allowed);
  @override
  Future<UiHostKeys> keys() async => (await ready).deviceSettings.keys();
  @override
  Future<void> setKeys({String? spoilerAi, String? tmdb}) async =>
      (await ready).deviceSettings.setKeys(spoilerAi: spoilerAi, tmdb: tmdb);
  @override
  Future<UiRemoteAccess> remoteAccess() async => (await ready).deviceSettings.remoteAccess();
  @override
  Future<void> setRemoteAccess(UiRemoteAccessChoice choice) async =>
      (await ready).deviceSettings.setRemoteAccess(choice);
  @override
  Future<void> forgetRemoteDevice(String clientKey) async =>
      (await ready).deviceSettings.forgetRemoteDevice(clientKey);
  Future<void> close() async {
    await _subscription?.cancel();
    await _changes.close();
  }
}
