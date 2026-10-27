import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/settings_keys.dart';
import '../next/ui/shell/next_ui_preference.dart';
import '../providers/labs_settings_provider.dart';
import 'macos_process_environment.dart';

/// A Classic task belongs to the interface generation in which it started.
/// Switching away and back never revives an old recognition request.
final class ClassicWorkPermit {
  ClassicWorkPermit._(this._generation);
  final int _generation;

  bool get isCurrent =>
      ClassicModePolicy._known &&
      !ClassicModePolicy._nextOpen &&
      _generation == ClassicModePolicy._generation;

  Future<bool> get allowed async {
    await ClassicModePolicy._refresh();
    return isCurrent;
  }
}

abstract final class ClassicModePolicy {
  static bool _nextOpen = false;
  static bool _known = false;
  static int _generation = 0;
  static Object? _binding;
  static Future<void>? _ready;
  static bool Function()? _readLive;

  static bool get classicActive => _known && !_nextOpen;

  /// The shell binds early, before either interface mounts. Startup services
  /// without a shell use the persisted mode instead of assuming Classic.
  static VoidCallback bind(
      LabsSettingsProvider labs, NextUiPreference preference) {
    final owner = Object();
    _known = false;
    _binding = owner;
    _ready = Future.wait([labs.ready, preference.ready]);
    bool read() => NextUiPreference.interfaceOpen(
        nextEnabled: labs.enableAgentEndpoint, preference: preference.enabled);
    _readLive = read;
    var loaded = false;
    void changed() {
      if (identical(_binding, owner) && loaded) _observe(read());
    }

    labs.addListener(changed);
    preference.addListener(changed);
    _ready!.then((_) {
      loaded = true;
      changed();
    });
    return () {
      labs.removeListener(changed);
      preference.removeListener(changed);
      if (identical(_binding, owner)) {
        _known = false;
        _generation++;
        _binding = null;
        _ready = null;
        _readLive = null;
      }
    };
  }

  static void _observe(bool nextOpen) {
    _known = true;
    if (_nextOpen == nextOpen) return;
    _nextOpen = nextOpen;
    _generation++;
  }

  static Future<void> _refresh() async {
    final owner = _binding;
    if (owner != null) {
      await _ready;
      if (!identical(owner, _binding)) return _refresh();
      _observe(_readLive!());
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    final sandboxed = await MacOSProcessEnvironment.isSandboxed();
    if (_binding != null) return _refresh();
    _observe(NextUiPreference.interfaceOpen(
        nextEnabled: !sandboxed &&
            preferences.getBool(SettingsKeys.labsEnableAgentEndpoint) == true,
        preference: preferences.getBool(NextUiPreference.key) == true));
  }

  static Future<ClassicWorkPermit?> acquire() async {
    await _refresh();
    return _nextOpen ? null : ClassicWorkPermit._(_generation);
  }

  static Future<bool> allowsImplicitWork() async => await acquire() != null;
}
