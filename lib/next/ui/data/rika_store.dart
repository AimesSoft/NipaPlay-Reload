import 'package:nipa_harness/nipa_harness.dart';

import 'gui_calls.dart';

/// One item of 梨花's store, listed or installed.
final class UiStoreItem {
  const UiStoreItem({
    required this.id,
    required this.kind,
    required this.name,
    required this.version,
    required this.description,
    required this.category,
    required this.reviewed,
    this.author,
    this.notices = const [],
    this.installedVersion,
    this.enabled,
    this.versionDiffers = false,
    this.versionSource,
    this.notLoaded,
  });

  final String id, kind, name, version, description, category;
  final bool reviewed;
  final String? author;
  final List<String> notices;

  /// Null when not installed.
  final String? installedVersion;
  final bool? enabled;
  final bool versionDiffers;
  final String? versionSource;

  /// Why the last start of 梨花 left this plugin out.
  final String? notLoaded;

  bool get installed => installedVersion != null;
  bool get plugin => kind == 'plugin';

  static UiStoreItem from(Map raw,
          {required bool installed, String? notLoaded}) =>
      UiStoreItem(
        id: raw['id'] as String,
        kind: raw['kind'] as String,
        name: raw['name'] as String,
        version: raw['version'] as String,
        description: raw['description'] as String? ?? '',
        category: raw['category'] as String? ?? 'tool',
        reviewed: raw['reviewed'] == true,
        author: raw['author'] as String?,
        notices: [
          for (final n in raw['notices'] as List? ?? const [])
            if (n is String) n
        ],
        installedVersion: installed
            ? raw['version'] as String
            : raw['installedVersion'] as String?,
        enabled: raw['enabled'] as bool?,
        versionDiffers: raw['versionDiffers'] == true,
        versionSource: raw['versionSource'] as String?,
        notLoaded: notLoaded,
      );
}

/// The store as the interface sees it: the official list (with what of it
/// is installed) and what came from npm.
final class UiStore {
  const UiStore(
      {required this.official, required this.fromNpm, this.listProblem});
  final List<UiStoreItem> official;
  final List<UiStoreItem> fromNpm;
  final String? listProblem;
}

const storeCategoryNames = {
  'bt': 'BT 来源',
  'danmaku': '弹幕',
  'model': '模型与订阅',
  'tool': '工具',
};

final class NextRikaStore {
  NextRikaStore(this.calls);
  final GuiCalls calls;

  Future<UiStore> read({bool refresh = false}) async {
    final r = await calls.call('store.list', {if (refresh) 'refresh': true});
    final notLoaded = {
      for (final e in ((r['notLoadedAtLastStart'] as Map?) ?? const {}).entries)
        '${e.key}': '${e.value}'
    };
    final official = [
      for (final raw in (r['official'] as List).cast<Map>())
        UiStoreItem.from(raw, installed: false, notLoaded: notLoaded[raw['id']])
    ];
    final listed = {for (final i in official) i.id};
    return UiStore(
      official: official,
      fromNpm: [
        for (final raw in (r['installed'] as List).cast<Map>())
          if (raw['reviewed'] != true || !listed.contains(raw['id']))
            UiStoreItem.from(raw,
                installed: true, notLoaded: notLoaded[raw['id']])
      ],
      listProblem: r['listProblem'] as String?,
    );
  }

  Future<({String version, String? text})> readme(String id) async {
    final result = await calls.call('store.readme', {'id': id});
    return (
      version: result['version'] as String,
      text: result['readme'] as String?
    );
  }

  Future<JsonMap> resolveNpm(String spec) =>
      calls.call('store.resolve_npm', {'npm': spec});

  /// From the list ([id] at the [version] whose notices were shown), or the
  /// npm package [npm].
  Future<JsonMap> install(
          {String? id, String? version, String? npm, String? kind}) =>
      calls.call('store.install', {
        if (id != null) 'id': id,
        if (version != null) 'version': version,
        if (npm != null) 'npm': npm,
        if (kind != null) 'kind': kind,
      });

  Future<void> setEnabled(String id, bool enabled) =>
      calls.call('store.enable', {'id': id, 'enabled': enabled});

  Future<void> remove(String id) => calls.call('store.remove', {'id': id});

  /// Restarts 梨花 so what changed takes effect.
  Future<JsonMap> apply() => calls.call('store.apply', {});
}
