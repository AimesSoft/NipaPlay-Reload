import 'dart:convert';

/// What 梨花's store holds: skills (instructions and scripts she runs) and
/// plugins (DeepSeek Harness npm packages, such as model providers).
enum StoreKind { skill, plugin }

/// Where an item came from: the official list, reviewed and pinned, or an
/// npm package someone named, not reviewed by anyone.
enum StoreOrigin { official, npm }

final _id = RegExp(r'^[a-z0-9][a-z0-9-]{0,47}$');
final _hex = RegExp(r'^[0-9a-f]{64}$');
final _path = RegExp(r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$');
final _npmName =
    RegExp(r'^(@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$');
final _semver = RegExp(r'^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$');

const storeCategories = {'bt', 'danmaku', 'model', 'tool'};

/// At most this many files in a skill, each at most [maxFileBytes].
const maxSkillFiles = 64;
const maxFileBytes = 1 << 20;

/// A plugin's packages together: npm tarballs of DSH plugins are small.
const maxPackageBytes = 32 << 20;

final class StoreFormatException implements Exception {
  const StoreFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

Never _bad(String message) => throw StoreFormatException(message);

bool storeId(String value) => _id.hasMatch(value);
bool npmName(String value) => value.length <= 214 && _npmName.hasMatch(value);

/// A relative path without `.`/`..` segments or anything a file system
/// might read otherwise.
bool safeRelativePath(String value) =>
    value.length <= 200 &&
    _path.hasMatch(value) &&
    !value.split('/').any((s) => s == '.' || s == '..');

/// A file pinned by its SHA-256: [url] is relative to where the list is.
final class StoreFile {
  const StoreFile(
      {required this.path,
      required this.url,
      required this.sha256,
      required this.bytes});

  final String path, url, sha256;
  final int bytes;

  static StoreFile parse(Object? raw, String where, {bool needsPath = true}) {
    if (raw is! Map) _bad('$where 应为对象');
    final path = raw['path'], url = raw['url'];
    final sha = raw['sha256'], bytes = raw['bytes'];
    if (needsPath && (path is! String || !safeRelativePath(path))) {
      _bad('$where 的 path 不安全');
    }
    if (url is! String || !safeRelativePath(url)) _bad('$where 的 url 不安全');
    if (sha is! String || !_hex.hasMatch(sha)) _bad('$where 的 sha256 无效');
    if (bytes is! int || bytes < 0 || bytes > maxFileBytes) {
      _bad('$where 的 bytes 无效');
    }
    return StoreFile(
        path: needsPath ? path as String : '',
        url: url,
        sha256: sha,
        bytes: bytes);
  }

  Map<String, Object?> toJson() =>
      {'path': path, 'url': url, 'sha256': sha256, 'bytes': bytes};
}

/// One npm tarball of a plugin, unpacked at [path] (`node_modules/<name>`).
/// Pinned by [sha256] (the official list) or by npm's [integrity] (`sha512-`
/// of a package someone named).
final class StorePackage {
  const StorePackage(
      {required this.path,
      required this.name,
      required this.version,
      required this.url,
      this.sha256,
      this.integrity,
      this.bytes});

  final String path, name, version, url;
  final String? sha256, integrity;
  final int? bytes;

  static StorePackage parse(Object? raw, String where) {
    if (raw is! Map) _bad('$where 应为对象');
    final name = raw['name'], version = raw['version'];
    final path = raw['path'], url = raw['url'];
    final sha = raw['sha256'], integrity = raw['integrity'];
    final bytes = raw['bytes'];
    if (name is! String || !npmName(name)) _bad('$where 的 name 无效');
    if (version is! String || !_semver.hasMatch(version)) {
      _bad('$where 的 version 无效');
    }
    if (path != 'node_modules/$name') _bad('$where 的 path 应为 node_modules/$name');
    if (url is! String ||
        !RegExp(r'^[A-Za-z0-9@._/%-]+\.tgz$').hasMatch(url) ||
        url.split('/').contains('..')) {
      _bad('$where 的 url 无效');
    }
    if (sha != null && (sha is! String || !_hex.hasMatch(sha))) {
      _bad('$where 的 sha256 无效');
    }
    if (integrity != null &&
        (integrity is! String || !integrity.startsWith('sha512-'))) {
      _bad('$where 的 integrity 无效');
    }
    if (sha == null && integrity == null) _bad('$where 没有校验值');
    if (bytes != null &&
        (bytes is! int || bytes <= 0 || bytes > maxPackageBytes)) {
      _bad('$where 的 bytes 无效');
    }
    return StorePackage(
        path: path as String,
        name: name,
        version: version,
        url: url,
        sha256: sha as String?,
        integrity: integrity as String?,
        bytes: bytes as int?);
  }

  Map<String, Object?> toJson() => {
        'path': path,
        'name': name,
        'version': version,
        'url': url,
        if (sha256 != null) 'sha256': sha256,
        if (integrity != null) 'integrity': integrity,
        if (bytes != null) 'bytes': bytes,
      };
}

/// A row a plugin adds to DSH's profile: [package]'s entry, as plugin [id].
final class StoreDshRow {
  const StoreDshRow(
      {required this.id, required this.package, this.config, this.inject});
  final String id, package;
  final Map<String, Object?>? config;
  final List<String>? inject;

  static StoreDshRow parse(Object? raw, String where, Set<String> packages) {
    if (raw is! Map) _bad('$where 应为对象');
    final id = raw['id'], package = raw['package'];
    final config = raw['config'], inject = raw['inject'];
    if (id is! String || !RegExp(r'^[a-z0-9][a-z0-9._-]{0,63}$').hasMatch(id)) {
      _bad('$where 的 id 无效');
    }
    if (id.startsWith('nipa-')) _bad('$where 的 id 不能以 nipa- 开头');
    if (package is! String || !packages.contains(package)) {
      _bad('$where 的 package 不在这个插件的包里');
    }
    if (config != null && config is! Map) _bad('$where 的 config 应为对象');
    if (inject != null &&
        (inject is! List || inject.any((e) => e is! String))) {
      _bad('$where 的 inject 应为字符串列表');
    }
    for (final key in raw.keys) {
      if (!const {'id', 'package', 'config', 'inject'}.contains(key)) {
        _bad('$where 有未知字段 $key');
      }
    }
    return StoreDshRow(
        id: id,
        package: package,
        config: config == null ? null : Map<String, Object?>.from(config),
        inject: (inject as List?)?.cast<String>());
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'package': package,
        if (config != null) 'config': config,
        if (inject != null) 'inject': inject,
      };
}

/// One thing the store offers or has installed.
final class StoreItem {
  const StoreItem({
    required this.id,
    required this.kind,
    required this.origin,
    required this.name,
    required this.version,
    required this.description,
    this.author,
    this.category = 'tool',
    this.minHostVersion,
    this.notices = const [],
    this.readme,
    this.files = const [],
    this.packages = const [],
    this.peers = const [],
    this.dsh = const [],
  });

  final String id, name, version, description, category;
  final StoreKind kind;
  final StoreOrigin origin;
  final String? author, minHostVersion;

  /// Said to the person before installing (risks, terms of service).
  final List<String> notices;
  final StoreFile? readme;

  /// A skill's files.
  final List<StoreFile> files;

  /// A plugin's packages, the packages the DSH runtime provides for them,
  /// and the rows it adds to DSH's profile.
  final List<StorePackage> packages;
  final List<String> peers;
  final List<StoreDshRow> dsh;

  bool get reviewed => origin == StoreOrigin.official;

  static StoreItem parse(Object? raw, {required StoreOrigin origin}) {
    if (raw is! Map) _bad('条目应为对象');
    final id = raw['id'];
    if (id is! String || !storeId(id)) _bad('条目 id 无效：$id');
    final where = '条目 $id';
    final kind = switch (raw['kind']) {
      'skill' => StoreKind.skill,
      'plugin' => StoreKind.plugin,
      _ => _bad('$where 的 kind 无效'),
    };
    String text(String key, {int max = 200, bool optional = false}) {
      final value = raw[key];
      if (value == null && optional) return '';
      if (value is! String || value.trim().isEmpty || value.length > max) {
        _bad('$where 的 $key 无效');
      }
      return value;
    }

    final version = text('version', max: 64);
    if (!_semver.hasMatch(version)) _bad('$where 的 version 无效');
    final category = raw['category'] ?? 'tool';
    if (!storeCategories.contains(category)) _bad('$where 的 category 无效');
    final notices = raw['notices'] ?? const [];
    if (notices is! List ||
        notices.length > 8 ||
        notices.any((n) => n is! String || n.length > 600)) {
      _bad('$where 的 notices 无效');
    }
    final files = <StoreFile>[];
    final packages = <StorePackage>[];
    final peers = <String>[];
    final dsh = <StoreDshRow>[];
    if (kind == StoreKind.skill) {
      final raws = raw['files'];
      if (raws is! List || raws.isEmpty || raws.length > maxSkillFiles) {
        _bad('$where 的 files 无效');
      }
      for (final (i, f) in raws.indexed) {
        files.add(StoreFile.parse(f, '$where 的第 ${i + 1} 个文件'));
      }
      if (!files.any((f) => f.path == 'SKILL.md')) _bad('$where 缺少 SKILL.md');
      if (files.map((f) => f.path.toLowerCase()).toSet().length !=
          files.length) {
        _bad('$where 有重名文件');
      }
      // A skill from npm keeps the package it came in.
      if (raw['packages'] case final List raws when raws.length == 1) {
        packages.add(StorePackage.parse(raws.single, '$where 的包'));
      }
    } else {
      final raws = raw['packages'];
      if (raws is! List || raws.isEmpty || raws.length > 64) {
        _bad('$where 的 packages 无效');
      }
      for (final (i, p) in raws.indexed) {
        packages.add(StorePackage.parse(p, '$where 的第 ${i + 1} 个包'));
      }
      if (packages.map((p) => p.name).toSet().length != packages.length) {
        _bad('$where 有重复的包');
      }
      final rawPeers = raw['peers'] ?? const [];
      if (rawPeers is! List ||
          rawPeers.any((p) => p is! String || !npmName(p))) {
        _bad('$where 的 peers 无效');
      }
      peers.addAll(rawPeers.cast<String>());
      final rows = raw['dsh'];
      if (rows is! List || rows.isEmpty || rows.length > 8) {
        _bad('$where 的 dsh 无效');
      }
      final names = {for (final p in packages) p.name};
      for (final (i, r) in rows.indexed) {
        dsh.add(StoreDshRow.parse(r, '$where 的第 ${i + 1} 行', names));
      }
    }
    final minHost = raw['minHostVersion'];
    if (minHost != null && (minHost is! String || minHost.length > 64)) {
      _bad('$where 的 minHostVersion 无效');
    }
    final author = raw['author'];
    if (author != null && (author is! String || author.length > 120)) {
      _bad('$where 的 author 无效');
    }
    return StoreItem(
      id: id,
      kind: kind,
      origin: origin,
      name: text('name', max: 80),
      version: version,
      description: text('description', max: 400),
      author: author as String?,
      category: category as String,
      minHostVersion: minHost as String?,
      notices: notices.cast<String>(),
      readme: raw['readme'] == null
          ? null
          : StoreFile.parse(raw['readme'], '$where 的 readme',
              needsPath: false),
      files: files,
      packages: packages,
      peers: peers,
      dsh: dsh,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'origin': origin.name,
        'name': name,
        'version': version,
        'description': description,
        if (author != null) 'author': author,
        'category': category,
        if (minHostVersion != null) 'minHostVersion': minHostVersion,
        'notices': notices,
        if (readme != null)
          'readme': {
            'url': readme!.url,
            'sha256': readme!.sha256,
            'bytes': readme!.bytes
          },
        if (kind == StoreKind.skill) 'files': [for (final f in files) f.toJson()],
        if (packages.isNotEmpty)
          'packages': [for (final p in packages) p.toJson()],
        if (kind == StoreKind.plugin) ...{
          'peers': peers,
          'dsh': [for (final r in dsh) r.toJson()],
        },
      };
}

/// The official list (`index.json` of the store repository).
final class StoreIndex {
  const StoreIndex(this.items);
  final List<StoreItem> items;

  static StoreIndex parse(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      _bad('官方列表不是有效的 JSON');
    }
    if (raw is! Map) _bad('官方列表格式无效');
    if (raw['version'] != 1) {
      _bad('官方列表的格式版本（${raw['version']}）比这个 NipaPlay 新，请更新 NipaPlay');
    }
    final items = raw['items'];
    if (items is! List) _bad('官方列表缺少 items');
    final parsed = [
      for (final item in items)
        StoreItem.parse(item, origin: StoreOrigin.official)
    ];
    if (parsed.map((i) => i.id).toSet().length != parsed.length) {
      _bad('官方列表有重复的 id');
    }
    return StoreIndex(parsed);
  }
}
