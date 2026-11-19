import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'store_fetch.dart';
import 'store_index.dart';

/// An npm tarball's files under its top folder (`package/`), read without
/// trusting it: only regular files with plain relative paths, never links,
/// within [maxFiles] and [maxBytes] in all.
Map<String, Uint8List> readPackageTarball(List<int> tgz,
    {int maxFiles = 5000, int maxBytes = 64 << 20}) {
  final Archive archive;
  // Unpacked as it is counted: a small archive that expands without end is
  // stopped at the limit, not after it has filled memory.
  final tar = _CappedBytes(maxBytes);
  try {
    final input = gzip.decoder.startChunkedConversion(tar);
    for (var at = 0; at < tgz.length; at += 1 << 16) {
      input.add(tgz.sublist(at, math.min(at + (1 << 16), tgz.length)));
    }
    input.close();
    archive = TarDecoder().decodeBytes(tar.bytes.takeBytes());
  } on StoreFormatException {
    rethrow;
  } catch (_) {
    throw const StoreFormatException('软件包不是有效的 tar.gz');
  }
  final files = <String, Uint8List>{};
  var total = 0;
  for (final entry in archive) {
    if (!entry.isFile || entry.isSymbolicLink) continue;
    final name = entry.name.replaceAll('\\', '/');
    final slash = name.indexOf('/');
    if (slash <= 0) continue;
    final path = name.substring(slash + 1);
    if (!_extractable(path)) {
      throw StoreFormatException('软件包里有不安全的路径：$name');
    }
    final bytes = entry.content;
    total += bytes.length;
    if (files.length >= maxFiles || total > maxBytes) {
      throw const StoreFormatException('软件包过大');
    }
    if (files.containsKey(path)) {
      throw StoreFormatException('软件包里有重复的文件：$path');
    }
    files[path] = bytes;
  }
  if (files.isEmpty) throw const StoreFormatException('软件包是空的');
  return files;
}

final class _CappedBytes implements Sink<List<int>> {
  _CappedBytes(this.limit);
  final int limit;
  final bytes = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    if (bytes.length + chunk.length > limit) {
      throw const StoreFormatException('软件包过大');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

bool _extractable(String path) =>
    path.isNotEmpty &&
    path.length <= 300 &&
    !path.startsWith('/') &&
    !path.contains(':') &&
    !path.codeUnits.any((c) => c < 0x20) &&
    path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');

/// Writes [files] (from [readPackageTarball]) under [target].
Future<void> writePackageFiles(
    Map<String, Uint8List> files, Directory target) async {
  for (final MapEntry(key: path, value: bytes) in files.entries) {
    final file = File(p.joinAll([target.path, ...path.split('/')]));
    if (!p.isWithin(target.path, file.path)) {
      throw StoreFormatException('软件包里有不安全的路径：$path');
    }
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: false);
  }
}

/// A package someone named, resolved and fetched: what the store would
/// install, and its tarball.
typedef NpmResolution = ({StoreItem item, List<int> tarball});

/// Resolves npm packages nobody reviewed: DSH plugins whose runtime
/// dependencies the DSH runtime itself provides, or skills (a package with
/// `SKILL.md` at its root). Nothing in a package runs while installing; one
/// that needs its install scripts is refused, as is a plugin whose
/// `cordis.patch.yml` does more than add its own entry.
final class NpmPackages {
  NpmPackages(this.fetch, {required this.registries});
  final StoreFetch fetch;

  /// Registry addresses, the one to try first first.
  final List<String> registries;

  static final _spec = RegExp(
      r'^((?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*)(?:@([0-9A-Za-z.+-]+))?$');

  /// `name` or `name@version` (a version or a dist-tag such as `latest`).
  static (String, String) parseSpec(String spec) {
    final match = _spec.firstMatch(spec.trim());
    if (match == null || !npmName(match[1]!)) {
      throw const StoreFormatException('请输入 npm 包名，例如 some-package 或 @scope/name@1.2.3');
    }
    return (match[1]!, match[2] ?? 'latest');
  }

  static String _encoded(String name) => name.replaceFirst('/', '%2f');

  static String tarballPath(String name, String version) =>
      '$name/-/${name.split('/').last}-$version.tgz';

  /// The store id a package is installed as.
  static String idFor(String name) {
    final plain = name
        .replaceAll('@', '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final id = 'npm-$plain';
    return id.length <= 48 ? id : id.substring(0, 48).replaceAll(RegExp(r'-+$'), '');
  }

  /// [provided]: the packages of the installed DSH runtime, null when none
  /// is installed (a plugin then cannot be checked, nor loaded).
  Future<NpmResolution> resolve(String spec,
      {required Set<String>? provided}) async {
    final (name, wanted) = parseSpec(spec);
    final manifestText = await fetch.text([
      for (final registry in registries)
        Uri.parse('$registry/${_encoded(name)}/${Uri.encodeComponent(wanted)}')
    ], maxBytes: 4 << 20, headers: {'accept': 'application/json'});
    final Object? manifest;
    try {
      manifest = jsonDecode(manifestText);
    } on FormatException {
      throw const StoreFormatException('npm 返回的不是有效的软件包信息');
    }
    if (manifest is! Map || manifest['name'] != name) {
      throw StoreFormatException('npm 上找不到 $spec');
    }
    final version = manifest['version'];
    final dist = manifest['dist'];
    if (version is! String || dist is! Map || dist['integrity'] is! String) {
      throw StoreFormatException('$name 缺少版本或完整性校验信息');
    }
    final integrity = dist['integrity'] as String;
    final tarball = await fetch.bytes([
      for (final registry in registries)
        Uri.parse('$registry/${tarballPath(name, version)}')
    ], integrity: integrity, maxBytes: maxPackageBytes);
    final files = readPackageTarball(tarball);

    final keywords = {
      for (final k in manifest['keywords'] as List? ?? const [])
        if (k is String) k.toLowerCase()
    };
    final peers = Map<String, Object?>.from(
        manifest['peerDependencies'] as Map? ?? const {});
    final optionalPeers = {
      for (final MapEntry(:key, :value)
          in (manifest['peerDependenciesMeta'] as Map? ?? const {}).entries)
        if (value is Map && value['optional'] == true) key as String
    };
    final dependencies = Map<String, Object?>.from(
        manifest['dependencies'] as Map? ?? const {});
    final bundled = {
      for (final b in (manifest['bundleDependencies'] ??
              manifest['bundledDependencies']) as List? ??
          const [])
        if (b is String) b
    };
    final plugin = peers.containsKey('@deepseek-ai/cordis') ||
        keywords.contains('dsh-plugin') ||
        keywords.contains('deepseek-harness');
    final skill = files.containsKey('SKILL.md');
    if (!plugin && !skill) {
      throw StoreFormatException(
          '$name 既不是 DeepSeek Harness 插件，也没有 SKILL.md，不能装给梨花');
    }
    final notices = [
      '这个包没有经过审核。${plugin ? '插件在梨花的运行环境里运行' : '梨花会运行它的脚本'}，'
          '能读写你的账户能访问的文件、连接任意网络地址，也能看到交给它的数据。只安装你信任的包。',
      if (manifest['deprecated'] case final String why) '作者已弃用这个版本：$why',
    ];
    final description = switch (manifest['description']) {
      final String d when d.trim().isNotEmpty =>
        d.length <= 400 ? d.trim() : '${d.substring(0, 399)}…',
      _ => '（没有说明）',
    };
    final author = switch (manifest['author']) {
      final String a => a,
      final Map a when a['name'] is String => a['name'] as String,
      _ => null,
    };
    final package = StorePackage(
        path: 'node_modules/$name',
        name: name,
        version: version,
        url: tarballPath(name, version),
        integrity: integrity,
        bytes: tarball.length);
    final id = idFor(name);
    if (plugin) {
      if (provided == null) {
        throw const StoreFormatException(
            '这是 DeepSeek Harness 插件，请先在梨花的设置里安装运行环境');
      }
      final scripts = manifest['scripts'] as Map? ?? const {};
      final install = [
        for (final hook in const ['preinstall', 'install', 'postinstall'])
          if (scripts[hook] != null) hook
      ];
      if (install.isNotEmpty || manifest['gypfile'] == true) {
        throw StoreFormatException(
            '$name 需要在安装时运行脚本（${install.join('、')}），商店不运行安装脚本');
      }
      final missing = [
        for (final dependency in dependencies.keys)
          if (!provided.contains(dependency) && !bundled.contains(dependency))
            dependency,
        for (final peer in peers.keys)
          if (!provided.contains(peer) && !optionalPeers.contains(peer)) peer,
      ];
      if (missing.isNotEmpty) {
        throw StoreFormatException(
            '$name 依赖的 ${missing.join('、')} 不在梨花的运行环境里，目前只能安装依赖都由运行环境提供的插件');
      }
      final rows = _patchRows(name, files['cordis.patch.yml'], id);
      return (
        item: StoreItem(
          id: id,
          kind: StoreKind.plugin,
          origin: StoreOrigin.npm,
          name: name,
          version: version,
          description: description,
          author: author,
          category: keywords.any((k) => const {
                    'llm',
                    'provider',
                    'model-provider',
                    'llm-provider'
                  }.contains(k))
              ? 'model'
              : 'tool',
          notices: notices,
          packages: [package],
          peers: [
            for (final dependency in {...dependencies.keys, ...peers.keys})
              if (provided.contains(dependency) && !bundled.contains(dependency))
                dependency
          ]..sort(),
          dsh: rows,
        ),
        tarball: tarball,
      );
    }
    final skillFiles = [
      for (final MapEntry(key: path, value: bytes) in files.entries)
        if (path != 'package.json' && safeRelativePath(path))
          StoreFile(
              path: path,
              url: path,
              sha256: sha256.convert(bytes).toString(),
              bytes: bytes.length)
    ]..sort((a, b) => a.path.compareTo(b.path));
    if (skillFiles.length > maxSkillFiles ||
        skillFiles.any((f) => f.bytes > maxFileBytes)) {
      throw StoreFormatException('$name 的文件太多或太大，不像一个技能');
    }
    return (
      item: StoreItem(
        id: id,
        kind: StoreKind.skill,
        origin: StoreOrigin.npm,
        name: name,
        version: version,
        description: description,
        author: author,
        notices: notices,
        files: skillFiles,
        packages: [package],
      ),
      tarball: tarball,
    );
  }

  /// The rows of a plugin's own `cordis.patch.yml`, accepted only when each
  /// adds an entry of this package; without one, a single row for it.
  static List<StoreDshRow> _patchRows(String name, Uint8List? patch, String id) {
    // Without a patch of its own, the plugin is loaded as the store item
    // (`npm-...`), which no plugin of DSH or NipaPlay is called.
    if (patch == null) return [StoreDshRow(id: id, package: name)];
    final Object? doc;
    try {
      doc = loadYaml(utf8.decode(patch));
    } catch (_) {
      throw StoreFormatException('$name 的 cordis.patch.yml 无法读取');
    }
    final rows = <StoreDshRow>[];
    if (doc is! YamlList) {
      throw StoreFormatException('$name 的 cordis.patch.yml 格式不受支持');
    }
    for (final op in doc) {
      if (op is! YamlMap || op.keys.length != 1 || op['insert'] is! YamlList) {
        throw StoreFormatException(
            '$name 的 cordis.patch.yml 会改动梨花运行环境里的其他插件，不能安装');
      }
      for (final row in op['insert'] as YamlList) {
        if (row is! YamlMap ||
            row['name'] != name ||
            row['id'] is! String ||
            row.keys.any((k) => !const {'id', 'name', 'config', 'inject'}
                .contains(k))) {
          throw StoreFormatException(
              '$name 的 cordis.patch.yml 除了加入它自己，还有别的改动，不能安装');
        }
        rows.add(StoreDshRow.parse({
          'id': row['id'],
          'package': name,
          if (row['config'] != null)
            'config': jsonDecode(jsonEncode(row['config'])),
          if (row['inject'] != null)
            'inject': jsonDecode(jsonEncode(row['inject'])),
        }, '$name 的 cordis.patch.yml', {name}));
      }
    }
    if (rows.isEmpty) {
      throw StoreFormatException('$name 的 cordis.patch.yml 没有加入任何插件');
    }
    return rows;
  }
}
