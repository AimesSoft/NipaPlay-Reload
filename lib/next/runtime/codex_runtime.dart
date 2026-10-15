import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/system_proxy_service.dart';

import '../ui_data/host_settings.dart';
import 'codex_manifest.dart';
import 'codex_licenses.dart';

/// Installs only the application manifest version into Next's own data root.
/// No PATH discovery and no user CODEX_HOME writes occur here.
final class CodexRuntime {
  factory CodexRuntime.desktop(
      {required Directory root,
      required void Function() notify,
      required bool Function() inUse}) {
    final arch = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x64',
      _ => throw UnsupportedError('此架构没有固定的 Codex 运行包'),
    };
    return CodexRuntime(
        root: root,
        platform: Platform.operatingSystem,
        asset: codexAssets['${Platform.operatingSystem}-$arch']!,
        notify: notify,
        inUse: inUse,
        licenses: codexLicenses,
        httpClient: () => HttpClient()
          ..findProxy = (uri) => uri.host == 'localhost' ||
                  InternetAddress.tryParse(uri.host)?.isLoopback == true
              ? 'DIRECT'
              : AppHttpProxy.findProxy(
                  uri, SystemProxyService.instance.findProxy));
  }
  CodexRuntime(
      {required this.root,
      required this.platform,
      required this.asset,
      required this.notify,
      required this.httpClient,
      required this.inUse,
      this.licenses = const []});
  final Directory root;
  final String platform;
  final CodexAsset asset;
  final void Function() notify;
  final HttpClient Function() httpClient;
  final bool Function() inUse;
  final List<CodexLicense> licenses;
  UiCodexStatus _status = UiCodexStatus.notInstalled;
  String? _problem;
  int _received = 0;
  bool _cancelled = false;
  HttpClient? _client;
  Future<void>? _installing;
  Directory get installed => Directory(p.join(root.path, codexVersion));
  File get partial => File(p.join(root.path, '${asset.name}.part'));
  File get _settings => File(p.join(root.path, 'settings.json'));
  String get _binary => p.join(installed.path, asset.executable);

  Future<UiCodexRuntimeChoice> choice() async {
    if (!await _settings.exists()) return const UiCodexRuntimeChoice();
    final json = jsonDecode(await _settings.readAsString()) as Map;
    return UiCodexRuntimeChoice(
        source: UiCodexSource.values.byName(json['source'] as String),
        executable: json['executable'] as String?,
        mirror: json['mirror'] as String?);
  }

  Future<void> configure(UiCodexRuntimeChoice value) async {
    if (_installing != null) throw StateError('请先取消下载');
    if (value.source == UiCodexSource.specified &&
        (value.executable == null || !p.isAbsolute(value.executable!))) {
      throw const FormatException('请选择 Codex 原生程序的绝对路径');
    }
    if (value.mirror?.isNotEmpty == true) {
      final uri = Uri.tryParse(value.mirror!);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException('镜像需为不含认证信息的 HTTPS 目录地址');
      }
    }
    await root.create(recursive: true);
    final staging = File('${_settings.path}.pending');
    await staging.writeAsString(
        jsonEncode({
          'source': value.source.name,
          'executable': value.executable,
          'mirror': value.mirror
        }),
        flush: true);
    await staging.rename(_settings.path);
    notify();
  }

  Future<bool> _ready() async =>
      await File(p.join(installed.path, 'installed.json')).exists() &&
      await File(_binary).exists();

  Future<UiCodexRuntime> state() async {
    final selected = await choice();
    final ready = await _ready();
    return UiCodexRuntime(
        status: _status == UiCodexStatus.notInstalled && ready
            ? UiCodexStatus.ready
            : _status,
        version: selected.source == UiCodexSource.managed ? codexVersion : null,
        source: selected.source,
        receivedBytes: _received,
        totalBytes: asset.bytes,
        problem: _problem,
        mirror: selected.mirror,
        executable: selected.source == UiCodexSource.managed
            ? (ready ? _binary : null)
            : selected.source == UiCodexSource.path
                ? (platform == 'windows' ? 'codex.exe' : 'codex')
                : selected.executable,
        licensesDirectory: ready ? p.join(installed.path, 'licenses') : null);
  }

  Future<String> executable() async {
    final selected = await choice();
    if (selected.source == UiCodexSource.path) {
      return platform == 'windows' ? 'codex.exe' : 'codex';
    }
    if (selected.source == UiCodexSource.specified) return selected.executable!;
    if (!await _ready()) await install();
    if (!await _ready()) throw StateError(_problem ?? 'Codex 尚未安装');
    return File(_binary).absolute.path;
  }

  Future<void> install() {
    if (_installing case final operation?) return operation;
    final operation = _install();
    _installing = operation.whenComplete(() => _installing = null);
    return _installing!;
  }

  void _update(UiCodexStatus status, [String? problem]) {
    _status = status;
    _problem = problem;
    notify();
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<void> _install() async {
    _cancelled = false;
    final staging = Directory('${installed.path}.pending');
    try {
      if (await _ready()) {
        _update(UiCodexStatus.ready);
        return;
      }
      await root.create(recursive: true);
      if (await staging.exists()) await staging.delete(recursive: true);
      final selected = await choice();
      await SystemProxyService.instance.initialize();
      _client = httpClient();
      _client!.autoUncompress = false;
      _client!.connectionTimeout = const Duration(seconds: 30);
      _update(UiCodexStatus.downloading);
      await _download(asset.url, asset.name, asset.sha256, asset.bytes, partial,
          selected.mirror,
          progress: true);
      _checkCancelled();
      await staging.create(recursive: true);
      await extractCodexArchive(partial, staging, platform);
      _checkCancelled();
      if (!await File(p.join(staging.path, asset.executable)).exists()) {
        throw const RuntimeInstallException('运行包缺少 Codex 原生程序');
      }
      final licenseDir =
          await Directory(p.join(staging.path, 'licenses')).create();
      for (final license in licenses) {
        final file = File(p.join(root.path, '${license.name}.part'));
        await _download(license.url, license.name, license.sha256,
            license.bytes, file, selected.mirror);
        await file.copy(p.join(licenseDir.path, license.name));
        await file.delete();
      }
      // Preserve any notices shipped anywhere in the native package as well.
      await for (final entity in Directory(p.join(staging.path, 'package'))
          .list(recursive: true, followLinks: false)) {
        if (entity is File &&
            RegExp(r'^(licen[cs]e|notice|copying|copyright)',
                    caseSensitive: false)
                .hasMatch(p.basename(entity.path))) {
          final target = File(p.join(
              licenseDir.path, p.relative(entity.path, from: staging.path)));
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
        }
      }
      if (platform == 'macos') {
        final binary = p.join(staging.path, asset.executable);
        final signature = await Process.run('/usr/bin/codesign',
            ['--verify', '--strict', '-R=notarized', binary]);
        if (signature.exitCode != 0) {
          throw const RuntimeInstallException('Codex 签名验证失败');
        }
        // Do not remove quarantine or alter the upstream signature.
      }
      _checkCancelled();
      await File(p.join(staging.path, 'installed.json')).writeAsString(
          jsonEncode({
            'version': codexVersion,
            'sha256': asset.sha256,
            'asset': asset.name
          }),
          flush: true);
      if (await installed.exists()) await installed.delete(recursive: true);
      await staging.rename(installed.path);
      await partial.delete();
      _update(UiCodexStatus.ready);
    } catch (error) {
      if (_cancelled) {
        _update(UiCodexStatus.notInstalled);
      } else {
        _update(
            UiCodexStatus.failed,
            error is RuntimeInstallException
                ? error.message
                : error is SocketException || error is TimeoutException
                    ? '运行包下载连接失败，请重试'
                    : '运行包安装失败，请重试');
      }
    } finally {
      _client?.close(force: true);
      _client = null;
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  Future<void> _download(String url, String name, String digest, int bytes,
      File file, String? mirror,
      {bool progress = false}) async {
    var offset = await file.exists() ? await file.length() : 0;
    if (offset > bytes) {
      await file.delete();
      offset = 0;
    }
    if (progress) {
      _received = offset;
      notify();
    }
    if (offset < bytes) {
      final uri = Uri.parse(mirror == null || mirror.isEmpty
          ? url
          : '${mirror.replaceFirst(RegExp(r'/+$'), '')}/$name');
      final request = await _client!.getUrl(uri);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        offset = 0;
      } else if (response.statusCode != 206 ||
          response.headers.value(HttpHeaders.contentRangeHeader) !=
              'bytes $offset-${bytes - 1}/$bytes') {
        throw const RuntimeInstallException('运行包下载失败或续传响应不正确');
      }
      final output =
          file.openWrite(mode: offset == 0 ? FileMode.write : FileMode.append);
      try {
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          _checkCancelled();
          offset += chunk.length;
          if (offset > bytes) throw const RuntimeInstallException('运行包长度不正确');
          output.add(chunk);
          if (progress) {
            _received = offset;
            notify();
          }
        }
      } finally {
        await output.close();
      }
      if (offset != bytes) throw const RuntimeInstallException('下载未完成，请继续安装');
    }
    _checkCancelled();
    if (progress) _update(UiCodexStatus.verifying);
    final hash = await sha256.bind(file.openRead()).first;
    if (hash.toString() != digest) {
      await file.delete();
      throw const RuntimeInstallException('SHA-256 校验失败，已删除下载文件');
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _client?.close(force: true);
    await _installing;
  }

  Future<void> remove() async {
    if (inUse()) throw StateError('请先结束当前 Codex 会话');
    await cancel();
    if (await installed.exists()) await installed.delete(recursive: true);
    if (await partial.exists()) await partial.delete();
    _received = 0;
    _update(UiCodexStatus.notInstalled);
  }
}

/// All desktop targets ship bsdtar (tar.exe on supported Windows 10/11).
/// Extracting the whole archive keeps helper locations and executable modes.
Future<void> extractCodexArchive(
    File archive, Directory target, String platform) async {
  final tar = platform == 'windows' && Platform.isWindows ? 'tar.exe' : 'tar';
  final result = await Process.run(
      tar, ['-xzf', archive.absolute.path, '-C', target.absolute.path]);
  if (result.exitCode != 0) {
    throw const RuntimeInstallException('运行包解压失败');
  }
}

final class CodexLicense {
  const CodexLicense(this.name, this.url, this.sha256, this.bytes);
  final String name, url, sha256;
  final int bytes;
}

final class RuntimeInstallException implements Exception {
  const RuntimeInstallException(this.message);
  final String message;
}

final class _Cancelled implements Exception {
  const _Cancelled();
}
