import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../chat/dsh_runtime.dart';
import '../ui_data/host_settings.dart';
import 'runtime_install_exception.dart';
import 'dsh_manifest.dart';

/// Mirrors that stand in for the official addresses when those do not
/// deliver a file: [node] replaces `https://nodejs.org/dist`, [registry] the
/// npm registry, for manifest addresses whose host is in [hosts].
final class DshFallback {
  const DshFallback(
      {required this.node, required this.registry, required this.hosts});

  /// npmmirror: the same paths as nodejs.org/dist and the npm registry.
  static const npmmirror = DshFallback(
      node: 'https://npmmirror.com/mirrors/node',
      registry: 'https://registry.npmmirror.com',
      hosts: {'nodejs.org', 'registry.npmjs.org'});

  final String node, registry;
  final Set<String> hosts;
}

/// Fetches the Node.js and the trimmed DeepSeek Harness that run Nipa, into
/// Next's own data root, from nodejs.org and the npm registry (or a mirror
/// the user names). Every file is pinned by SHA-256 in the manifest, so a
/// mirror can change where bytes come from but never what they are.
///
/// Downloads keep their partial files and continue where they stopped; a
/// finished, verified file stays until the whole runtime is in place. The
/// runtime appears in one rename, so a stopped installation leaves nothing
/// half-usable.
final class DshInstall {
  DshInstall(
      {required this.root,
      required this.manifest,
      required this.platform,
      required this.notify,
      required this.httpClient,
      required this.inUse,
      this.beforeInstall,
      this.verifySignature = true,
      this.fallback = DshFallback.npmmirror,
      this.concurrency = 6});

  final Directory root;
  final DshManifest manifest;

  /// The platform key (`macos-arm64`...), or null when this machine has none.
  final String? platform;
  final void Function() notify;
  final HttpClient Function() httpClient;
  final bool Function() inUse;

  /// Runs before a download starts (e.g. reading the system proxy).
  final Future<void> Function()? beforeInstall;

  /// On macOS the Node.js binary must carry its publisher's notarized
  /// signature. Tests with a stand-in binary turn this off.
  final bool verifySignature;

  /// Where a file comes from when the official address does not deliver it.
  /// Only used while the person has named no mirror of their own, and only
  /// for manifest addresses on [DshFallback.hosts]. Bytes from it are held
  /// to the same SHA-256 and size.
  final DshFallback? fallback;
  final int concurrency;

  UiDshStatus _status = UiDshStatus.notInstalled;
  String? _problem;
  int _received = 0;
  final _item = <String, int>{};
  bool _cancelled = false;

  /// Hosts that failed to connect during this installation: later files try
  /// their other source first instead of waiting for them again.
  final _unreachable = <String>{};
  HttpClient? _client;
  Future<void>? _installing;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  Directory get installed => Directory(p.join(root.path, manifest.id));
  Directory get _downloads => Directory(p.join(root.path, 'downloads'));
  File get _settings => File(p.join(root.path, 'settings.json'));

  bool get supported => platform != null && manifest.supports(platform!);
  bool get busy => _installing != null;

  String get _nodeName => platform!.startsWith('windows') ? 'node.exe' : 'node';
  String get _node => p.join(installed.path, 'node', _nodeName);
  String get _bin => p.join(installed.path, 'lib', 'node_modules',
      '@deepseek-ai', 'dsh', 'lib', 'bin.js');

  Future<({String? registry, String? node})> mirrors() async {
    if (!await _settings.exists()) return (registry: null, node: null);
    final json = jsonDecode(await _settings.readAsString()) as Map;
    return (
      registry: json['registryMirror'] as String?,
      node: json['nodeMirror'] as String?
    );
  }

  static String? _mirror(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final loopback = uri != null &&
        (uri.host == 'localhost' ||
            InternetAddress.tryParse(uri.host)?.isLoopback == true);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http' && loopback) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('镜像需为不含认证信息的 HTTPS 地址');
    }
    return text.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<void> configure({String? registryMirror, String? nodeMirror}) async {
    if (_installing != null) throw StateError('请先取消下载');
    final values = {
      'registryMirror': _mirror(registryMirror),
      'nodeMirror': _mirror(nodeMirror),
    };
    await root.create(recursive: true);
    final staging = File('${_settings.path}.pending');
    await staging.writeAsString(jsonEncode(values), flush: true);
    await staging.rename(_settings.path);
    notify();
  }

  Future<bool> _ready() async =>
      supported &&
      await File(p.join(installed.path, 'installed.json')).exists() &&
      await File(_node).exists() &&
      await File(_bin).exists();

  int get _total {
    if (!supported) return 0;
    return manifest.nodes[platform]!.bytes +
        {
          for (final package in manifest.packagesFor(platform!))
            package.sha256: package.bytes
        }.values.fold(0, (a, b) => a + b);
  }

  Future<UiDshRuntime> state() async {
    final ready = await _ready();
    final configured = await mirrors();
    return UiDshRuntime(
        status: !supported
            ? UiDshStatus.unsupported
            : _status == UiDshStatus.notInstalled && ready
                ? UiDshStatus.ready
                : _status,
        version: manifest.dsh,
        receivedBytes: _received,
        totalBytes: _total,
        problem: _problem,
        registryMirror: configured.registry,
        nodeMirror: configured.node);
  }

  /// The runtime to launch, or null while it is not installed.
  Future<DshRuntime?> runtime() async => await _ready()
      ? DshRuntime(
          node: File(_node).absolute.path,
          bin: File(_bin).absolute.path,
          version: manifest.dsh)
      : null;

  Future<void> install() {
    if (_installing case final operation?) return operation;
    final operation = _install();
    _installing = operation.whenComplete(() => _installing = null);
    return _installing!;
  }

  void _update(UiDshStatus status, [String? problem]) {
    _status = status;
    _problem = problem;
    _lastNotify = DateTime.now();
    notify();
  }

  void _progress() {
    final now = DateTime.now();
    if (now.difference(_lastNotify) < const Duration(milliseconds: 150)) return;
    _lastNotify = now;
    notify();
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  Future<void> _install() async {
    _cancelled = false;
    _item.clear();
    _unreachable.clear();
    _received = 0;
    final staging = Directory('${installed.path}.pending');
    try {
      // A platform without a traced runtime says so in its state; there is
      // nothing to fetch.
      if (!supported) return;
      if (await _ready()) {
        _update(UiDshStatus.ready);
        return;
      }
      await root.create(recursive: true);
      if (await staging.exists()) await staging.delete(recursive: true);
      final configured = await mirrors();
      final node = manifest.nodes[platform]!;
      final items = <_Item>[
        _Item(node.name, node.sha256, node.bytes,
            _sources(_nodeUrl(node, configured.node), configured.node == null
                ? _fallbackNode(node) : null)),
        for (final package in {
          for (final package in manifest.packagesFor(platform!))
            package.sha256: package
        }.values)
          _Item(
              '${package.name.split('/').last}-${package.version}.tgz',
              package.sha256,
              package.bytes,
              _sources(
                  '${configured.registry ?? manifest.registry.replaceFirst(RegExp(r'/+$'), '')}/${package.url}',
                  configured.registry == null ? _fallbackPackage(package) : null)),
      ];
      await _downloads.create(recursive: true);
      await beforeInstall?.call();
      _client = httpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 30)
        ..maxConnectionsPerHost = concurrency;
      _update(UiDshStatus.downloading);
      await _downloadAll(items);
      _checkCancelled();
      _update(UiDshStatus.unpacking);
      await staging.create(recursive: true);
      await _unpack(staging, node);
      _checkCancelled();
      await _checkNode(staging);
      await File(p.join(staging.path, 'installed.json')).writeAsString(
          jsonEncode({
            'dsh': manifest.dsh,
            'node': manifest.nodeVersion,
            'platform': platform,
            'packages': manifest.packagesFor(platform!).length,
          }),
          flush: true);
      if (await installed.exists()) await installed.delete(recursive: true);
      await staging.rename(installed.path);
      await _downloads.delete(recursive: true);
      await _removeOlder();
      _update(UiDshStatus.ready);
    } catch (error) {
      if (_cancelled) {
        _update(UiDshStatus.notInstalled);
      } else {
        _update(
            UiDshStatus.failed,
            error is RuntimeInstallException
                ? error.message
                : error is FileSystemException
                    ? '写入失败：${error.osError?.message ?? error.message}'
                    : '运行环境安装失败：$error');
      }
    } finally {
      _client?.close(force: true);
      _client = null;
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  List<_Source> _sources(String primary, String? backup) => [
        _Source(backup == null ? '' : '官方源', primary),
        if (backup != null) _Source('备用源', backup),
      ];

  String? _fallbackNode(DshNodeAsset asset) => fallback != null &&
          fallback!.hosts.contains(Uri.parse(asset.url).host)
      ? _nodeUrl(asset, fallback!.node)
      : null;

  String? _fallbackPackage(DshPackage package) => fallback != null &&
          fallback!.hosts.contains(Uri.parse(manifest.registry).host)
      ? '${fallback!.registry}/${package.url}'
      : null;

  String _nodeUrl(DshNodeAsset asset, String? mirror) {
    if (mirror == null) return asset.url;
    final marker = '/v${manifest.nodeVersion}/';
    return '$mirror$marker${asset.url.substring(asset.url.indexOf(marker) + marker.length)}';
  }

  Future<void> _downloadAll(List<_Item> items) async {
    var next = 0;
    Object? failure;
    Future<void> worker() async {
      while (failure == null && !_cancelled) {
        final index = next++;
        if (index >= items.length) return;
        try {
          await _fetch(items[index]);
        } catch (error) {
          if (failure == null) {
            failure = error;
            _client?.close(force: true);
          }
        }
      }
    }

    await Future.wait(
        [for (var i = 0; i < math.min(concurrency, items.length); i++) worker()]);
    _checkCancelled();
    if (failure != null) throw failure!;
  }

  void _count(_Item item, int bytes) {
    _received += bytes - (_item[item.digest] ?? 0);
    _item[item.digest] = bytes;
    _progress();
  }

  File _file(_Item item) => File(p.join(_downloads.path, item.digest));

  Future<void> _fetch(_Item item) async {
    final file = _file(item);
    if (await file.exists() && await file.length() == item.bytes) {
      _count(item, item.bytes);
      return;
    }
    // A host that did not answer earlier in this installation goes last.
    final order = [
      ...item.sources.where((s) => !_unreachable.contains(s.host)),
      ...item.sources.where((s) => _unreachable.contains(s.host)),
    ];
    final failures = <_Source, _SourceFailure>{};
    for (final source in order) {
      try {
        await _fetchFrom(item, source, hasOther: order.length > 1);
        return;
      } on _SourceFailure catch (failure) {
        _checkCancelled();
        if (failure.unreachable) _unreachable.add(source.host);
        failures[source] = failure;
      }
    }
    if (failures.length == 1) {
      final MapEntry(key: source, value: failure) = failures.entries.single;
      throw RuntimeInstallException(
          '${item.name} 下载失败（${source.host}）：${failure.reason}');
    }
    throw RuntimeInstallException('${item.name} 下载失败，'
        '${[for (final source in item.sources) '${source.role}（${source.host}）：${failures[source]!.reason}'].join('；')}');
  }

  /// One source for one file: transfers (continuing a partial file), then
  /// holds the bytes to the manifest's SHA-256.
  Future<void> _fetchFrom(_Item item, _Source source, {required bool hasOther}) async {
    final file = _file(item);
    final part = File('${file.path}.part');
    // With another source to turn to, a failing one is given up on sooner.
    final attempts = hasOther ? 2 : 3;
    for (var attempt = 0;; attempt++) {
      try {
        await _transfer(item, source, part);
        break;
      } on _Retry catch (retry) {
        if (attempt >= attempts - 1) throw _SourceFailure(retry.fact);
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      } on SocketException catch (error) {
        _checkCancelled();
        final reason = '连接中断：${error.osError?.message ?? error.message}';
        if (hasOther || attempt >= attempts - 1) {
          throw _SourceFailure(reason, unreachable: true);
        }
        await Future<void>.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      } on TimeoutException {
        _checkCancelled();
        if (hasOther || attempt >= attempts - 1) {
          throw const _SourceFailure('响应超时', unreachable: true);
        }
      } on HttpException catch (error) {
        _checkCancelled();
        if (attempt >= attempts - 1) {
          throw _SourceFailure('连接中断：${error.message}', unreachable: hasOther);
        }
      } on TlsException {
        throw const _SourceFailure('服务器证书无法验证', unreachable: true);
      }
    }
    _checkCancelled();
    final digest = await Isolate.run(
        () async => (await sha256.bind(part.openRead()).first).toString());
    if (digest != item.digest) {
      await part.delete();
      _count(item, 0);
      throw const _SourceFailure('SHA-256 与预期不符，已删除');
    }
    await part.rename(file.path);
  }

  Future<void> _transfer(_Item item, _Source source, File part) async {
    var offset = await part.exists() ? await part.length() : 0;
    if (offset > item.bytes) {
      await part.delete();
      offset = 0;
    }
    _count(item, offset);
    if (offset == item.bytes) return;
    final request = await _client!.getUrl(Uri.parse(source.url));
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (offset > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode == 416) {
      await response.drain<void>();
      await part.delete();
      throw const _Retry('续传位置无效，已重新开始');
    }
    if (response.statusCode == 200) {
      offset = 0;
    } else if (response.statusCode == 206) {
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      if (range == null || !range.startsWith('bytes $offset-')) {
        await response.drain<void>();
        await part.delete();
        throw const _Retry('续传响应不正确，已重新开始');
      }
    } else {
      await response.drain<void>();
      if (response.statusCode >= 500 || response.statusCode == 429) {
        throw _Retry('服务器暂时不可用（HTTP ${response.statusCode}）');
      }
      throw _SourceFailure('HTTP ${response.statusCode}');
    }
    final output =
        part.openWrite(mode: offset == 0 ? FileMode.write : FileMode.append);
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        _checkCancelled();
        offset += chunk.length;
        if (offset > item.bytes) {
          throw const _SourceFailure('长度超出预期');
        }
        output.add(chunk);
        _count(item, offset);
      }
    } finally {
      await output.close();
    }
    if (offset != item.bytes) throw _Retry('只收到 $offset / ${item.bytes} 字节');
  }

  // --- unpacking ---------------------------------------------------------

  Future<void> _unpack(Directory staging, DshNodeAsset node) async {
    final nodeDir = await Directory(p.join(staging.path, 'node')).create();
    final archive = File(p.join(_downloads.path, node.sha256));
    if (node.archive == 'file') {
      await archive.copy(p.join(nodeDir.path, node.executable));
    } else {
      final top = node.executable.split('/').first;
      await _tar(archive, nodeDir, strip: 2, members: [node.executable]);
      await _tar(archive, nodeDir, strip: 1, members: ['$top/LICENSE']);
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', p.join(nodeDir.path, _nodeName)]);
    }
    final lib = await Directory(p.join(staging.path, 'lib')).create();
    final packages = manifest.packagesFor(platform!);
    var next = 0;
    Object? failure;
    Future<void> worker() async {
      while (failure == null && !_cancelled) {
        final index = next++;
        if (index >= packages.length) return;
        final package = packages[index];
        try {
          final target = Directory(p.join(lib.path, package.path));
          await target.create(recursive: true);
          await _tar(File(p.join(_downloads.path, package.sha256)), target,
              strip: 1);
        } catch (error) {
          failure ??= error;
        }
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    _checkCancelled();
    if (failure != null) throw failure!;
    if (!await File(p.join(lib.path, 'node_modules', '@deepseek-ai', 'dsh',
            'lib', 'bin.js'))
        .exists()) {
      throw const RuntimeInstallException('运行包缺少 DSH 启动文件');
    }
  }

  Future<void> _tar(File archive, Directory target,
      {required int strip, List<String> members = const []}) async {
    // Windows' own bsdtar: a GNU tar earlier in PATH (Git for Windows) reads
    // the drive letter of `D:\...` as a remote host.
    final windowsTar =
        '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\tar.exe';
    final tar = Platform.isWindows
        ? File(windowsTar).existsSync()
            ? windowsTar
            : 'tar.exe'
        : File('/usr/bin/tar').existsSync()
            ? '/usr/bin/tar'
            : 'tar';
    final result = await Process.run(tar, [
      '-xzf',
      archive.absolute.path,
      '-C',
      target.absolute.path,
      '--strip-components=$strip',
      ...members,
    ]);
    if (result.exitCode != 0) {
      throw RuntimeInstallException(
          '解压失败：${p.basename(archive.path)}（${(result.stderr as String).trim().split('\n').first}）');
    }
  }

  /// The binary must be Node.js as its publisher signed it, and must start.
  Future<void> _checkNode(Directory staging) async {
    final node = p.join(staging.path, 'node', _nodeName);
    if (Platform.isMacOS && verifySignature) {
      final signature = await Process.run('/usr/bin/codesign',
          ['--verify', '--strict', '-R=notarized', node]);
      if (signature.exitCode != 0) {
        throw const RuntimeInstallException('Node.js 的签名验证失败');
      }
    }
    final run = await Process.run(node, ['--version']);
    final version = (run.stdout as String).trim();
    if (run.exitCode != 0 || version != 'v${manifest.nodeVersion}') {
      throw RuntimeInstallException(
          'Node.js 无法启动：${run.exitCode == 0 ? version : (run.stderr as String).trim()}');
    }
  }

  Future<void> _removeOlder() async {
    await for (final entity in root.list(followLinks: false)) {
      if (entity is Directory &&
          p.basename(entity.path).startsWith('dsh-') &&
          p.basename(entity.path) != manifest.id) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<void> cancel() async {
    _cancelled = true;
    _client?.close(force: true);
    await _installing;
  }

  Future<void> remove() async {
    if (inUse()) throw StateError('请先结束当前梨花会话');
    await cancel();
    if (await installed.exists()) await installed.delete(recursive: true);
    if (await _downloads.exists()) await _downloads.delete(recursive: true);
    _received = 0;
    _item.clear();
    _update(UiDshStatus.notInstalled);
  }
}

final class _Item {
  const _Item(this.name, this.digest, this.bytes, this.sources);
  final String name, digest;
  final int bytes;

  /// Where the file can be had, in the order they are tried.
  final List<_Source> sources;
}

/// An address for a file. [role] names it in a failure when there is more
/// than one ('官方源', '备用源').
final class _Source {
  const _Source(this.role, this.url);
  final String role, url;
  String get host => Uri.parse(url).host;
}

/// A source gave up: [reason] says how, without the file's name.
/// [unreachable] when it did not connect or answer at all.
final class _SourceFailure implements Exception {
  const _SourceFailure(this.reason, {this.unreachable = false});
  final String reason;
  final bool unreachable;
}

final class _Retry implements Exception {
  const _Retry(this.fact);
  final String fact;
}

final class _Cancelled implements Exception {
  const _Cancelled();
}
