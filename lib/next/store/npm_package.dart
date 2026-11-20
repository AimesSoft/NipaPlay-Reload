import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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

List<String> packageEntryCandidates(List<int>? manifest) {
  final raw = manifest == null ? null : jsonDecode(utf8.decode(manifest));
  String? relative;
  if (raw is Map) {
    Object? exported = raw['exports'];
    if (exported is Map && exported.containsKey('.')) exported = exported['.'];
    if (exported is Map) {
      exported = exported['import'] ??
          exported['node'] ??
          exported['default'] ??
          exported['require'];
      if (exported is Map) exported = exported['default'];
    }
    relative = exported is String
        ? exported
        : raw['main'] is String
            ? raw['main'] as String
            : null;
  }
  relative ??= 'index.js';
  return [
    relative,
    if (p.extension(relative).isEmpty) ...[
      '$relative.js',
      '$relative/index.js',
    ]
  ];
}

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

typedef NpmOption = ({StoreItem? item, String? reason});

typedef NpmResolution = ({
  String name,
  String requested,
  String version,
  String? deprecated,
  List<String> notices,
  bool hasSkill,
  bool isPlugin,
  Map<StoreKind, NpmOption> options,
  Map<String, Uint8List> files,
});

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
      throw const StoreFormatException(
          '请输入 npm 包名，例如 some-package 或 @scope/name@1.2.3');
    }
    return (match[1]!, match[2] ?? 'latest');
  }

  static String _encoded(String name) => name.replaceFirst('/', '%2f');

  static String tarballPath(String name, String version) =>
      '$name/-/${name.split('/').last}-$version.tgz';

  /// The store id a package is installed as.
  static String idFor(String name) {
    final fingerprint = sha256.convert(utf8.encode(name)).toString();
    return 'npm-${fingerprint.substring(0, 44)}';
  }

  /// [provided]: the packages of the installed DSH runtime, null when none
  /// is installed (a plugin then cannot be checked, nor loaded).
  Future<NpmResolution> resolve(String spec,
      {required Set<String>? provided,
      String? exactVersion,
      String? id,
      String? identityProblem}) async {
    final (name, wanted) = parseSpec(spec);
    if (exactVersion != null &&
        (wanted != 'latest' ||
            name != spec.trim() ||
            !storeVersion(exactVersion))) {
      throw const StoreFormatException('安装时须分别提供 npm 包名和确切版本');
    }
    final requested = exactVersion ?? wanted;
    final manifestText = await fetch.text(
        [
          for (final registry in registries)
            Uri.parse(
                '$registry/${_encoded(name)}/${Uri.encodeComponent(requested)}')
        ],
        maxBytes: 4 << 20,
        headers: {'accept': 'application/json'});
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
    if (version is! String ||
        !storeVersion(version) ||
        dist is! Map ||
        dist['integrity'] is! String) {
      throw StoreFormatException('$name 缺少版本或完整性校验信息');
    }
    if (storeVersion(requested) && requested != version) {
      throw StoreChanged('$name 请求的版本为 $requested，但镜像返回了 $version');
    }
    final integrity = dist['integrity'] as String;
    final tarball = await fetch.bytes([
      for (final registry in registries)
        Uri.parse('$registry/${tarballPath(name, version)}')
    ], integrity: integrity, maxBytes: maxPackageBytes);
    final packageId = id ?? idFor(name);
    return _inspectOffThread(name, requested, version, manifest, tarball,
        integrity, provided, packageId, identityProblem);
  }

  static Future<NpmResolution> _inspectOffThread(
          String name,
          String requested,
          String version,
          Map manifest,
          List<int> tarball,
          String integrity,
          Set<String>? provided,
          String id,
          String? identityProblem) =>
      Isolate.run(() => _inspect(name, requested, version, manifest, tarball,
          integrity, provided, id, identityProblem));

  static NpmResolution _inspect(
      String name,
      String requested,
      String version,
      Map manifest,
      List<int> tarball,
      String integrity,
      Set<String>? provided,
      String id,
      String? identityProblem) {
    final files = readPackageTarball(tarball);

    final keywords = {
      for (final k in manifest['keywords'] is List
          ? manifest['keywords'] as List
          : const [])
        if (k is String) k.toLowerCase()
    };
    final declaredPeers = manifest['peerDependencies'];
    final plugin = (declaredPeers is Map &&
            declaredPeers.containsKey('@deepseek-ai/cordis')) ||
        keywords.contains('dsh-plugin') ||
        keywords.contains('deepseek-harness');
    final skill = files.containsKey('SKILL.md');
    final deprecated = manifest['deprecated'] is String
        ? manifest['deprecated'] as String
        : null;
    final notices = [
      '这个包没有经过审核。插件及技能脚本以用户账户的权限运行，能读写该账户可访问的文件、联网，并看到交给它的数据。',
      if (deprecated != null) '作者已弃用这个版本：$deprecated',
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
    StoreItem asPlugin() {
      if (!plugin) throw const StoreFormatException('未声明 DeepSeek Harness 插件');
      if (provided == null) {
        throw const StoreFormatException('未安装 DeepSeek Harness 运行环境');
      }
      final peers =
          Map<String, Object?>.from(declaredPeers as Map? ?? const {});
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
      if (!packageEntryCandidates(files['package.json']).any(
          (candidate) => files.containsKey(p.posix.normalize(candidate)))) {
        throw StoreFormatException('$name 找不到入口文件');
      }
      return StoreItem(
        id: id,
        kind: StoreKind.plugin,
        origin: StoreOrigin.npm,
        name: name.length <= 80 ? name : '${name.substring(0, 79)}…',
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
      );
    }

    StoreItem asSkill() {
      if (!skill) throw const StoreFormatException('包根目录没有 SKILL.md');
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
      return StoreItem(
        id: id,
        kind: StoreKind.skill,
        origin: StoreOrigin.npm,
        name: name.length <= 80 ? name : '${name.substring(0, 79)}…',
        version: version,
        description: description,
        author: author,
        notices: notices,
        files: skillFiles,
        packages: [package],
      );
    }

    NpmOption option(StoreItem Function() build) {
      if (identityProblem != null) return (item: null, reason: identityProblem);
      try {
        final item = build();
        StoreItem.parse(item.toJson(), origin: item.origin);
        return (item: item, reason: null);
      } on StoreFormatException catch (error) {
        return (item: null, reason: error.message);
      } on FormatException {
        return (item: null, reason: '软件包的元数据格式无效');
      } on TypeError {
        return (item: null, reason: '软件包的元数据类型无效');
      }
    }

    return (
      name: name,
      requested: requested,
      version: version,
      deprecated: deprecated,
      notices: notices,
      hasSkill: skill,
      isPlugin: plugin,
      options: {
        StoreKind.skill: option(asSkill),
        StoreKind.plugin: option(asPlugin)
      },
      files: files,
    );
  }

  /// The rows of a plugin's own `cordis.patch.yml`, accepted only when each
  /// adds an entry of this package; without one, a single row for it.
  static List<StoreDshRow> _patchRows(
      String name, Uint8List? patch, String id) {
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
            row.keys.any(
                (k) => !const {'id', 'name', 'config', 'inject'}.contains(k))) {
          throw StoreFormatException(
              '$name 的 cordis.patch.yml 除了加入它自己，还有别的改动，不能安装');
        }
        rows.add(StoreDshRow.parse(
            {
              'id': row['id'],
              'package': name,
              if (row['config'] != null)
                'config': jsonDecode(jsonEncode(row['config'])),
              if (row['inject'] != null)
                'inject': jsonDecode(jsonEncode(row['inject'])),
            },
            '$name 的 cordis.patch.yml',
            {name}));
      }
    }
    if (rows.isEmpty) {
      throw StoreFormatException('$name 的 cordis.patch.yml 没有加入任何插件');
    }
    return rows;
  }
}
