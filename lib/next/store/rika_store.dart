import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nipa_harness/nipa_harness.dart' show JsonMap;
import 'package:path/path.dart' as p;

import 'npm_package.dart';
import 'store_fetch.dart';
import 'store_index.dart';

/// An installed item, as the store keeps it.
final class InstalledItem {
  const InstalledItem(this.item, {required this.enabled, required this.at});
  final StoreItem item;
  final bool enabled;
  final DateTime at;

  Map<String, Object?> toJson() => {
        ...item.toJson(),
        'enabled': enabled,
        'installedAt': at.toUtc().toIso8601String(),
      };

  static InstalledItem parse(Map raw) => InstalledItem(
      StoreItem.parse(raw,
          origin:
              raw['origin'] == 'npm' ? StoreOrigin.npm : StoreOrigin.official),
      enabled: raw['enabled'] != false,
      at: DateTime.tryParse(raw['installedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
}

/// What the installed items add to a starting conversation host: a section
/// of instructions naming the skills, the rows DSH loads the plugins by, and
/// the plugins left out (with why) for this runtime.
typedef StoreHostFacts = ({
  String instructions,
  List<Map<String, Object?>> dshPlugins,
  Map<String, String> skipped,
});

/// 梨花's store: the official list (a repository of reviewed skills and
/// plugins, every file pinned by SHA-256) and any npm package someone names,
/// installed under [root]:
///
/// - `skills/<id>/`: a skill's files. She is told each enabled skill's name,
///   description and folder when her conversation host starts.
/// - `plugins/<id>/node_modules/...`: a plugin's packages. The packages the
///   DSH runtime provides are linked in at start (to the runtime it starts
///   with), so the plugin shares DSH's own modules.
/// - `installed.json`: what is installed, and whether it is on.
///
/// Changes take effect when the conversation host next starts.
final class RikaStore {
  RikaStore(
      {required this.root,
      required this.fetch,
      required this.listSources,
      required this.registries,
      this.provided,
      this.cacheFor = const Duration(minutes: 10)});

  final Directory root;
  final StoreFetch fetch;

  /// Where the official list is: folders holding `index.json` and the files
  /// it names (the repository's raw address, a mirror; a local checkout in
  /// development), in the order tried.
  final List<Uri> Function() listSources;

  /// npm registry addresses, in the order tried.
  final Future<List<String>> Function() registries;

  /// The packages the installed DSH runtime provides (null: none installed):
  /// what a plugin from npm may depend on.
  final Future<Set<String>?> Function()? provided;
  final Duration cacheFor;

  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;

  StoreIndex? _list;
  DateTime? _listAt;
  String? _listProblem;
  Future<void> _operations = Future.value();

  Directory get _skills => Directory(p.join(root.path, 'skills'));
  Directory get _plugins => Directory(p.join(root.path, 'plugins'));
  File get _installedFile => File(p.join(root.path, 'installed.json'));
  File get _listCache => File(p.join(root.path, 'index.json'));

  List<JsonMap>? get loadedAtLastStart => _loadedAtLastStart;
  List<JsonMap>? _loadedAtLastStart;

  /// The extensions the last host start left out, and why.
  Map<String, String> get notLoaded => Map.unmodifiable(_notLoaded);
  Map<String, String> _notLoaded = const {};

  /// Why the official list could not be read last time (shown with the copy
  /// kept from before, if any).
  String? get listProblem => _listProblem;
  String get listVersionSource =>
      _listProblem == null ? 'officialIndex' : 'cachedOfficialIndex';

  /// The official list: fetched at most every [cacheFor], else the copy
  /// from the last fetch.
  Future<StoreIndex> officialList({bool refresh = false}) async {
    final now = DateTime.now();
    if (!refresh &&
        _list != null &&
        _listAt != null &&
        now.difference(_listAt!) < cacheFor) {
      return _list!;
    }
    try {
      final text = await fetch.text(
          [for (final base in listSources()) base.resolve('index.json')],
          maxBytes: 4 << 20,
          headers: {'accept': 'application/json'});
      final list = StoreIndex.parse(text);
      _list = list;
      _listAt = now;
      _listProblem = null;
      await root.create(recursive: true);
      await _write(_listCache, text);
      return list;
    } on Object catch (error) {
      _listProblem =
          error is StoreFetchException || error is StoreFormatException
              ? '$error'
              : '官方列表读取失败：$error';
      if (_list != null) return _list!;
      if (await _listCache.exists()) {
        try {
          return _list = StoreIndex.parse(await _listCache.readAsString());
        } on StoreFormatException {
          // The kept copy is no better; say why the fetch failed.
        }
      }
      rethrow;
    }
  }

  /// The README of an official item, held to its SHA-256.
  Future<String?> readme(StoreItem item) async {
    final readme = item.readme;
    if (readme == null) return null;
    return utf8.decode(await fetch.bytes(
        [for (final base in listSources()) base.resolve(readme.url)],
        sha256Hex: readme.sha256, size: readme.bytes, maxBytes: maxFileBytes));
  }

  /// What is installed. A record this version cannot read is left out (and
  /// kept, see [unreadable]), so one bad entry does not hide the rest.
  Future<List<InstalledItem>> installed() async {
    final items = <InstalledItem>[];
    final unreadable = <String, String>{};
    for (final raw in await _records()) {
      try {
        items.add(InstalledItem.parse(raw));
      } on Object catch (error) {
        unreadable['${raw['id']}'] = '$error';
      }
    }
    _unreadable = unreadable;
    return items;
  }

  /// Installed records that could not be read, and why; removable.
  Map<String, String> get unreadable => Map.unmodifiable(_unreadable);
  Map<String, String> _unreadable = const {};

  Future<List<Map>> _records() async {
    if (!await _installedFile.exists()) return const [];
    try {
      final raw = jsonDecode(await _installedFile.readAsString());
      if (raw is! Map || raw['items'] is! List) return const [];
      return [
        for (final item in raw['items'] as List)
          if (item is Map) item
      ];
    } on FormatException {
      return const [];
    }
  }

  /// Saves [items], keeping records nobody could read unless [dropping].
  Future<void> _save(List<InstalledItem> items, {String? dropping}) async {
    final kept = {for (final i in items) i.item.id};
    final unread = [
      for (final raw in await _records())
        if (_unreadable.containsKey('${raw['id']}') &&
            !kept.contains(raw['id']) &&
            raw['id'] != dropping)
          raw
    ];
    await root.create(recursive: true);
    await _write(
        _installedFile,
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'items': [for (final item in items) item.toJson(), ...unread]
        }));
  }

  Future<T> _locked<T>(Future<T> Function() action) async {
    await root.create(recursive: true);
    final lock = await File(p.join(root.path, 'installed.lock'))
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.blockingExclusive);
      return await action();
    } finally {
      await lock.close();
    }
  }

  static Future<void> _write(File file, String text) async {
    final staging = File('${file.path}.pending');
    await staging.writeAsString(text, flush: true);
    await staging.rename(file.path);
  }

  /// One change of what is installed at a time: in this process by a queue,
  /// across processes (a headless host and its --store-install-npm) by an
  /// exclusive lock on `installed.lock`.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _operations.then((_) => _locked(action));
    _operations = result.then<void>((_) {}, onError: (_, __) {});
    return result;
  }

  /// Installs (or updates to) the official item [id] at [version], the one
  /// whose notices the person read; a list that moved on is [StoreChanged].
  Future<InstalledItem> installOfficial(String id, {required String version}) =>
      _serial(() async {
        final list = await officialList(refresh: true);
        final item = list.items.where((i) => i.id == id).firstOrNull ??
            (throw StoreFormatException('官方列表里没有 $id'));
        if (item.version != version) {
          throw StoreChanged('「${item.name}」刚更新到 ${item.version}，请看过新版的说明后再安装');
        }
        return _install(item, null);
      });

  Future<NpmResolution> resolveNpm(String spec, {String? exactVersion}) async {
    final (name, _) = NpmPackages.parseSpec(spec);
    final items = await installed();
    final id = items
            .where((entry) => entry.item.npmPackage == name)
            .firstOrNull
            ?.item
            .id ??
        NpmPackages.idFor(name);
    final problem = _identityProblem(id, StoreOrigin.npm, name, items);
    return NpmPackages(fetch, registries: await registries()).resolve(spec,
        provided: await provided?.call(),
        exactVersion: exactVersion,
        id: id,
        identityProblem: problem);
  }

  Future<InstalledItem> installNpm(String name,
          {required String version, required StoreKind kind}) =>
      _serial(() async {
        final resolution = await resolveNpm(name, exactVersion: version);
        final choice = resolution.options[kind]!;
        final item =
            choice.item ?? (throw StoreFormatException(choice.reason!));
        return _install(item, resolution.files);
      });

  String? _identityProblem(String id, StoreOrigin origin, String? npmPackage,
      List<InstalledItem> items) {
    if (_unreadable.containsKey(id) ||
        items.any((entry) =>
            entry.item.id == id &&
            (entry.item.origin != origin ||
                entry.item.npmPackage != npmPackage))) {
      return '条目 ID $id 已由其他或不可读取的条目占用';
    }
    return null;
  }

  Future<InstalledItem> _install(
      StoreItem item, Map<String, Uint8List>? npmFiles) async {
    // What is saved must read back: checked before anything is written.
    StoreItem.parse(item.toJson(), origin: item.origin);
    final items = await installed();
    final problem =
        _identityProblem(item.id, item.origin, item.npmPackage, items);
    if (problem != null) throw StoreChanged(problem);
    final before = items.where((entry) => entry.item.id == item.id).firstOrNull;
    final folder = Directory(p.join(
        item.kind == StoreKind.skill ? _skills.path : _plugins.path, item.id));
    final staging = Directory('${folder.path}.pending');
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      if (item.kind == StoreKind.skill) {
        if (npmFiles != null) {
          await writePackageFiles({
            for (final f in item.files) f.path: npmFiles[f.path]!,
          }, staging);
        } else {
          for (final file in item.files) {
            final bytes = await fetch.bytes(
                [for (final base in listSources()) base.resolve(file.url)],
                sha256Hex: file.sha256,
                size: file.bytes,
                maxBytes: maxFileBytes);
            await writePackageFiles(
                {file.path: Uint8List.fromList(bytes)}, staging);
          }
        }
      } else {
        final registries = await this.registries();
        for (final package in item.packages) {
          final files = npmFiles ??
              readPackageTarball(await fetch.bytes(
                  [for (final r in registries) Uri.parse('$r/${package.url}')],
                  sha256Hex: package.sha256,
                  integrity: package.integrity,
                  size: package.bytes,
                  maxBytes: maxPackageBytes));
          await writePackageFiles(files,
              Directory(p.joinAll([staging.path, ...package.path.split('/')])));
        }
        for (final row in item.dsh) {
          final package =
              item.packages.firstWhere((pkg) => pkg.name == row.package);
          await _entry(
              Directory(p.joinAll([staging.path, ...package.path.split('/')])));
        }
      }
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    final installed_ = InstalledItem(item,
        enabled: before?.enabled ?? true, at: DateTime.now().toUtc());
    // The old files stay until the record of the new ones is saved; if it
    // cannot be, the old version is put back as it was.
    final old = Directory('${folder.path}.old');
    if (await old.exists()) await old.delete(recursive: true);
    final hadOld = await folder.exists();
    if (hadOld) await folder.rename(old.path);
    try {
      await staging.rename(folder.path);
      await _save([
        for (final i in items)
          if (i.item.id != item.id) i,
        installed_,
      ]);
    } catch (_) {
      if (await folder.exists()) await folder.delete(recursive: true);
      if (hadOld) await old.rename(folder.path);
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    // Installed: the old copy going is housekeeping, retried next time.
    if (hadOld) {
      await old
          .delete(recursive: true)
          .then<void>((_) {}, onError: (Object _) {});
    }
    if (before != null && before.item.kind != item.kind) {
      final previous = Directory(p.join(
          before.item.kind == StoreKind.skill ? _skills.path : _plugins.path,
          item.id));
      if (await previous.exists()) {
        await previous
            .delete(recursive: true)
            .then<void>((_) {}, onError: (Object _) {});
      }
    }
    _changes.add(null);
    return installed_;
  }

  Future<void> remove(String id) => _serial(() async {
        if (!storeId(id)) throw StoreFormatException('没有安装 $id');
        final items = await installed();
        if (!items.any((i) => i.item.id == id) &&
            !_unreadable.containsKey(id)) {
          throw StoreFormatException('没有安装 $id');
        }
        await _save([
          for (final i in items)
            if (i.item.id != id) i
        ], dropping: id);
        _unreadable = {..._unreadable}..remove(id);
        for (final kind in [_skills, _plugins]) {
          final folder = Directory(p.join(kind.path, id));
          if (await folder.exists()) await folder.delete(recursive: true);
        }
        _changes.add(null);
      });

  Future<InstalledItem> setEnabled(String id, bool enabled) =>
      _serial(() async {
        final items = await installed();
        final item = items.where((i) => i.item.id == id).firstOrNull ??
            (throw StoreFormatException('没有安装 $id'));
        final changed = InstalledItem(item.item, enabled: enabled, at: item.at);
        await _save([
          for (final i in items) i.item.id == id ? changed : i,
        ]);
        _changes.add(null);
        return changed;
      });

  /// The file a package's DSH plugin is imported from: `exports['.']`, then
  /// `main`, then `index.js`, always inside the package.
  static Future<File> _entry(Directory package) async {
    final manifest = File(p.join(package.path, 'package.json'));
    final candidates = packageEntryCandidates(
        await manifest.exists() ? await manifest.readAsBytes() : null);
    for (final candidate in candidates) {
      final file = File(p.normalize(p.join(package.path, candidate)));
      if (p.isWithin(package.path, file.path) && await file.exists()) {
        return file;
      }
    }
    throw StoreFormatException('${p.basename(package.path)} 找不到入口文件');
  }

  /// What the enabled items add to a host starting now: [runtimeModules] is
  /// the `node_modules` of the DSH runtime it starts with (null: Codex, which
  /// loads no plugins).
  ///
  /// Not queued behind installs: a host starting never waits on a download.
  Future<StoreHostFacts> hostFacts({Directory? runtimeModules}) => (() async {
        final items = [
          for (final i in await installed())
            if (i.enabled) i.item
        ];
        final skills = <StoreItem>[];
        final loaded = <JsonMap>[];
        final rows = <Map<String, Object?>>[];
        final skipped = <String, String>{};
        for (final item in items) {
          if (item.kind == StoreKind.skill) {
            if (!await File(p.join(_skills.path, item.id, 'SKILL.md'))
                .exists()) {
              skipped[item.id] = '找不到 SKILL.md';
              continue;
            }
            skills.add(item);
            loaded.add(_startupItem(item));
            continue;
          }
          if (runtimeModules == null) {
            skipped[item.id] = '插件只在 DeepSeek Harness 运行环境下加载';
            continue;
          }
          try {
            rows.addAll(await _pluginRows(item, runtimeModules));
            loaded.add(_startupItem(item));
          } on Object catch (error) {
            skipped[item.id] = '$error';
          }
        }
        _notLoaded = skipped;
        _loadedAtLastStart = List.unmodifiable(loaded);
        return (
          instructions: skills.isEmpty ? '' : _skillsSection(skills),
          dshPlugins: rows,
          skipped: skipped,
        );
      })();

  JsonMap _startupItem(StoreItem item) => Map.unmodifiable({
        'id': item.id,
        'version': item.version,
        'kind': item.kind.name,
      });

  Future<List<Map<String, Object?>>> _pluginRows(
      StoreItem item, Directory runtimeModules) async {
    final folder = Directory(p.join(_plugins.path, item.id));
    final modules = Directory(p.join(folder.path, 'node_modules'));
    for (final peer in item.peers) {
      final target =
          Directory(p.joinAll([runtimeModules.path, ...peer.split('/')]));
      if (!await target.exists()) {
        throw StoreFormatException('运行环境里没有它需要的 $peer');
      }
      final link = Link(p.joinAll([modules.path, ...peer.split('/')]));
      if (await link.exists()) {
        if (await link.target() == target.path) continue;
        await link.delete();
      } else if (await FileSystemEntity.type(link.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StoreFormatException('插件自带的 $peer 与运行环境的冲突');
      }
      await link.parent.create(recursive: true);
      await link.create(target.path);
    }
    return [
      for (final row in item.dsh)
        {
          'id': row.id,
          'name': (await _entry(Directory(p.joinAll([
            folder.path,
            ...item.packages
                .firstWhere((pkg) => pkg.name == row.package)
                .path
                .split('/')
          ]))))
              .absolute
              .path,
          if (row.config != null) 'config': row.config,
          if (row.inject != null) 'inject': row.inject,
        }
    ];
  }

  String _skillsSection(List<StoreItem> skills) {
    final lines = [
      '## 已安装的扩展技能',
      '',
      '这些技能来自梨花的商店。各自的目录和 SKILL.md 路径列在下方。'
          '未审核技能来自 npm，其脚本以用户账户权限运行。',
      '',
    ];
    for (final skill in skills) {
      final folder = p.join(_skills.path, skill.id);
      lines.add('- ${skill.name}（${skill.reviewed ? '官方' : '未审核'}）：'
          '${skill.description.replaceAll('\n', ' ')} 文件夹：`$folder`；'
          '说明：`${p.join(folder, 'SKILL.md')}`');
    }
    return lines.join('\n');
  }

  Future<void> close() => _changes.close();
}
