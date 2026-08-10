import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/emby_media_selection.dart';
import '../models/server_profile_model.dart';
import 'emby_release_name_parser.dart';

const _preferencesKey = 'emby_media_preferences_v1';
const _schemaVersion = 1;

String? embyAccountKey(ServerProfile? profile, String? userId) {
  final serverId = profile?.serverId?.trim();
  final profileId = profile?.id.trim();
  final resolvedServer = serverId?.isNotEmpty == true ? serverId : profileId;
  final resolvedUser = userId?.trim();
  if (resolvedServer == null ||
      resolvedServer.isEmpty ||
      resolvedUser == null ||
      resolvedUser.isEmpty) {
    return null;
  }
  return '$resolvedServer:$resolvedUser';
}

EmbySelectionContext? buildEmbySelectionContext({
  required ServerProfile? profile,
  required String? userId,
  required String seriesId,
  required String episodeId,
}) {
  final accountKey = embyAccountKey(profile, userId);
  final normalizedSeriesId = seriesId.trim();
  final normalizedEpisodeId = episodeId.trim();
  if (accountKey == null ||
      normalizedSeriesId.isEmpty ||
      normalizedEpisodeId.isEmpty) {
    return null;
  }
  return EmbySelectionContext(
    accountKey: accountKey,
    seriesId: normalizedSeriesId,
    episodeId: normalizedEpisodeId,
  );
}

class EmbyMediaPreferenceStore {
  EmbyMediaPreferenceStore(
    this._preferences, {
    this.maxEpisodeRecords = 200,
    DateTime Function()? now,
  })  : assert(maxEpisodeRecords > 0),
        _now = now ?? DateTime.now;

  final SharedPreferences _preferences;
  final int maxEpisodeRecords;
  final DateTime Function() _now;

  Future<EmbyPreferenceLayers> load(EmbySelectionContext context) async {
    final document = _readDocument();
    if (document.wasCleaned) await _writeDocument(document);

    final account = document.accounts[context.accountKey];
    if (account == null) return const EmbyPreferenceLayers();
    return EmbyPreferenceLayers(
      episode: account.episodes[context.episodeId]?.preference,
      series: account.series[context.seriesId]?.preference,
      global: account.global?.preference,
    );
  }

  Future<void> saveManualPatch(
    EmbySelectionContext context,
    EmbyMediaSourceDescriptor currentSource,
    EmbyManualSelectionPatch patch,
  ) async {
    if (patch.audio?.mode == EmbyTrackPreferenceMode.disabled) {
      throw ArgumentError.value(
        patch.audio,
        'patch.audio',
        'Audio preferences cannot be disabled.',
      );
    }

    final document = _readDocument();
    final account = document.accounts.putIfAbsent(
      context.accountKey,
      _AccountRecord.new,
    );
    final identity =
        _SourceIdentity.fromDescriptor(patch.source ?? currentSource);

    final existingEpisode = account.episodes[context.episodeId];
    final episode = _patchEpisode(existingEpisode, patch, _now());
    if (episode == null) {
      account.episodes.remove(context.episodeId);
    } else {
      account.episodes[context.episodeId] = episode;
    }

    final existingSeries = account.series[context.seriesId];
    final series = _patchSeries(existingSeries, identity, patch);
    if (series == null) {
      account.series.remove(context.seriesId);
    } else {
      account.series[context.seriesId] = series;
    }

    final global = _patchGlobal(account.global, identity, patch);
    account.global = global;

    _evictOldEpisodes(document);
    document.removeEmptyAccounts();
    await _writeDocument(document);
  }

  _PreferenceDocument _readDocument() {
    final raw = _preferences.getString(_preferencesKey);
    if (raw == null) return _PreferenceDocument.empty();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != _schemaVersion) {
        return _PreferenceDocument.empty(wasCleaned: true);
      }
      final document = _PreferenceDocument.fromJson(decoded);
      if (document.wasCleaned || jsonEncode(document.toJson()) != raw) {
        return _PreferenceDocument(document.accounts, wasCleaned: true);
      }
      return document;
    } on FormatException {
      return _PreferenceDocument.empty(wasCleaned: true);
    } on Object {
      return _PreferenceDocument.empty(wasCleaned: true);
    }
  }

  Future<void> _writeDocument(_PreferenceDocument document) =>
      _preferences.setString(_preferencesKey, jsonEncode(document.toJson()));

  void _evictOldEpisodes(_PreferenceDocument document) {
    final records = <_EpisodeRecordReference>[];
    for (final accountEntry in document.accounts.entries) {
      for (final episodeEntry in accountEntry.value.episodes.entries) {
        records.add(
          _EpisodeRecordReference(
            accountKey: accountEntry.key,
            episodeId: episodeEntry.key,
            record: episodeEntry.value,
          ),
        );
      }
    }
    if (records.length <= maxEpisodeRecords) return;

    records.sort((left, right) {
      final byTime = left.record.updatedAt.compareTo(right.record.updatedAt);
      if (byTime != 0) return byTime;
      final byAccount = left.accountKey.compareTo(right.accountKey);
      return byAccount != 0
          ? byAccount
          : left.episodeId.compareTo(right.episodeId);
    });
    final countToRemove = records.length - maxEpisodeRecords;
    for (var index = 0; index < countToRemove; index++) {
      final record = records[index];
      document.accounts[record.accountKey]?.episodes.remove(record.episodeId);
    }
  }
}

_EpisodeRecord? _patchEpisode(
  _EpisodeRecord? existing,
  EmbyManualSelectionPatch patch,
  DateTime now,
) {
  var mediaSourceId = existing?.mediaSourceId;
  var displayName = existing?.displayName;
  var audio = existing?.audio;
  var subtitle = existing?.subtitle;

  if (patch.source != null) {
    mediaSourceId = _nonEmpty(patch.source!.source.id);
    displayName = _nonEmpty(patch.source!.displayName);
  }
  audio = _applyTrackPatch(audio, patch.audio);
  subtitle = _applyTrackPatch(subtitle, patch.subtitle);

  if (mediaSourceId == null &&
      displayName == null &&
      audio == null &&
      subtitle == null) {
    return null;
  }
  return _EpisodeRecord(
    mediaSourceId: mediaSourceId,
    displayName: displayName,
    audio: audio,
    subtitle: subtitle,
    updatedAt: now.toUtc(),
  );
}

_SeriesRecord? _patchSeries(
  _SeriesRecord? existing,
  _SourceIdentity identity,
  EmbyManualSelectionPatch patch,
) {
  final sourceSelected =
      existing?.sourceSelected == true || patch.source != null;
  final audio = _applyTrackPatch(existing?.audio, patch.audio, inherited: true);
  final subtitle =
      _applyTrackPatch(existing?.subtitle, patch.subtitle, inherited: true);
  final resolvedIdentity =
      patch.source != null || existing == null || existing.identity.isEmpty
          ? identity
          : existing.identity;
  final record = _SeriesRecord(
    sourceSelected: sourceSelected,
    identity: resolvedIdentity,
    audio: audio,
    subtitle: subtitle,
  );
  return record.preference.isEmpty ? null : record;
}

_GlobalRecord? _patchGlobal(
  _GlobalRecord? existing,
  _SourceIdentity identity,
  EmbyManualSelectionPatch patch,
) {
  final sourceSelected =
      existing?.sourceSelected == true || patch.source != null;
  final audio = _applyTrackPatch(existing?.audio, patch.audio, inherited: true);
  final subtitle =
      _applyTrackPatch(existing?.subtitle, patch.subtitle, inherited: true);
  final resolvedIdentity =
      patch.source != null || existing == null || existing.identity.isEmpty
          ? identity
          : existing.identity;
  final record = _GlobalRecord(
    sourceSelected: sourceSelected,
    identity: resolvedIdentity,
    audio: audio,
    subtitle: subtitle,
  );
  return record.preference.isEmpty ? null : record;
}

EmbyTrackPreference? _applyTrackPatch(
  EmbyTrackPreference? existing,
  EmbyTrackPreference? patch, {
  bool inherited = false,
}) {
  if (patch == null) return existing;
  if (patch.mode == EmbyTrackPreferenceMode.followDefault) return null;
  if (patch.mode == EmbyTrackPreferenceMode.disabled) return patch;
  final fingerprint = patch.fingerprint;
  if (fingerprint == null) return existing;
  return EmbyTrackPreference.track(
    fingerprint,
    sourceIndex: inherited ? null : patch.sourceIndex,
    mediaSourceId: inherited ? null : patch.mediaSourceId,
  );
}

class _PreferenceDocument {
  _PreferenceDocument(this.accounts, {required this.wasCleaned});

  factory _PreferenceDocument.empty({bool wasCleaned = false}) =>
      _PreferenceDocument(<String, _AccountRecord>{}, wasCleaned: wasCleaned);

  factory _PreferenceDocument.fromJson(Map raw) {
    var wasCleaned = false;
    final accounts = <String, _AccountRecord>{};
    final rawAccounts = raw['accounts'];
    if (rawAccounts is! Map) {
      return _PreferenceDocument.empty(wasCleaned: true);
    }
    for (final entry in rawAccounts.entries) {
      final accountKey = _nonEmpty(entry.key);
      if (accountKey == null || entry.value is! Map) {
        wasCleaned = true;
        continue;
      }
      final account = _AccountRecord.fromJson(entry.value as Map);
      wasCleaned = wasCleaned || account.wasCleaned;
      if (account.isEmpty) {
        wasCleaned = true;
        continue;
      }
      accounts[accountKey] = account;
    }
    return _PreferenceDocument(accounts, wasCleaned: wasCleaned);
  }

  final Map<String, _AccountRecord> accounts;
  final bool wasCleaned;

  void removeEmptyAccounts() {
    accounts.removeWhere((_, account) => account.isEmpty);
  }

  Map<String, Object?> toJson() => {
        'version': _schemaVersion,
        'accounts': accounts.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      };
}

class _AccountRecord {
  _AccountRecord({
    Map<String, _EpisodeRecord>? episodes,
    Map<String, _SeriesRecord>? series,
    this.global,
    this.wasCleaned = false,
  })  : episodes = episodes ?? <String, _EpisodeRecord>{},
        series = series ?? <String, _SeriesRecord>{};

  factory _AccountRecord.fromJson(Map raw) {
    var wasCleaned = false;
    final episodes = <String, _EpisodeRecord>{};
    final series = <String, _SeriesRecord>{};

    void readRecords<T>(
      Object? value,
      T? Function(Map value) decode,
      Map<String, T> target,
    ) {
      if (value == null) return;
      if (value is! Map) {
        wasCleaned = true;
        return;
      }
      for (final entry in value.entries) {
        final key = _nonEmpty(entry.key);
        if (key == null || entry.value is! Map) {
          wasCleaned = true;
          continue;
        }
        final record = decode(entry.value as Map);
        if (record == null) {
          wasCleaned = true;
          continue;
        }
        target[key] = record;
      }
    }

    readRecords<_EpisodeRecord>(
      raw['episodes'],
      _EpisodeRecord.fromJson,
      episodes,
    );
    readRecords<_SeriesRecord>(raw['series'], _SeriesRecord.fromJson, series);

    _GlobalRecord? global;
    final rawGlobal = raw['global'];
    if (rawGlobal != null) {
      if (rawGlobal is Map) {
        global = _GlobalRecord.fromJson(rawGlobal);
        if (global == null) wasCleaned = true;
      } else {
        wasCleaned = true;
      }
    }
    return _AccountRecord(
      episodes: episodes,
      series: series,
      global: global,
      wasCleaned: wasCleaned,
    );
  }

  final Map<String, _EpisodeRecord> episodes;
  final Map<String, _SeriesRecord> series;
  _GlobalRecord? global;
  final bool wasCleaned;

  bool get isEmpty => episodes.isEmpty && series.isEmpty && global == null;

  Map<String, Object?> toJson() => {
        if (episodes.isNotEmpty)
          'episodes':
              episodes.map((key, value) => MapEntry(key, value.toJson())),
        if (series.isNotEmpty)
          'series': series.map((key, value) => MapEntry(key, value.toJson())),
        if (global != null) 'global': global!.toJson(),
      };
}

class _EpisodeRecord {
  const _EpisodeRecord({
    this.mediaSourceId,
    this.displayName,
    this.audio,
    this.subtitle,
    required this.updatedAt,
  });

  static _EpisodeRecord? fromJson(Map raw) {
    final updatedAt = DateTime.tryParse(_nonEmpty(raw['updatedAt']) ?? '');
    if (updatedAt == null) return null;
    final mediaSourceId = _nonEmpty(raw['mediaSourceId']);
    final displayName = _nonEmpty(raw['displayName']);
    final audio = _decodeTrack(raw['audio'], allowBinding: true);
    final subtitle = _decodeTrack(raw['subtitle'], allowBinding: true);
    if (mediaSourceId == null &&
        displayName == null &&
        audio == null &&
        subtitle == null) {
      return null;
    }
    return _EpisodeRecord(
      mediaSourceId: mediaSourceId,
      displayName: displayName,
      audio: audio,
      subtitle: subtitle,
      updatedAt: updatedAt.toUtc(),
    );
  }

  final String? mediaSourceId;
  final String? displayName;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;
  final DateTime updatedAt;

  EmbyEpisodePreference get preference => EmbyEpisodePreference(
        mediaSourceId: mediaSourceId,
        displayName: displayName,
        audio: audio,
        subtitle: subtitle,
        updatedAt: updatedAt,
      );

  Map<String, Object?> toJson() => {
        if (mediaSourceId != null) 'mediaSourceId': mediaSourceId,
        if (displayName != null) 'displayName': displayName,
        if (audio != null) 'audio': _trackToJson(audio!),
        if (subtitle != null) 'subtitle': _trackToJson(subtitle!),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class _SeriesRecord {
  const _SeriesRecord({
    required this.sourceSelected,
    required this.identity,
    this.audio,
    this.subtitle,
  });

  static _SeriesRecord? fromJson(Map raw) {
    final sourceSelected = raw['sourceSelected'] == true;
    final identity = _SourceIdentity.fromJson(raw);
    final audio = _decodeTrack(raw['audio'], allowBinding: false);
    final subtitle = _decodeTrack(raw['subtitle'], allowBinding: false);
    final record = _SeriesRecord(
      sourceSelected: sourceSelected,
      identity: identity,
      audio: audio,
      subtitle: subtitle,
    );
    if (record.preference.isEmpty) {
      return null;
    }
    return record;
  }

  final bool sourceSelected;
  final _SourceIdentity identity;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;

  EmbySeriesPreference get preference {
    if (!sourceSelected && audio == null && subtitle == null) {
      return const EmbySeriesPreference();
    }
    return EmbySeriesPreference(
      normalizedFullName: identity.normalizedFullName,
      families: identity.families,
      features: identity.features,
      technical: identity.technical,
      audio: audio,
      subtitle: subtitle,
    );
  }

  Map<String, Object?> toJson() => {
        if (sourceSelected) 'sourceSelected': true,
        ...identity.toSeriesJson(),
        if (audio != null) 'audio': _trackToJson(audio!),
        if (subtitle != null) 'subtitle': _trackToJson(subtitle!),
      };
}

class _GlobalRecord {
  const _GlobalRecord({
    required this.sourceSelected,
    required this.identity,
    this.audio,
    this.subtitle,
  });

  static _GlobalRecord? fromJson(Map raw) {
    final sourceSelected = raw['sourceSelected'] == true;
    final identity = _SourceIdentity.fromJson(raw);
    final audio = _decodeTrack(raw['audio'], allowBinding: false);
    final subtitle = _decodeTrack(raw['subtitle'], allowBinding: false);
    final record = _GlobalRecord(
      sourceSelected: sourceSelected,
      identity: identity,
      audio: audio,
      subtitle: subtitle,
    );
    if (record.preference.isEmpty) {
      return null;
    }
    return record;
  }

  final bool sourceSelected;
  final _SourceIdentity identity;
  final EmbyTrackPreference? audio;
  final EmbyTrackPreference? subtitle;

  EmbyGlobalPreference get preference {
    if (!sourceSelected && audio == null && subtitle == null) {
      return const EmbyGlobalPreference();
    }
    return EmbyGlobalPreference(
      families: identity.families,
      technical: identity.technical,
      audio: audio,
      subtitle: subtitle,
    );
  }

  Map<String, Object?> toJson() => {
        if (sourceSelected) 'sourceSelected': true,
        ...identity.toGlobalJson(),
        if (audio != null) 'audio': _trackToJson(audio!),
        if (subtitle != null) 'subtitle': _trackToJson(subtitle!),
      };
}

class _SourceIdentity {
  const _SourceIdentity({
    this.normalizedFullName,
    this.families = const <String>{},
    this.features = const <String>{},
    this.technical,
  });

  factory _SourceIdentity.fromDescriptor(EmbyMediaSourceDescriptor source) {
    final release = parseEmbyReleaseIdentity(source.displayName);
    return _SourceIdentity(
      normalizedFullName: _nonEmpty(release.normalizedFullName),
      families: release.families,
      features: release.features,
      technical: _technicalIsEmpty(source.technical) ? null : source.technical,
    );
  }

  factory _SourceIdentity.fromJson(Map raw) => _SourceIdentity(
        normalizedFullName: _nonEmpty(raw['normalizedFullName']),
        families: _stringSet(raw['families']),
        features: _stringSet(raw['features']),
        technical: _technicalFromJson(raw['technical']),
      );

  final String? normalizedFullName;
  final Set<String> families;
  final Set<String> features;
  final EmbyTechnicalFingerprint? technical;

  bool get isEmpty =>
      normalizedFullName == null &&
      families.isEmpty &&
      features.isEmpty &&
      technical == null;

  Map<String, Object?> toSeriesJson() => {
        if (normalizedFullName != null)
          'normalizedFullName': normalizedFullName,
        if (families.isNotEmpty) 'families': families.toList()..sort(),
        if (features.isNotEmpty) 'features': features.toList()..sort(),
        if (technical != null) 'technical': _technicalToJson(technical!),
      };

  Map<String, Object?> toGlobalJson() => {
        if (families.isNotEmpty) 'families': families.toList()..sort(),
        if (technical != null) 'technical': _technicalToJson(technical!),
      };
}

class _EpisodeRecordReference {
  const _EpisodeRecordReference({
    required this.accountKey,
    required this.episodeId,
    required this.record,
  });

  final String accountKey;
  final String episodeId;
  final _EpisodeRecord record;
}

EmbyTrackPreference? _decodeTrack(Object? raw, {required bool allowBinding}) {
  if (raw is! Map) return null;
  switch (raw['mode']) {
    case 'disabled':
      return const EmbyTrackPreference.disabled();
    case 'track':
      final fingerprint = _fingerprintFromJson(raw['fingerprint']);
      if (fingerprint == null) return null;
      final sourceIndex = _nonNegativeInt(raw['sourceIndex']);
      final mediaSourceId = _nonEmpty(raw['mediaSourceId']);
      final hasBinding = sourceIndex != null || mediaSourceId != null;
      if (hasBinding && (sourceIndex == null || mediaSourceId == null)) {
        return null;
      }
      return EmbyTrackPreference.track(
        fingerprint,
        sourceIndex: allowBinding ? sourceIndex : null,
        mediaSourceId: allowBinding ? mediaSourceId : null,
      );
    default:
      return null;
  }
}

Map<String, Object?> _trackToJson(EmbyTrackPreference preference) {
  switch (preference.mode) {
    case EmbyTrackPreferenceMode.disabled:
      return const {'mode': 'disabled'};
    case EmbyTrackPreferenceMode.track:
      final fingerprint = preference.fingerprint;
      if (fingerprint == null) return const {};
      return {
        'mode': 'track',
        'fingerprint': _fingerprintToJson(fingerprint),
        if (preference.sourceIndex != null)
          'sourceIndex': preference.sourceIndex,
        if (preference.mediaSourceId != null)
          'mediaSourceId': preference.mediaSourceId,
      };
    case EmbyTrackPreferenceMode.followDefault:
      return const {};
  }
}

EmbyTrackFingerprint? _fingerprintFromJson(Object? raw) {
  if (raw is! Map) return null;
  final channels = raw['channels'];
  if (channels != null && _nonNegativeInt(channels) == null) return null;
  final fingerprint = EmbyTrackFingerprint(
    language: _nonEmpty(raw['language']),
    normalizedTitle: _nonEmpty(raw['normalizedTitle']),
    codec: _nonEmpty(raw['codec']),
    channels: _nonNegativeInt(channels),
    isExternal: raw['isExternal'] is bool ? raw['isExternal'] as bool : null,
  );
  return _fingerprintIsEmpty(fingerprint) ? null : fingerprint;
}

Map<String, Object?> _fingerprintToJson(EmbyTrackFingerprint fingerprint) => {
      if (fingerprint.language != null) 'language': fingerprint.language,
      if (fingerprint.normalizedTitle != null)
        'normalizedTitle': fingerprint.normalizedTitle,
      if (fingerprint.codec != null) 'codec': fingerprint.codec,
      if (fingerprint.channels != null) 'channels': fingerprint.channels,
      if (fingerprint.isExternal != null) 'isExternal': fingerprint.isExternal,
    };

bool _fingerprintIsEmpty(EmbyTrackFingerprint fingerprint) =>
    fingerprint.language == null &&
    fingerprint.normalizedTitle == null &&
    fingerprint.codec == null &&
    fingerprint.channels == null &&
    fingerprint.isExternal == null;

EmbyTechnicalFingerprint? _technicalFromJson(Object? raw) {
  if (raw is! Map) return null;
  final height = raw['height'];
  if (height != null && _nonNegativeInt(height) == null) return null;
  final value = EmbyTechnicalFingerprint(
    height: _nonNegativeInt(height),
    videoCodec: _nonEmpty(raw['videoCodec']),
    hdr: _nonEmpty(raw['hdr']),
    container: _nonEmpty(raw['container']),
  );
  return _technicalIsEmpty(value) ? null : value;
}

Map<String, Object?> _technicalToJson(EmbyTechnicalFingerprint value) => {
      if (value.height != null) 'height': value.height,
      if (value.videoCodec != null) 'videoCodec': value.videoCodec,
      if (value.hdr != null) 'hdr': value.hdr,
      if (value.container != null) 'container': value.container,
    };

bool _technicalIsEmpty(EmbyTechnicalFingerprint value) =>
    value.height == null &&
    value.videoCodec == null &&
    value.hdr == null &&
    value.container == null;

Set<String> _stringSet(Object? value) {
  if (value is! List) return const <String>{};
  return value.map(_nonEmpty).whereType<String>().toSet();
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int? _nonNegativeInt(Object? value) {
  final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
  return parsed != null && parsed >= 0 ? parsed : null;
}
