import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import 'gui_calls.dart';

/// Space and caches (`storage.status`, `cache.plan` / `cache.prune`), and
/// newer versions (`app.update.*`).
final class NextUpkeep {
  NextUpkeep(this.calls);
  final GuiCalls calls;

  /// What NipaPlay keeps on this computer, and the room left there.
  Future<UiSpace> space() async {
    final r = await calls.call('storage.status', {});
    Map? dir(String role) => (r['directories'] as List)
        .cast<Map>()
        .where((d) => d['role'] == role)
        .firstOrNull;
    final app = dir('app'), downloads = dir('downloads');
    final appBytes = (app?['bytes'] as num?)?.toInt();
    final downloadBytes = (downloads?['bytes'] as num?)?.toInt();
    // The downloads folder sits inside NipaPlay's own: not counted twice.
    final inside = app?['path'] is String &&
        downloads?['path'] is String &&
        p.isWithin(app!['path'] as String, downloads!['path'] as String);
    final volume = ((r['volumes'] as List?) ?? const []).cast<Map>().firstOrNull;
    return UiSpace(
      app: appBytes == null
          ? null
          : inside
              ? appBytes - (downloadBytes ?? 0)
              : appBytes,
      downloads: downloadBytes,
      free: (volume?['availableBytes'] as num?)?.toInt(),
      total: (volume?['totalBytes'] as num?)?.toInt(),
    );
  }

  /// Each kind of cache: what clearing it frees, and what it keeps.
  Future<List<UiCacheKind>> caches() async {
    final kinds = <UiCacheKind>[];
    for (final (id, title, members) in UiCacheKind.all) {
      final plan = await calls.call('cache.plan', {'kinds': members});
      final retained = (plan['retained'] as List).cast<Map>();
      kinds.add(UiCacheKind(
        id: id,
        title: title,
        bytes: (plan['reclaimableBytes'] as num?)?.toInt() ?? 0,
        kept: retained.fold<int>(
            0, (n, e) => n + ((e['bytes'] as num?)?.toInt() ?? 0)),
      ));
    }
    return kinds;
  }

  /// Clears what can be fetched again of [kindId]; the bytes freed.
  Future<int> clear(String kindId) async {
    final members =
        UiCacheKind.all.firstWhere((k) => k.$1 == kindId).$3;
    final plan = await calls.call('cache.plan', {'kinds': members});
    final r = await calls.call('cache.prune', {'planId': plan['planId']});
    return (r['removedBytes'] as num?)?.toInt() ?? 0;
  }

  /// Looks for a newer version now.
  Future<UiUpdateCheck> checkUpdate() async =>
      UiUpdateCheck.from(await calls.call('app.update.check', {}));

  /// The last look, this time NipaPlay runs; null before any.
  Future<UiUpdateCheck?> lastUpdate() async {
    final r = await calls.call('app.update.status', {});
    return r['result'] is Map
        ? UiUpdateCheck.from(Map<String, Object?>.from(r['result'] as Map))
        : null;
  }

  /// The release page of the version found.
  Future<void> openUpdate() => calls.call('app.update.open', {});
}

final class UiSpace {
  const UiSpace({this.app, this.downloads, this.free, this.total});

  /// Bytes NipaPlay's own folder holds (caches included, downloads not).
  final int? app;
  final int? downloads;
  final int? free;
  final int? total;
}

final class UiCacheKind {
  const UiCacheKind(
      {required this.id, required this.title, this.bytes = 0, this.kept = 0});
  final String id;
  final String title;

  /// What clearing frees.
  final int bytes;

  /// Unique copies it keeps (imports, pictures it cannot fetch again).
  final int kept;

  /// The page's kinds and the caches they clear together.
  static const all = [
    ('images', '图片', ['images', 'nextArtwork']),
    ('danmaku', '弹幕', ['classicDanmaku', 'nextDanmaku']),
    ('thumbnails', '缩略图', ['thumbnails', 'timeline']),
  ];
}

final class UiUpdateCheck {
  const UiUpdateCheck(
      {this.current, this.latest, this.newer, this.page = false, this.failed = false});
  final String? current;
  final String? latest;

  /// Null when the check failed.
  final bool? newer;

  /// Its release page can be opened.
  final bool page;
  final bool failed;

  factory UiUpdateCheck.from(JsonMap r) => UiUpdateCheck(
        current: r['currentVersion'] as String?,
        latest: r['latestVersion'] as String?,
        newer: r['hasUpdate'] as bool?,
        page: r['publicReleaseUrl'] != null,
        failed: r['error'] != null,
      );
}

/// Plugins: those installed (`plugins.list`), the market (`plugins.market`),
/// and what is done with them.
final class NextPlugins {
  NextPlugins(this.calls);
  final GuiCalls calls;

  Future<List<UiPlugin>> installed() async => [
        for (final p in ((await calls.call('plugins.list', {}))['plugins']
                as List)
            .cast<Map>())
          UiPlugin.from(p, installed: true)
      ];

  /// The market's plugins, with the installed ones that have a newer version.
  Future<UiMarket> market({bool refresh = false}) async {
    final r = await calls.call('plugins.market', {if (refresh) 'refresh': true});
    final updates = <String, String>{
      for (final e in ((r['updates'] as Map?) ?? const {}).entries)
        if (e.value != null) '${e.key}': '${e.value}'
    };
    return UiMarket(
      plugins: [
        for (final p in (r['plugins'] as List).cast<Map>())
          UiPlugin.from(p, installed: false)
      ],
      updates: updates,
    );
  }

  Future<void> setEnabled(String id, bool enabled) =>
      calls.call('plugins.set_enabled', {'id': id, 'enabled': enabled});

  /// From the market (also an update), or a .js file on this computer.
  Future<void> install({String? remoteId, String? path, String? updating}) =>
      calls.call('plugins.install', {
        if (remoteId != null) 'remoteId': remoteId,
        if (path != null) 'path': path,
        if (updating != null) 'updateForId': updating,
      });

  Future<void> delete(String id) => calls.call('plugins.delete', {'id': id});

  /// One of the plugin's own actions (`plugins.invoke`); what it answered.
  Future<JsonMap> invoke(String id, String actionId) =>
      calls.call('plugins.invoke', {'id': id, 'actionId': actionId});
}

final class UiPlugin {
  const UiPlugin({
    required this.id,
    required this.name,
    this.version,
    this.description,
    this.builtin = false,
    this.enabled = false,
    this.loaded = false,
    this.error,
    this.installed = false,
    this.actions = const [],
  });
  final String id;
  final String name;
  final String? version;
  final String? description;
  final bool builtin;
  final bool enabled;
  final bool loaded;
  final String? error;
  final bool installed;

  /// What the plugin itself offers to do.
  final List<UiPluginAction> actions;

  factory UiPlugin.from(Map p, {required bool installed}) => UiPlugin(
        id: '${p['id']}',
        name: '${p['name'] ?? p['id']}',
        version: p['version'] as String?,
        description: (p['description'] as String?)?.trim(),
        builtin: p['builtin'] == true,
        enabled: p['enabled'] == true,
        loaded: p['loaded'] == true,
        error: p['error'] as String?,
        installed: installed,
        actions: [
          for (final a in ((p['actions'] as List?) ?? const []).cast<Map>())
            UiPluginAction(id: a['id'] as String, title: a['title'] as String)
        ],
      );
}

final class UiPluginAction {
  const UiPluginAction({required this.id, required this.title});
  final String id;
  final String title;
}

/// What a plugin's action answered: a title and its text, or nothing.
final class UiPluginResult {
  const UiPluginResult({required this.title, this.content = ''});
  final String title;
  final String content;

  static UiPluginResult? from(JsonMap r) => switch (r['result']) {
        {'title': final String title, 'content': final String content} =>
          UiPluginResult(title: title, content: content),
        null => null,
        final other => throw FormatException('plugins.invoke result: $other'),
      };
}

final class UiMarket {
  const UiMarket({this.plugins = const [], this.updates = const {}});
  final List<UiPlugin> plugins;

  /// Installed plugin → the newer version on the market.
  final Map<String, String> updates;
}

/// Syncing records between this computer and others through a WebDAV
/// folder (`sync.*`).
final class NextSync {
  NextSync(this.calls);
  final GuiCalls calls;

  Future<UiSync> status() async => UiSync.from(await calls.call('sync.status', {}));

  /// Saves the server, folder, interval and what goes along; omitted
  /// parts stay.
  Future<void> configure({
    String? url,
    String? username,
    String? folder,
    int? minutes,
    List<String>? kinds,
    bool? onChange,
  }) =>
      calls.call('sync.configure', {
        if (url != null) 'url': url,
        if (username != null) 'username': username,
        if (folder != null) 'remotePath': folder,
        if (minutes != null) 'intervalMinutes': minutes,
        if (kinds != null) 'categories': kinds,
        if (onChange != null) 'syncOnRecordChange': onChange,
      });

  /// NipaPlay's own password window.
  Future<void> login() => calls.call('sync.login', {});
  Future<void> setEnabled(bool on) => calls.call('sync.enable', {'enabled': on});

  /// Whether the server answers with the saved account.
  Future<bool> test() async {
    try {
      final r = await calls.call('sync.test', {});
      return r['connected'] == true;
    } on Failure {
      return false;
    }
  }

  Future<void> run() => calls.call('sync.run', {});
}

final class UiSync {
  const UiSync({
    this.url = '',
    this.username = '',
    this.folder = '',
    this.minutes = 30,
    this.kinds = const [],
    this.onChange = false,
    this.enabled = false,
    this.syncing = false,
    this.last,
    this.error,
    this.hasPassword = false,
  });
  final String url;
  final String username;
  final String folder;
  final int minutes;
  final List<String> kinds;
  final bool onChange;
  final bool enabled;
  final bool syncing;
  final DateTime? last;
  final String? error;

  /// A password is saved for this address and user.
  final bool hasPassword;

  static const allKinds = [
    ('watchHistory', '观看记录'),
    ('mediaLibraries', '媒体库'),
    ('episodeMatches', '识别结果'),
    ('preferences', '偏好'),
    ('accounts', '账号'),
  ];

  bool get configured => url.isNotEmpty;

  factory UiSync.from(JsonMap r) {
    final c = (r['configuration'] as Map?) ?? const {};
    final error = r['lastError'];
    return UiSync(
      url: '${c['url'] ?? ''}',
      username: '${c['username'] ?? ''}',
      folder: '${c['remotePath'] ?? ''}',
      minutes: (c['intervalMinutes'] as num?)?.toInt() ?? 30,
      kinds: [for (final k in (c['categories'] as List?) ?? const []) '$k'],
      onChange: c['syncOnRecordChange'] == true,
      enabled: r['enabled'] == true,
      syncing: r['syncing'] == true,
      last: DateTime.tryParse('${r['lastSyncAt']}')?.toLocal(),
      error: error is String && error.isNotEmpty ? error : null,
      hasPassword: r['hasPassword'] == true,
    );
  }
}

/// Folders on this computer NipaPlay looks through
/// (`media.library.roots.*`, `media.library.scan_classic`), and NipaPlay
/// shares nearby (`media.sources.discover`).
final class NextFolders {
  NextFolders(this.calls);
  final GuiCalls calls;

  Future<UiFolders> list() async =>
      UiFolders.from(await calls.call('media.library.roots.list', {}));

  /// The system's folder picker; the folders added.
  Future<List<String>> add() async =>
      ((await calls.call('media.library.roots.add', {}))['selected'] as List)
          .cast<String>();

  /// NipaPlay forgets the folder and what was watched in it; the files stay.
  Future<void> remove(String path) => calls.call('media.library.roots.remove', {
        'paths': [path]
      });

  /// Looks through [paths] (all when null); the task doing it. NipaPlay
  /// indexes their files as well, so they reach Nipa as facts even when
  /// Classic cannot identify them (without a dandanplay login it takes none).
  Future<String> scan([List<String>? paths]) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (final root in paths ?? (await list()).paths) {
      try {
        await calls.call('media.library.scan',
            {'root': root, 'requestId': 'gui-scan-$stamp-$root'});
      } catch (_) {
        // Classic's scan below still runs; the index can be built later.
      }
    }
    final r = await calls.call(
        'media.library.scan_classic', {if (paths != null) 'paths': paths});
    return r['jobId'] as String;
  }

  /// NipaPlay shares answering on this network.
  Future<List<UiShare>> nearby() async {
    final r = await calls.call('media.sources.discover', {'timeoutMs': 1500});
    return [
      for (final c in (r['candidates'] as List).cast<Map>())
        UiShare(name: '${c['name'] ?? c['address']}', address: '${c['address']}')
    ];
  }
}

final class UiFolders {
  const UiFolders(
      {this.paths = const [],
      this.scanning = false,
      this.failedFiles = const []});
  final List<String> paths;
  final bool scanning;

  /// Files the last scan could not take.
  final List<String> failedFiles;
  int get failed => failedFiles.length;

  /// Of those, the ones in [folder].
  int failedIn(String folder) =>
      failedFiles.where((f) => p.isWithin(folder, f)).length;

  factory UiFolders.from(JsonMap r) => UiFolders(
        paths: (r['roots'] as List).cast<String>(),
        scanning: r['scanning'] == true,
        failedFiles: [
          for (final f in ((r['failedFiles'] as List?) ?? const []).cast<Map>())
            '${f['path']}'
        ],
      );
}

final class UiShare {
  const UiShare({required this.name, required this.address});
  final String name;
  final String address;
}
