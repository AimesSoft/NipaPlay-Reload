import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

import '../../ui_data/host_settings.dart';

/// What the settings page reads and changes. Everything here goes through
/// the same Actions Nipa uses (`settings.*`, `accounts.*`,
/// `media.sources.*`), invoked as the person (`origin: gui`); memory is
/// NipaPlay's own memory files; [host] holds what only the person at this
/// device may change.
abstract interface class NextSettingsData {
  /// Every setting the registry shows on this device, with its value and
  /// latest change (`settings.describe`).
  Future<List<UiSetting>> settings();

  /// `settings.set`; the setting as saved.
  Future<UiSetting> set(String key, Object? value);

  /// `settings.reset` for each key, in order.
  Future<void> reset(List<String> keys);

  /// A file or folder for a path setting, from the system's picker; null
  /// when cancelled.
  Future<String?> pickPath({required bool directory});

  Future<List<UiAccount>> accounts();

  /// Opens NipaPlay's own login window for [provider] (the secret is only
  /// ever typed there).
  Future<void> login(String provider);
  Future<void> logout(String provider);
  Future<UiBangumiSync> bangumiSync();
  Future<void> syncBangumi({bool full = false});

  Future<List<UiMediaSource>> sources();
  Future<UiMediaSource> addSource(UiSourceDraft draft);
  Future<UiMediaSource> updateSource(String sourceId, UiSourceDraft draft);
  Future<void> removeSource(String sourceId);

  /// Quick Connect when the server has it (a code to approve there),
  /// otherwise NipaPlay's own password window.
  Future<UiSourceLogin> loginSource(String sourceId);
  Future<UiSourceCheck> checkSource(String sourceId);
  Future<List<UiSourceLibrary>> libraries(String sourceId);
  Future<void> selectLibraries(String sourceId, List<String> libraryIds);

  /// What Nipa remembers: preferences, the index, topic notes.
  Future<List<UiMemoryFile>> memories();
  Future<UiMemoryDoc> memory(String path);
  Future<void> editMemory(UiMemoryDoc doc, String content);
  Future<void> forgetMemory(UiMemoryDoc doc);

  /// Fires when what Nipa remembers may have changed elsewhere (her own
  /// notes included).
  Stream<void> get memoryChanges;

  /// The version running (`app.instance`).
  Future<UiAbout> about();

  NextHostSettings get host;

  /// Fires when something above may have changed elsewhere (Nipa, another
  /// window, a login finishing).
  Stream<void> get changes;
}

/// How a setting is changed, from its schema.
enum UiSettingKind {
  toggle,
  choice,
  number,
  text,
  secret,
  path,
  color,
  list,

  /// An object or anything else the page has no control for (only Nipa
  /// can change it).
  other,
}

final class UiSetting {
  const UiSetting({
    required this.key,
    required this.title,
    required this.kind,
    this.value,
    this.defaultValue,
    this.choices = const [],
    this.names = const {},
    this.min,
    this.max,
    this.step,
    this.integer = false,
    this.directory = false,
    this.apply = 'immediate',
    this.runtime = false,
    this.revision = 0,
    this.changedBy,
    this.changedAt,
    this.reason,
    this.previousValue,
  });

  final String key;
  final String title;
  final UiSettingKind kind;
  final Object? value;
  final Object? defaultValue;

  /// For [UiSettingKind.choice] (and colour swatches): the allowed values.
  final List<Object?> choices;

  /// What values are called, by their text (the registry's `enumNames`
  /// and `valueNames`).
  final Map<String, String> names;
  final num? min;
  final num? max;
  final num? step;
  final bool integer;

  /// For [UiSettingKind.path]: a folder rather than a file.
  final bool directory;

  /// `immediate`, `reload_player`, `reload_server` or `restart_app`.
  final String apply;

  /// The player's live state (volume, brightness…) rather than a
  /// preference: not shown on the page.
  final bool runtime;
  final int revision;

  /// Who changed it last: `user`, `agent` (Nipa), `migration`…
  final String? changedBy;
  final DateTime? changedAt;
  final String? reason;
  final Object? previousValue;

  String get domain => key.split('.').first;

  /// Nipa changed it last, and it has not been touched since. The
  /// registry calls MCP callers `agent`; Nipa in NipaPlay (her
  /// conversations and helpers) and other agents' CLI calls still arrive
  /// as `harness_cli…` (Y8_REPORT).
  bool get byNipa =>
      changedBy == 'agent' || (changedBy?.startsWith('harness_cli') ?? false);

  bool get isDefault => '$value' == '$defaultValue';

  /// What [value] is called; the value itself when it has no name.
  String nameOf(Object? value) {
    final text = value is double && value == value.roundToDouble()
        ? '${value.toInt()}'
        : '$value';
    return names['$value'] ?? names[text] ?? text;
  }

  UiSetting copyWith({Object? value}) => UiSetting(
        key: key,
        title: title,
        kind: kind,
        value: value,
        defaultValue: defaultValue,
        choices: choices,
        names: names,
        min: min,
        max: max,
        step: step,
        integer: integer,
        directory: directory,
        apply: apply,
        runtime: runtime,
        revision: revision,
        changedBy: changedBy,
        changedAt: changedAt,
        reason: reason,
        previousValue: previousValue,
      );

  /// A colour value as the registry writes them: ARGB or `#RRGGBB[AA]`.
  static bool _isColor(Object? v) =>
      v is int || (v is String && RegExp(r'^#[0-9A-Fa-f]{6,8}$').hasMatch(v));

  /// A `settings.describe` row (contract and value merged).
  factory UiSetting.fromRow(Map row) {
    final key = row['key'] as String;
    final rawType = row['type'];
    final type = rawType is List
        ? rawType.where((t) => t != 'null').firstOrNull
        : rawType;
    final choices =
        row['enum'] is List ? List<Object?>.of(row['enum'] as List) : null;
    final provenance = row['provenance'];
    final storage = row['storage'];
    final format = row['format'] ?? row['x-format'];
    final secret = row['x-secret'] == true || row['writeOnly'] == true;
    final pattern = row['pattern'] as String?;
    // The registry does not mark paths yet (see Y8_REPORT): `format` when it
    // does, the key's own word until then.
    // (webdavQuick's folders are on the server, not this computer.)
    final namedPath = format == null &&
        !key.startsWith('webdavQuick.') &&
        RegExp(r'(path|directory|dir)$', caseSensitive: false).hasMatch(key);
    final pathFormat = format == 'path' ||
        format == 'directory' ||
        format == 'file' ||
        (type == 'string' && namedPath);
    final kind = switch (type) {
      'boolean' => UiSettingKind.toggle,
      _ when choices != null && choices.length > 1 =>
        key.toLowerCase().endsWith('color') && choices.every(_isColor)
            ? UiSettingKind.color
            : UiSettingKind.choice,
      'integer' || 'number' => UiSettingKind.number,
      'string' when secret => UiSettingKind.secret,
      'string' when pathFormat => UiSettingKind.path,
      'string' when pattern != null && pattern.startsWith('^#') =>
        UiSettingKind.color,
      'string' => UiSettingKind.text,
      'array'
          when row['items'] is Map &&
              (row['items'] as Map)['type'] == 'string' =>
        UiSettingKind.list,
      _ => UiSettingKind.other,
    };
    return UiSetting(
      key: key,
      title: (row['title'] as String?) ?? key,
      kind: kind,
      value: row['value'],
      defaultValue: row['default'],
      choices: choices ?? const [],
      names: {
        if ((choices, row['enumNames']) case (final List c, final List names))
          for (final (i, name) in names.indexed) '${c[i]}': name as String,
        if (row['valueNames'] case final Map names)
          for (final e in names.entries) '${e.key}': e.value as String,
      },
      min: row['minimum'] as num?,
      max: row['maximum'] as num?,
      step: row['step'] as num?,
      integer: type == 'integer',
      directory: format == 'directory' ||
          (namedPath &&
              RegExp(r'(directory|dir)$', caseSensitive: false).hasMatch(key)),
      apply: (row['apply'] as String?) ?? 'immediate',
      runtime: storage is Map && storage['kind'] == 'runtime',
      revision: (row['revision'] as num?)?.toInt() ?? 0,
      changedBy: provenance is Map ? provenance['changedBy'] as String? : null,
      changedAt: provenance is Map
          ? DateTime.tryParse('${provenance['changedAt']}')?.toLocal()
          : null,
      reason: provenance is Map ? provenance['reason'] as String? : null,
      previousValue: provenance is Map ? provenance['previousValue'] : null,
    );
  }
}

final class UiAccount {
  const UiAccount(
      {required this.provider, this.loggedIn = false, this.username});

  /// `dandanplay` or `bangumi`.
  final String provider;
  final bool loggedIn;
  final String? username;

  String get name => switch (provider) {
        'dandanplay' => '弹弹play',
        'bangumi' => 'Bangumi',
        _ => provider,
      };
}

final class UiBangumiSync {
  const UiBangumiSync({this.last, this.works = 0, this.failed = 0});
  final DateTime? last;
  final int works;
  final int failed;
}

enum UiSourceState { connected, unverified, failed }

final class UiMediaSource {
  const UiMediaSource({
    required this.sourceId,
    required this.type,
    required this.name,
    this.url = '',
    this.username = '',
    this.state = UiSourceState.unverified,
    this.selected = const [],
    this.needsPassword = false,
  });
  final String sourceId;

  /// jellyfin, emby, smb, webdav, nipaplay, dandanplay_remote.
  final String type;
  final String name;
  final String url;
  final String username;
  final UiSourceState state;

  /// The saved password is gone and has to be typed again.
  final bool needsPassword;

  /// The libraries shown and synced.
  final List<String> selected;

  static const types = [
    'jellyfin',
    'emby',
    'smb',
    'webdav',
    'nipaplay',
    'dandanplay_remote'
  ];

  static String typeName(String type) => switch (type) {
        'jellyfin' => 'Jellyfin',
        'emby' => 'Emby',
        'smb' => 'SMB',
        'webdav' => 'WebDAV',
        'nipaplay' => 'NipaPlay',
        'dandanplay_remote' => '弹弹play 远程',
        _ => type,
      };

  /// SMB is reached by host and port; the others by address.
  static bool byHost(String type) => type == 'smb';

  /// The address as people read it: host, without scheme or slashes.
  String get place {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
  }

  factory UiMediaSource.fromRow(Map row) => UiMediaSource(
        sourceId: row['sourceId'] as String,
        type: row['type'] as String,
        name: row['name'] as String,
        url: (row['url'] as String?) ?? '',
        username: (row['username'] as String?) ?? '',
        state: switch (row['connectionState']) {
          'connected' => UiSourceState.connected,
          'failed' => UiSourceState.failed,
          _ => UiSourceState.unverified,
        },
        selected: [
          for (final id in (row['selectedLibraries'] as List?) ?? const [])
            '$id'
        ],
        needsPassword: ((row['type'] == 'smb' || row['type'] == 'webdav') &&
            ((row['username'] as String?) ?? '').isNotEmpty &&
            (row['credential'] as Map?)?['state'] == 'missing'),
      );
}

final class UiSourceDraft {
  const UiSourceDraft({
    required this.type,
    required this.name,
    this.url,
    this.username,
    this.host,
    this.port,
    this.domain,
  });
  final String type;
  final String name;
  final String? url;
  final String? username;
  final String? host;
  final int? port;
  final String? domain;

  JsonMap toJson() => {
        'name': name,
        if (url != null && url!.isNotEmpty) 'url': url,
        if (username != null) 'username': username,
        if (host != null && host!.isNotEmpty) 'host': host,
        if (port != null) 'port': port,
        if (domain != null) 'domain': domain,
      };
}

final class UiSourceLogin {
  const UiSourceLogin({this.code, this.message, this.connected = false});

  /// Quick Connect: the code to approve on the server.
  final String? code;
  final String? message;
  final bool connected;
}

final class UiSourceCheck {
  const UiSourceCheck({required this.ok, this.message});
  final bool ok;
  final String? message;
}

final class UiSourceLibrary {
  const UiSourceLibrary({required this.id, required this.name, this.kind});
  final String id;
  final String name;
  final String? kind;
}

final class UiMemoryFile {
  const UiMemoryFile(
      {required this.path, this.bytes = 0, this.title, this.revision});
  final String path;
  final int bytes;

  /// The note's own heading, when it has one.
  final String? title;
  final String? revision;

  /// What the page calls it.
  String get name => switch (path) {
        'preferences.md' => '偏好',
        'MEMORY.md' => '目录',
        _ => title ?? path.split('/').last.replaceAll(RegExp(r'\.md$'), ''),
      };
}

final class UiMemoryDoc {
  const UiMemoryDoc(
      {required this.path, required this.content, required this.revision});
  final String path;
  final String content;
  final String revision;
}

final class UiAbout {
  const UiAbout({this.version, this.build});
  final String? version;
  final String? build;
}

/// The settings registry's failure, in a few plain words.
String settingFailure(Object error) {
  if (error is Failure) {
    return switch (error.code) {
      FailureCode.invalidInput => '这个值不行',
      FailureCode.conflict => '刚被改过，再试一次',
      FailureCode.notFound => '这里没有这一项',
      _ => '没能保存',
    };
  }
  return '没能保存';
}
