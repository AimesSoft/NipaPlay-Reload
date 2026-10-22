import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import 'registry.dart';

/// What is in effect for one setting while the application runs, beside the
/// value that is stored. [value] is null when it is not known ([state]
/// `unknown`) or when the stored value is not in use at all (`inactive`).
final class Effective {
  const Effective._(this.value, this.state, this.source, this.reason, this.detail);

  /// The running value equals the stored one.
  const Effective.same(Object? value, {String source = 'live', String? detail})
      : this._(value, 'same', source, null, detail);

  /// The running value is not the stored one.
  const Effective.differs(Object? value, String reason, String detail,
      {String source = 'live'})
      : this._(value, 'differs', source, reason, detail);

  /// The stored value is not in use: another setting, the kernel or the
  /// platform stops it from having an effect.
  const Effective.inactive(String reason, String detail)
      : this._(null, 'inactive', null, reason, detail);

  /// The running value cannot be read; [reason] says why.
  const Effective.unknown(String reason, String detail)
      : this._(null, 'unknown', null, reason, detail);

  final Object? value;

  /// `same`, `differs`, `inactive` or `unknown`.
  final String state;

  /// Where [value] was read: `live` (the running component), `startup` (the
  /// stored value as the registry started, which is what a restart-only
  /// setting loaded) or `storage` (no separate running value is observable;
  /// the setter that saves it is the one the running component uses).
  final String? source;
  final String? reason, detail;

  JsonMap toJson() => {
        'effective': value,
        'effectiveState': state,
        'effectiveSource': source,
        'effectiveReason': reason,
        'effectiveDetail': detail,
      };
}

/// Settings read once when the application starts. Their stored value moves on
/// while the loaded one stays until the next start.
const startupLoadedSettings = {
  'general.startupWindowState',
  'general.startupWindowPosition',
  'general.startupWindowWidth',
  'general.startupWindowHeight',
  'player.androidAudioOutput',
  'appearance.remoteAccessQrVisible',
  'appearance.animeDetailDisplayMode',
};

/// Settings read when their page or window is created.
const pageLoadedSettings = {
  'appearance.classicLibrarySection',
  'appearance.classicLibrarySectionOrder',
  'appearance.classicLocalLibrarySort',
  'appearance.collectionSort.local',
  'appearance.collectionSort.webdav',
  'appearance.collectionSort.smb',
  'appearance.unwatchedOnly.jellyfin',
  'appearance.unwatchedOnly.emby',
  'appearance.unwatchedOnly.shared',
  'diagnostics.logViewerAutoScroll',
  'diagnostics.logViewerShowTimestamp',
};

/// Reads another setting's stored value.
typedef ReadOther = Future<Object?> Function(String key);

/// Works out [Effective] for one registry entry.
typedef EffectiveResolver = Future<Effective> Function(
    SettingEntry entry, Object? stored,
    {required Map<String, Object?> startup, required ReadOther readOther});

bool sameValue(Object? a, Object? b) {
  if (a is num && b is num) return (a.toDouble() - b.toDouble()).abs() < 1e-6;
  return jsonEncode(a) == jsonEncode(b);
}

/// The stored value against a running one, with the reason they differ taken
/// from the apply mode.
Effective compareEffective(
    SettingEntry entry, Object? stored, Object? running, String? note,
    {String source = 'live', bool sameDetail = false}) {
  if (sameValue(stored, running)) {
    return Effective.same(running,
        source: source, detail: sameDetail ? note : null);
  }
  final reason = switch (entry.apply) {
    'restart_app' => 'restart_required',
    'reload_player' => 'reload_required',
    _ => 'runtime_adjusted',
  };
  final base = switch (reason) {
    'restart_required' => 'Stored value changed after the application started.',
    'reload_required' => 'Stored value applies when media is next opened.',
    _ =>
      'The running value differs from the stored one; the player adjusts values to the current state.',
  };
  return Effective.differs(running, reason, note == null ? base : '$base $note',
      source: source);
}

/// What can be said without reading any running component: values loaded at
/// start, values read when a page is created, runtime-only values, and the
/// apply mode. Settings with a running reader get theirs from the host.
Future<Effective> baseEffective(SettingEntry entry, Object? stored,
    {required Map<String, Object?> startup, required ReadOther readOther}) async {
  final key = entry.key;
  if (startupLoadedSettings.contains(key) && startup.containsKey(key)) {
    return compareEffective(entry, stored, startup[key],
        'Loaded when the application started; it is read again at the next start.',
        source: 'startup');
  }
  if (pageLoadedSettings.contains(key)) {
    return const Effective.unknown('loaded_when_page_created',
        'Read when the page or window is created; there is no single running value before then.');
  }
  if (entry.storageKey.startsWith('@runtime:')) {
    return Effective.same(stored);
  }
  switch (entry.apply) {
    case 'reload_player':
      return const Effective.unknown('applies_at_next_open',
          'The stored value is used when media is next opened; the value used by media already open is not recorded.');
    case 'restart_app':
      return const Effective.unknown('no_runtime_probe',
          'Applied at the next application start; the loaded value is not recorded.');
    default:
      return Effective.same(stored, source: 'storage');
  }
}
