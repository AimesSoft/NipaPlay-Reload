import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/utils/player_kernel_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;

import '../harness_redaction.dart';
import '../tasks/user_consent.dart';
import 'classic_action.dart';
import 'kernel_facts.dart';
import 'player_facts.dart';
import 'video_player_state_port.dart';

/// Asks the person at NipaPlay; [stopped] completes when the question no
/// longer applies (the media or the player changed).
typedef KernelConsent = Future<bool> Function(
    String title, String message, String accept, Future<void> stopped);

/// Replaces the player and reopens what it plays: on [kernel] (null is the
/// kernel setting), with [request]'s own source.
typedef KernelSwitch = Future<void> Function(
    VideoPlayerState state, PlayerKernelType? kernel, PlayableItem? request);

Future<bool> _askUser(
        String title, String message, String accept, Future<void> stopped) =>
    showUserConsent(title, message, accept, stopped: stopped);

/// Classic's own kernel hot swap, serialized with Classic's.
Future<void> classicKernelSwitch(VideoPlayerState state,
        PlayerKernelType? kernel, PlayableItem? request) =>
    PlayerKernelManager.performPlayerKernelHotSwap(state,
        kernelType: kernel, request: request);

/// A kernel value Next changed on one player for one media, and what it
/// was before.
final class _Override {
  _Override(this.name, this.kind, this.original, this.originalKnown,
      this.firstAt);
  final String name;
  final String kind;
  final Object? original;
  final bool originalKnown;
  final DateTime firstAt;
  Object? requested;
  Object? lastSet;
  final changeIds = <String>[];

  JsonMap toJson() => {
        'name': name,
        'kind': kind,
        'original': safeKernelValue(name, original),
        'originalKnown': originalKnown,
        'requested': safeKernelValue(name, requested),
        'current': safeKernelValue(name, lastSet),
        'firstChangedAt': firstAt.toIso8601String(),
        'changeIds': List.of(changeIds),
      };
}

/// The player and the media a set of changes belongs to.
final class _Binding {
  const _Binding(this.player, this.path);
  final Player player;
  final String? path;
  bool same(_Binding other) =>
      identical(player, other.player) && path == other.path;
}

/// Kernel reads and per-playback kernel changes for NipaPlay Next.
///
/// A change holds for the player and media it was made on: a different
/// media restores the values it changed (a value NipaPlay or the user set
/// since is left as it is), a value whose original the kernel never
/// reported makes NipaPlay open the next media on a fresh player, and a
/// player replaced by NipaPlay ends them. Reopening on another kernel holds
/// the same way: the next media opens on the kernel setting. Turning Next
/// off restores all of it. Nothing here writes a setting.
final class KernelControl {
  KernelControl(
    this.state, {
    KernelConsent? consent,
    KernelSwitch? switcher,
    PlayerKernelType Function()? configured,
    List<PlayerKernelType> Function()? supported,
    String? Function()? harness,
  })  : _harness = harness ?? (() => null),
        _consent = consent ?? _askUser,
        _switch = switcher ?? classicKernelSwitch,
        _configured = configured ?? PlayerFactory.getKernelType,
        _supported = supported ?? (() => PlayerFactory.supportedKernelTypes) {
    _deferredSaves = DeferredReloads.changes.listen((_) => _deferredChanged());
  }

  final VideoPlayerState state;
  final String? Function() _harness;
  final KernelConsent _consent;
  final KernelSwitch _switch;
  final PlayerKernelType Function() _configured;
  final List<PlayerKernelType> Function() _supported;

  static const historyCapacity = 200;
  final _overrides = <String, _Override>{};
  final _history = ListQueue<JsonMap>();
  _Binding? _binding;
  JsonMap? _kernelOverride;
  /// A call whose effect may outlast the media (a command, an invoke).
  bool _freshByCall = false;

  /// Settings Next saved that the player in use was not rebuilt for.
  late final StreamSubscription<void> _deferredSaves;
  bool get _pending => DeferredReloads.pendingFor(_configured());

  /// Whether the next media opens on a fresh player: a change whose
  /// original the kernel never reported, a call that may outlast it, or a
  /// setting saved by Next that the player in use does not carry.
  bool get _freshPlayerNext =>
      _freshByCall || _overrides.values.any((o) => !o.originalKnown) || _pending;
  String? _revertFor;
  PlayableItem? _seenRequest;
  bool _listening = false;
  bool _reopening = false;
  Future<void> _work = Future.value();
  ErikaSample? _erikaSample;
  int _sequence = 0;

  /// The changes in force, newest first, and the record of all of them.
  List<JsonMap> get history => List.unmodifiable(_history.toList().reversed);

  _Binding _now() => _Binding(state.player,
      state.lastPlaybackRequest?.videoPath ?? state.currentVideoPath);

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _work.then((_) => run());
    _work = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  void _listen() {
    if (_listening) return;
    _listening = true;
    state.addListener(_changed);
  }

  void _stopListening() {
    if (!_listening) return;
    _listening = false;
    state.removeListener(_changed);
  }

  bool get _holding =>
      _overrides.isNotEmpty ||
      _kernelOverride != null ||
      _revertFor != null ||
      _freshPlayerNext;

  /// A setting Next saved reached the stored values. With no media open the
  /// player is rebuilt now, which interrupts nothing; with media playing it
  /// is left alone and the next media opens on the stored values.
  void _deferredChanged() {
    unawaited(_serial(() async {
      if (!_pending) return;
      if (state.currentVideoPath == null) {
        await _revert('setting_saved');
      } else {
        _seenRequest = state.lastPlaybackRequest;
        _binding ??= _now();
        _listen();
      }
    }));
  }

  void _changed() {
    if (_reopening) return;
    final request = state.lastPlaybackRequest;
    if (!identical(request, _seenRequest)) {
      // Another open began, even of the same path on the same player.
      _seenRequest = request;
      if (_pending && request != null) _revertFor = request.videoPath;
    }
    final binding = _binding;
    final now = _now();
    if (binding != null && !binding.same(now)) {
      _binding = now;
      unawaited(_serial(() => _bindingMoved(binding, now)));
    }
    _checkRevert();
  }

  /// Once the next media has opened (or failed), reopens it on a fresh
  /// player on the kernel setting.
  void _checkRevert() {
    final revert = _revertFor;
    if (revert == null || _reopening) return;
    // Classic's open has settled once it is playing, paused or failed. While
    // it is ready its play() has not taken yet, and a reopen started then
    // would carry the media over as paused.
    if (_now().path == revert &&
        const {PlayerStatus.playing, PlayerStatus.paused, PlayerStatus.error}
            .contains(state.status)) {
      _revertFor = null;
      unawaited(_serial(() => _revert('media_changed')));
    }
  }

  Future<void> _bindingMoved(_Binding from, _Binding to) async {
    if (!identical(from.player, to.player)) {
      for (final override in _overrides.values.toList()) {
        _record('ended', override.name, {
          'trigger': 'player_replaced',
          'original': safeKernelValue(override.name, override.original),
        });
      }
      _overrides.clear();
      _freshByCall = false;
      final kernel = _kernelOverride;
      if (kernel != null &&
          playerKernelId(to.player.getPlayerKernelName()) ==
              kernelIdOf(_configured())) {
        _record('ended', 'kernel', {
          'trigger': 'player_replaced',
          'kernel': kernel['kernel'],
        });
        _kernelOverride = null;
        _revertFor = null;
      }
    } else {
      for (final override in _overrides.values.toList()) {
        if (override.originalKnown) {
          await _restoreOne(override, 'media_changed', null);
        }
      }
      if (_freshPlayerNext || _kernelOverride != null) {
        _revertFor = to.path;
      }
      _overrides.removeWhere((_, o) => o.originalKnown);
    }
    if (!_holding) {
      _binding = null;
      _stopListening();
    }
    scheduleMicrotask(_checkRevert);
  }

  Future<void> _revert(String trigger) async {
    final kernel = _kernelOverride;
    final before = playerKernelId(state.player.getPlayerKernelName());
    String? failure;
    _reopening = true;
    try {
      await _switch(state, null, state.lastPlaybackRequest);
    } catch (error) {
      failure = redactHarnessText('$error');
    } finally {
      _reopening = false;
    }
    for (final override in _overrides.values) {
      _record('ended', override.name, {
        'trigger': 'player_recreated',
        'original': safeKernelValue(override.name, override.original),
      });
    }
    _overrides.clear();
    _freshByCall = false;
    _kernelOverride = null;
    _record('revert', 'kernel', {
      'trigger': trigger,
      'from': before,
      'temporaryKernel': kernel?['kernel'],
      'to': playerKernelId(state.player.getPlayerKernelName()),
      'configured': kernelIdOf(_configured()),
      'error': failure,
    });
    _revertFor = null;
    _seenRequest = state.lastPlaybackRequest;
    _binding = null;
    _stopListening();
  }

  /// Restores every change and returns to the kernel setting; called when
  /// Next is turned off. With [reopen] false the player is left as it is.
  Future<void> release({bool reopen = true}) => _serial(() async {
        if (!reopen) await _deferredSaves.cancel();
        if (reopen) {
          for (final override in _overrides.values.toList()) {
            if (override.originalKnown &&
                identical(_binding?.player, state.player)) {
              await _restoreOne(override, 'next_off', null);
            }
          }
          _overrides.removeWhere((_, o) => o.originalKnown);
          if (_kernelOverride != null ||
              _freshPlayerNext ||
              _overrides.isNotEmpty) {
            await _revert('next_off');
          }
        }
        _overrides.clear();
        _kernelOverride = null;
        _revertFor = null;
        _freshByCall = false;
        _binding = null;
        _stopListening();
      });

  // ---- inputs ----

  JsonMap _snapshot() => VideoPlayerStatePort(state).snapshot().toJson();

  void _session(JsonMap input, {bool required = true}) {
    final sessionId = input['sessionId'];
    if (sessionId == null && !required) return;
    if (sessionId != _snapshot()['sessionId']) {
      throw const Failure(FailureCode.conflict,
          'Playback session changed. Read playback.state.');
    }
  }

  void _internalMedia() {
    if (ExternalPlayerConsoleService.hasActiveSession) {
      throw const Failure(FailureCode.unavailable,
          'An external player is playing; its kernel is not NipaPlay\'s.');
    }
    if (state.currentVideoPath == null &&
        state.lastPlaybackRequest?.videoPath == null) {
      throw const Failure(
          FailureCode.unavailable, 'No internal media is open.');
    }
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';

  JsonMap _record(String action, String name, JsonMap facts,
      {Invocation? invocation}) {
    final entry = <String, Object?>{
      'changeId': _id('kc'),
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'name': name,
      'origin': invocation?.origin ?? 'nipaplay',
      'invocationId': invocation?.id,
      'kernel': playerKernelId(state.player.getPlayerKernelName()),
      'path': _now().path == null ? null : redactHarnessText(_now().path!),
      ...facts,
    };
    _history.add(entry);
    while (_history.length > historyCapacity) {
      _history.removeFirst();
    }
    return entry;
  }

  // ---- reading ----

  Future<Object?> _currentValue(_Override override) async {
    final player = state.player;
    switch (override.kind) {
      case 'mpv':
        return (await player.readNativePropertiesChecked(
                [override.name]))[override.name]
            ?.value;
      case 'mdk':
        return player.getProperty(override.name);
      case 'decoders':
        return player.getDecoders(override.name == 'videoDecoders'
            ? MediaType.video
            : MediaType.audio);
      case 'erika':
        return _erikaSetting(player, override.name);
    }
    return null;
  }

  static Future<String?> _erikaSetting(Player player, String name) async {
    if (name == 'debugHud') return player.debugHudEnabled?.toString();
    final status = await player.getUpscalerStatus();
    return status == null ? null : erikaUpscalerName(status.requestedMode);
  }

  static bool _equal(Object? a, Object? b) => a is List && b is List
      ? a.join('\u0000') == b.join('\u0000')
      : a == b;

  /// playback.kernel: who the kernel is, what it lets Next read and set,
  /// what it reports now, and the changes in force.
  Future<JsonMap> read(JsonMap input) async {
    final snapshot = _snapshot();
    final base = <String, Object?>{
      'sessionId': snapshot['sessionId'],
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'player': snapshot['player'],
    };
    if (snapshot['player'] == 'external') {
      return {...base, 'unavailableReason': 'external_player'};
    }
    final player = state.player;
    final name = player.getPlayerKernelName();
    final kernel = playerKernelId(name);
    final asked = [
      for (final n in (input['properties'] as List? ?? const []).cast<String>())
        n
    ];
    final result = <String, Object?>{
      ...base,
      'kernel': {
        'id': kernel,
        'name': name,
        'configured': kernelIdOf(_configured()),
        'version': null,
      },
      'controls': kernelControls(kernel, _supported()),
    };
    switch (kernel) {
      case 'media_kit':
        final names = {...mpvKernelSnapshot, ...asked}.toList();
        final reads = await player.readNativePropertiesChecked(names);
        String? value(String n) => reads[n]?.value;
        result['kernel'] = {
          ...result['kernel'] as JsonMap,
          'version': {
            'mpv': value('mpv-version'),
            'ffmpeg': value('ffmpeg-version'),
          },
        };
        result['snapshot'] = {
          for (final n in mpvKernelSnapshot) n: safeKernelValue(n, value(n))
        };
        result['properties'] = {
          for (final n in asked)
            n: {
              'value': safeKernelValue(n, value(n)),
              'error': reads[n]?.error,
            }
        };
      case 'mdk':
        result['kernel'] = {
          ...result['kernel'] as JsonMap,
          'version': {'mdk': player.nativeVersion},
        };
        result['snapshot'] = {
          for (final n in mdkKernelSnapshot)
            n: safeKernelValue(n, player.getProperty(n))
        };
        result['decoders'] = {
          'video': player.getDecoders(MediaType.video),
          'audio': player.getDecoders(MediaType.audio),
          'activeVideo': player.getProperty('decoder.video'),
          'activeAudio': player.getProperty('decoder.audio'),
        };
        result['properties'] = {
          for (final n in asked)
            n: {'value': safeKernelValue(n, player.getProperty(n)), 'error': null}
        };
      case 'erika':
        result['erika'] = await _readErika(player, input['sampleMs'] as int?);
        if (asked.isNotEmpty) {
          result['properties'] = {
            for (final n in asked)
              n: {'value': null, 'error': 'Erika has no named properties.'}
          };
        }
      default:
        if (asked.isNotEmpty) {
          result['properties'] = {
            for (final n in asked)
              n: {'value': null, 'error': 'This kernel reports no properties.'}
          };
        }
    }
    result['overrides'] = [for (final o in _overrides.values) o.toJson()];
    result['kernelOverride'] = _kernelOverride;
    result['nextMediaOpensFreshPlayer'] =
        _freshPlayerNext || _kernelOverride != null;
    final history = _history.toList().reversed.toList();
    result['changes'] = history.take(20).toList();
    result['changesTotal'] = history.length;
    return result;
  }

  Future<JsonMap> _readErika(Player player, int? sampleMs) async {
    final instance = player.kernelInstance;
    final path = _now().path;
    var status = await player.readKernelStatus();
    ErikaSample? sample(JsonMap status) {
      final stats = status['presenterStats'];
      final at = status['presenterStatsAt'];
      return stats is Map && at is String
          ? ErikaSample(DateTime.parse(at), instance, path,
              {for (final e in stats.entries) '${e.key}': e.value})
          : null;
    }

    var previous = _erikaSample;
    var source = 'previous_read';
    if (sampleMs != null) {
      previous = sample(status);
      await Future<void>.delayed(Duration(milliseconds: sampleMs));
      status = await player.readKernelStatus();
      source = 'sampled';
    }
    final current = sample(status);
    ({JsonMap? window, String? reason}) window =
        (window: null, reason: 'stats_unavailable');
    if (current != null) {
      window = erikaWindow(previous, current, source: source);
      _erikaSample = current;
    }
    return erikaKernelFacts(status,
        window: window.window == null
            ? null
            : {...window.window!, 'paused': state.isPaused},
        windowUnavailable: window.reason);
  }

  // ---- setting ----

  /// playback.set_kernel_properties.
  Future<JsonMap> set(JsonMap input, Invocation invocation) => _serial(() async {
        _session(input);
        _internalMedia();
        final player = state.player;
        final kernel = playerKernelId(player.getPlayerKernelName());
        final properties = <String, String>{};
        for (final entry
            in ((input['properties'] as Map?) ?? const {}).entries) {
          final value = entry.value;
          if (value is! String) {
            throw Failure(FailureCode.invalidInput,
                'properties.${entry.key} must be a string.');
          }
          properties['${entry.key}'] = value;
        }
        final decoders = <String, List<String>>{
          for (final key in const ['videoDecoders', 'audioDecoders'])
            if (input[key] is List)
              key: [for (final d in input[key] as List) '$d'],
        };
        if (properties.isEmpty && decoders.isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'Give properties, videoDecoders or audioDecoders.');
        }
        switch (kernel) {
          case 'media_kit':
            if (decoders.isNotEmpty) {
              throw const Failure(FailureCode.invalidInput,
                  'Media Kit has no decoder list; mpv picks its decoder through properties such as hwdec and vd.');
            }
          case 'mdk':
            break;
          case 'erika':
            if (decoders.isNotEmpty) {
              throw const Failure(FailureCode.invalidInput,
                  'Erika takes no decoder list.');
            }
            for (final entry in properties.entries) {
              final values = erikaKernelSettings[entry.key];
              if (values == null || !values.contains(entry.value)) {
                throw Failure(FailureCode.invalidInput,
                    'Erika takes ${erikaKernelSettings.entries.map((e) => '${e.key} (${e.value.join('/')})').join(', ')}.');
              }
            }
          default:
            throw const Failure(FailureCode.unavailable,
                'This kernel takes no properties.');
        }
        final network = {
          for (final entry in properties.entries)
            if (kernelSettingConsent(entry.key, entry.value) != null)
              entry.key: entry.value
        };
        final consent = network.isEmpty
            ? 'not_needed'
            : await _askNetwork([
                for (final entry in network.entries)
                  '· ${entry.key}：${redactHarnessText(entry.value)}',
              ], network.keys.join(','), {
                'requested': {
                  for (final e in network.entries)
                    e.key: safeKernelValue(e.key, e.value)
                },
              }, invocation);
        _bindHere();
        final changes = <JsonMap>[];
        for (final entry in properties.entries) {
          changes.add(await _apply(player, kernel!, entry.key, entry.value,
              invocation,
              consent: network.containsKey(entry.key) ? consent : null));
        }
        for (final entry in decoders.entries) {
          changes.add(await _apply(player, 'decoders', entry.key, entry.value,
              invocation));
        }
        if (!_holding) {
          _binding = null;
          _stopListening();
        }
        return {
          'sessionId': _snapshot()['sessionId'],
          'kernel': {'id': kernel, 'name': player.getPlayerKernelName()},
          'changes': changes,
          'overrides': [for (final o in _overrides.values) o.toJson()],
          'nextMediaOpensFreshPlayer':
              _freshPlayerNext || _kernelOverride != null,
        };
      });

  Future<JsonMap> _apply(Player player, String kind, String name,
      Object value, Invocation invocation,
      {String? consent}) async {
    final kindName = switch (kind) {
      'media_kit' => 'mpv',
      'mdk' => 'mdk',
      'erika' => 'erika',
      _ => 'decoders',
    };
    final probe = _Override(name, kindName, null, true, DateTime.now().toUtc());
    Object? before;
    String? beforeError;
    if (kindName == 'mpv') {
      final read =
          (await player.readNativePropertiesChecked([name]))[name];
      before = read?.value;
      beforeError = read?.error;
    } else {
      before = await _currentValue(probe);
    }
    String? error;
    try {
      switch (kindName) {
        case 'mpv':
          error = await player.writeNativeProperty(name, value as String);
        case 'mdk':
          player.setProperty(name, value as String);
        case 'decoders':
          player.setDecoders(
              name == 'videoDecoders' ? MediaType.video : MediaType.audio,
              value as List<String>);
        case 'erika':
          if (name == 'debugHud') {
            await player.setDebugHud(value == 'true');
          } else {
            await player.setUpscaler(erikaUpscalerMode(value as String));
          }
      }
    } catch (e) {
      error = redactHarnessText('$e');
    }
    final after = await _currentValue(probe);
    final applied = error == null;
    if (applied) {
      final known = kindName == 'mpv' ? beforeError == null : before != null;
      _noteOverride(name, kindName, before, known, value, after);
    }
    final entry = _record('set', name, {
      'before': safeKernelValue(name, before),
      if (beforeError != null) 'beforeError': beforeError,
      'requested': safeKernelValue(name, value),
      'after': safeKernelValue(name, after),
      'error': error,
      'consent': consent,
    }, invocation: invocation);
    if (applied) _overrides[name]!.changeIds.add(entry['changeId'] as String);
    return {
      'changeId': entry['changeId'],
      'name': name,
      'before': entry['before'],
      if (beforeError != null) 'beforeError': beforeError,
      'requested': entry['requested'],
      'after': entry['after'],
      'error': error,
      'restorable': applied ? _overrides[name]!.originalKnown : null,
      if (consent != null) 'consent': consent,
    };
  }

  /// Puts [override]'s original back when the kernel still holds what Next
  /// set; anything else is left as found.
  Future<JsonMap> _restoreOne(
      _Override override, String trigger, Invocation? invocation) async {
    final player = state.player;
    final current = await _currentValue(override);
    JsonMap result;
    if (!override.originalKnown) {
      result = {'restored': false, 'reason': 'original_unknown'};
    } else if (_equal(current, override.original)) {
      _overrides.remove(override.name);
      result = {'restored': true, 'alreadyOriginal': true};
    } else if (!_equal(current, override.lastSet)) {
      _overrides.remove(override.name);
      result = {'restored': false, 'reason': 'changed_since'};
    } else {
      String? error;
      try {
        final original = override.original;
        switch (override.kind) {
          case 'mpv':
            error = await player.writeNativeProperty(
                override.name, original as String? ?? '');
          case 'mdk':
            player.setProperty(override.name, original as String);
          case 'decoders':
            player.setDecoders(
                override.name == 'videoDecoders'
                    ? MediaType.video
                    : MediaType.audio,
                (original as List).cast<String>());
          case 'erika':
            if (override.name == 'debugHud') {
              await player.setDebugHud(original == 'true');
            } else {
              await player.setUpscaler(erikaUpscalerMode(original as String));
            }
        }
      } catch (e) {
        error = redactHarnessText('$e');
      }
      _overrides.remove(override.name);
      result = {'restored': error == null, if (error != null) 'error': error};
    }
    final after = await _currentValue(override);
    final entry = _record('restore', override.name, {
      'trigger': trigger,
      'before': safeKernelValue(override.name, current),
      'original': safeKernelValue(override.name, override.original),
      'after': safeKernelValue(override.name, after),
      ...result,
    }, invocation: invocation);
    return {
      'changeId': entry['changeId'],
      'name': override.name,
      'before': entry['before'],
      'original': entry['original'],
      'after': entry['after'],
      ...result,
    };
  }

  /// playback.restore_kernel_properties.
  Future<JsonMap> restore(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _session(input, required: false);
        final binding = _binding;
        if (binding != null && !binding.same(_now())) {
          await _bindingMoved(binding, _now());
          _binding = _holding ? _now() : null;
        }
        final names = (input['names'] as List?)?.cast<String>() ??
            _overrides.keys.toList();
        final results = <JsonMap>[];
        for (final name in names) {
          final override = _overrides[name];
          if (override == null) {
            results.add({'name': name, 'restored': false, 'reason': 'not_changed'});
            continue;
          }
          results.add(await _restoreOne(override, 'requested', invocation));
        }

        if (!_holding) {
          _binding = null;
          _stopListening();
        }
        return {
          'restored': results,
          'overrides': [for (final o in _overrides.values) o.toJson()],
          'nextMediaOpensFreshPlayer':
              _freshPlayerNext || _kernelOverride != null,
        };
      });

  /// Asks the person at NipaPlay about [lines]; the answer, or a refusal
  /// recorded and thrown. The question goes away when the media or the
  /// player changes.
  Future<String> _askNetwork(List<String> lines, String name, JsonMap facts,
      Invocation invocation) async {
    final started = _now();
    final stopped = Completer<void>();
    void watch() {
      if (!_now().same(started) && !stopped.isCompleted) stopped.complete();
    }

    state.addListener(watch);
    bool approved;
    try {
      approved = await _consent(
          '播放器网络设置',
          ['这次播放将使用：', ...lines, '换到其他视频时恢复。'].join('\n'),
          '允许',
          stopped.future);
    } finally {
      state.removeListener(watch);
    }
    if (!approved) {
      _record('declined', name, facts, invocation: invocation);
      throw const Failure(FailureCode.conflict, '用户没有同意这次播放使用这些网络设置');
    }
    if (!_now().same(started)) {
      throw const Failure(
          FailureCode.conflict, 'Playback changed while waiting for the user.');
    }
    return 'user_approved';
  }

  /// Changes made now belong to this player and media. (While listening,
  /// a move was already queued ahead of this work by [_changed].)
  void _bindHere() {
    _binding = _now();
    _listen();
  }

  void _unbindIfIdle() {
    if (!_holding) {
      _binding = null;
      _stopListening();
    }
  }

  /// Records [name] as changed from [before] (known when the kernel reported
  /// it) to [after].
  _Override _noteOverride(String name, String kind, Object? before,
      bool known, Object? requested, Object? after) {
    final override = _overrides.putIfAbsent(
        name, () => _Override(name, kind, before, known, DateTime.now().toUtc()));
    override.requested = requested;
    override.lastSet = after;

    return override;
  }

  // ---- passing through ----

  /// playback.kernel_command.
  Future<JsonMap> command(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _session(input);
        _internalMedia();
        final player = state.player;
        final kernel = playerKernelId(player.getPlayerKernelName());
        if (kernel != 'media_kit') {
          throw Failure(FailureCode.unavailable,
              'Only Media Kit runs mpv commands; this player runs $kernel.');
        }
        final args = [for (final a in input['command'] as List) '$a'];
        final body = mpvCommandBody(args);
        if (body.isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'command needs a command name.');
        }
        if (body.first == 'load-script') {
          final harness = _harness();
          final script = body.length > 1 ? body[1] : '';
          if (harness == null) {
            throw const Failure(FailureCode.unavailable,
                'load-script takes a script in the harness repository; none is open.');
          }
          var resolved = p.normalize(p.absolute(script));
          try {
            resolved = await File(resolved).resolveSymbolicLinks();
          } catch (_) {}
          var root = p.normalize(p.absolute(harness));
          try {
            root = await Directory(root).resolveSymbolicLinks();
          } catch (_) {}
          if (!p.isWithin(root, resolved)) {
            throw Failure(FailureCode.invalidInput,
                'load-script takes a script in the harness repository ($root).');
          }
        }
        final safeCommand = [for (final a in args) redactHarnessText(a)];
        final consent = kernelCommandConsent(args) == null
            ? 'not_needed'
            : await _askNetwork(['· ${safeCommand.join(' ')}'], body.first,
                {'command': safeCommand}, invocation);
        _bindHere();
        final property = mpvCommandProperty(args);
        ({String? value, String? error})? before;
        if (property != null) {
          before = (await player.readNativePropertiesChecked([property]))[property];
        }
        final reply = await player.runNativeCommand(args,
            timeout: Duration(milliseconds: input['timeoutMs'] as int? ?? 10000));
        String? after;
        if (property != null) {
          after = (await player.readNativePropertiesChecked([property]))[property]
              ?.value;
        }
        final lasting = property != null
            ? 'property'
            : mpvTransientCommands.contains(body.first)
                ? 'none'
                : 'unknown';
        _Override? override;
        if (reply.error == null) {
          if (property != null) {
            override = _noteOverride(property, 'mpv', before?.value,
                before?.error == null, safeCommand.join(' '), after);
          } else if (lasting == 'unknown') {
            _freshByCall = true;
          }
        }
        final sessionId = _snapshot()['sessionId'] as String;
        final playerError = playbackErrorFacts(state, sessionId);
        final entry = _record('command', property ?? body.first, {
          'command': safeCommand,
          'result': safeKernelResult(reply.result),
          'error': reply.error,
          if (property != null) ...{
            'property': property,
            'before': safeKernelValue(property, before?.value),
            'after': safeKernelValue(property, after),
          },
          'lasting': lasting,
          'consent': consent,
          if (playerError != null) 'playerError': playerError['message'],
        }, invocation: invocation);
        override?.changeIds.add(entry['changeId'] as String);
        _unbindIfIdle();
        return {
          'changeId': entry['changeId'],
          'sessionId': sessionId,
          'command': safeCommand,
          'result': entry['result'],
          'error': reply.error,
          if (property != null)
            'property': {
              'name': property,
              'before': entry['before'],
              'after': entry['after'],
              'restorable': override?.originalKnown,
            },
          'lasting': lasting,
          'consent': consent,
          'playerError': playerError,
          'nextMediaOpensFreshPlayer':
              _freshPlayerNext || _kernelOverride != null,
        };
      });

  /// playback.kernel_invoke.
  Future<JsonMap> invoke(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _session(input);
        _internalMedia();
        final player = state.player;
        final kernel = playerKernelId(player.getPlayerKernelName());
        if (kernel != 'erika') {
          throw Failure(FailureCode.unavailable,
              'Only Erika takes invoke; this player runs $kernel.');
        }
        final method = input['method'] as String;
        final arguments = <String, Object?>{
          for (final e in ((input['arguments'] as Map?) ?? const {}).entries)
            '${e.key}': e.value
        };
        final consent = kernelInvokeConsent(arguments) == null
            ? 'not_needed'
            : await _askNetwork([
                '· $method ${redactHarnessText(jsonEncode(arguments))}'
              ], method, {
                'arguments': safeKernelResult(arguments)
              }, invocation);
        _bindHere();
        final reply = await player.invokeNative(method, arguments);
        final reading = method.startsWith('get') ||
            const {'tracks', 'danmakuTracks'}.contains(method);
        if (reply.error == null && reply.supported && !reading) {
          _freshByCall = true;
        }
        final sessionId = _snapshot()['sessionId'] as String;
        final playerError = playbackErrorFacts(state, sessionId);
        final entry = _record('invoke', method, {
          'arguments': safeKernelResult(arguments),
          'supported': reply.supported,
          'result': safeKernelResult(reply.result),
          'error': reply.error,
          'consent': consent,
          if (playerError != null) 'playerError': playerError['message'],
        }, invocation: invocation);
        _unbindIfIdle();
        return {
          'changeId': entry['changeId'],
          'sessionId': sessionId,
          'method': method,
          'supported': reply.supported,
          'result': entry['result'],
          'error': reply.error,
          'consent': consent,
          'playerError': playerError,
          'nextMediaOpensFreshPlayer':
              _freshPlayerNext || _kernelOverride != null,
        };
      });

  /// playback.watch_kernel_properties: what the named properties were, and
  /// each change seen over a bounded time, read every [intervalMs].
  Future<JsonMap> watch(JsonMap input) async {
    final snapshot = _snapshot();
    if (snapshot['player'] == 'external') {
      throw const Failure(FailureCode.unavailable,
          'An external player is playing; its kernel is not NipaPlay\'s.');
    }
    final player = state.player;
    final kernel = playerKernelId(player.getPlayerKernelName());
    if (kernel != 'media_kit' && kernel != 'mdk') {
      throw Failure(FailureCode.unavailable,
          'Named properties are watched on Media Kit and MDK; this player runs $kernel.');
    }
    final names = [for (final n in input['properties'] as List) '$n'];
    final duration = input['durationMs'] as int? ?? 0;
    final interval = input['intervalMs'] as int? ?? 250;
    Future<Map<String, ({String? value, String? error})>> sample() async =>
        kernel == 'mdk'
            ? {for (final n in names) n: (value: player.getProperty(n), error: null)}
            : await player.readNativePropertiesChecked(names);
    JsonMap values(Map<String, ({String? value, String? error})> read) => {
          for (final n in names)
            n: {
              'value': safeKernelValue(n, read[n]?.value),
              'error': read[n]?.error,
            }
        };
    final started = _now();
    final startedAt = DateTime.now().toUtc();
    final clock = Stopwatch()..start();
    final initial = await sample();
    var previous = initial;
    final changes = <JsonMap>[];
    var samples = 1;
    var endedBy = 'duration';
    while (clock.elapsedMilliseconds < duration) {
      await Future<void>.delayed(Duration(
          milliseconds: (duration - clock.elapsedMilliseconds).clamp(1, interval)));
      final now = _now();
      if (!now.same(started)) {
        endedBy = identical(now.player, started.player)
            ? 'media_changed'
            : 'player_replaced';
        break;
      }
      final current = await sample();
      samples++;
      for (final n in names) {
        if (current[n]?.value != previous[n]?.value ||
            current[n]?.error != previous[n]?.error) {
          changes.add({
            'at': DateTime.now().toUtc().toIso8601String(),
            'elapsedMs': clock.elapsedMilliseconds,
            'name': n,
            'value': safeKernelValue(n, current[n]?.value),
            'error': current[n]?.error,
          });
        }
      }
      previous = current;
      if (changes.length >= 500) {
        endedBy = 'change_limit';
        break;
      }
    }
    return {
      'sessionId': snapshot['sessionId'],
      'kernel': kernel,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'elapsedMs': clock.elapsedMilliseconds,
      'intervalMs': interval,
      'samples': samples,
      'initial': values(initial),
      'changes': changes,
      'final': values(previous),
      'endedBy': endedBy,
    };
  }

  // ---- reopening ----

  /// playback.reopen_with_kernel.
  Future<JsonMap> reopen(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _session(input);
        _internalMedia();
        final id = input['kernel'] as String;
        final target = kernelTypesById[id]!;
        final supported = _supported();
        if (!supported.contains(target)) {
          throw Failure(FailureCode.unavailable,
              'This device cannot run $id; it runs ${supported.map(kernelIdOf).join(', ')}.');
        }
        final before = _playbackFacts();
        final previous = state.player;
        for (final override in _overrides.values) {
          _record('ended', override.name, {
            'trigger': 'player_replaced',
            'original': safeKernelValue(override.name, override.original),
          }, invocation: invocation);
        }
        _overrides.clear();
        _freshByCall = false;
        _revertFor = null;
        String? failure;
        _reopening = true;
        try {
          await _switch(state, target, state.lastPlaybackRequest);
        } catch (error) {
          failure = redactHarnessText('$error');
        } finally {
          _reopening = false;
        }
        final replaced = !identical(previous, state.player);
        final tracks = replaced && state.hasVideo
            ? await _restoreTracks(before)
            : const <String, Object?>{};
        if (replaced && state.hasVideo) {
          await _settle(paused: before['paused'] == true);
        }
        final after = _playbackFacts();
        final actual = playerKernelId(state.player.getPlayerKernelName());
        final configured = kernelIdOf(_configured());
        _kernelOverride = replaced && actual != configured
            ? {
                'kernel': actual,
                'configured': configured,
                'path': after['path'],
                'at': DateTime.now().toUtc().toIso8601String(),
                'origin': invocation.origin,
              }
            : null;
        // What this player was not built from still waits for the next media.
        final holding = _kernelOverride != null || _pending;
        _seenRequest = state.lastPlaybackRequest;
        _binding = holding ? _now() : null;
        holding ? _listen() : _stopListening();
        final opened = replaced && failure == null && state.hasVideo;
        final error = playbackErrorFacts(state, _snapshot()['sessionId'] as String);
        _record('reopen', 'kernel', {
          'requested': id,
          'actual': actual,
          'configured': configured,
          'opened': opened,
          'error': failure ?? (error?['message']),
        }, invocation: invocation);
        return {
          'kernel': {
            'requested': id,
            'actual': actual,
            'name': state.player.getPlayerKernelName(),
            'configured': configured,
          },
          'replaced': replaced,
          'opened': opened,
          'failure': failure,
          'error': error,
          'preserved': {
            for (final key in const ['positionMs', 'paused', 'rate'])
              key: {'before': before[key], 'after': after[key]},
            ...tracks,
          },
          'nextMediaOpensConfiguredKernel': _kernelOverride != null || _pending,
          'state': _snapshot(),
        };
      });

  /// Classic's play() and pause() set the status only once the kernel
  /// answers, so the state right after a reopen can still be the one before.
  /// Waits, up to two seconds, until the status has settled and, when the
  /// media was paused, until the new player is paused too.
  Future<void> _settle({required bool paused}) async {
    final until = DateTime.now().add(const Duration(seconds: 2));
    bool settled() =>
        state.status == PlayerStatus.error ||
        (paused
            ? state.status == PlayerStatus.paused
            : const {PlayerStatus.playing, PlayerStatus.paused}
                .contains(state.status));
    while (!settled() && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  JsonMap _playbackFacts() {
    final info = state.player.mediaInfo;
    JsonMap? describe(List<Object?>? tracks, int? index) {
      if (tracks == null || index == null || index < 0 || index >= tracks.length) {
        return null;
      }
      final track = tracks[index];
      return switch (track) {
        PlayerAudioStreamInfo t => {
            'index': index,
            'title': t.title,
            'language': t.language,
            'codec': t.codec.name,
          },
        PlayerSubtitleStreamInfo t => {
            'index': index,
            'title': t.title,
            'language': t.language,
          },
        _ => {'index': index},
      };
    }

    final path = _now().path;
    return {
      'path': path == null ? null : redactHarnessText(path),
      'positionMs': state.position.inMilliseconds,
      'paused': state.isPaused,
      'rate': state.playbackRate,
      'audio': describe(info.audio, state.player.activeAudioTracks.firstOrNull),
      'audioCount': info.audio?.length ?? 0,
      'subtitle': describe(
          info.subtitle, state.player.activeSubtitleTracks.firstOrNull),
      'subtitleCount': info.subtitle?.length ?? 0,
      'externalSubtitles': List.of(state.activeExternalSubtitlePaths),
    };
  }

  /// The same track on the new kernel: one with the same language, title
  /// (and codec for audio), else the same index when both list as many.
  static int? _match(JsonMap? before, List<Object?>? tracks, int beforeCount) {
    if (before == null || tracks == null) return null;
    final candidates = <int>[];
    for (var i = 0; i < tracks.length; i++) {
      final track = tracks[i];
      final (title, language, codec) = switch (track) {
        PlayerAudioStreamInfo t => (t.title, t.language, t.codec.name),
        PlayerSubtitleStreamInfo t => (t.title, t.language, null),
        _ => (null, null, null),
      };
      if (title == before['title'] &&
          language == before['language'] &&
          (codec == null || before['codec'] == null || codec == before['codec'])) {
        candidates.add(i);
      }
    }
    if (candidates.length == 1) return candidates.single;
    final index = before['index'] as int;
    return tracks.length == beforeCount && index < tracks.length ? index : null;
  }

  Future<JsonMap> _restoreTracks(JsonMap before) async {
    final info = state.player.mediaInfo;
    final out = <String, Object?>{};
    final audioBefore = before['audio'] as JsonMap?;
    final audioNow = state.player.activeAudioTracks.firstOrNull;
    final audio = _match(audioBefore, info.audio,
        (before['audioCount'] as int?) ?? (info.audio?.length ?? 0));
    var audioApplied = false;
    if (audio != null && audio != audioNow) {
      state.selectEmbeddedAudioTrack(audio);
      audioApplied = true;
    }
    out['audioTrack'] = {
      'before': audioBefore,
      'after': audio ?? audioNow,
      'reapplied': audioApplied,
      if (audioBefore != null && audio == null) 'reason': 'no_matching_track',
    };
    final subtitleBefore = before['subtitle'] as JsonMap?;
    final subtitleNow = state.player.activeSubtitleTracks.firstOrNull;
    final subtitle = _match(subtitleBefore, info.subtitle,
        (before['subtitleCount'] as int?) ?? (info.subtitle?.length ?? 0));
    var subtitleApplied = false;
    if (subtitle != null && subtitle != subtitleNow) {
      state.player.activeSubtitleTracks = [subtitle];
      state.onSubtitleTrackChanged();
      subtitleApplied = true;
    }
    out['subtitleTrack'] = {
      'before': subtitleBefore,
      'after': subtitle ?? subtitleNow,
      'reapplied': subtitleApplied,
      if (subtitleBefore != null && subtitle == null)
        'reason': 'no_matching_track',
    };
    final externalBefore =
        (before['externalSubtitles'] as List).cast<String>();
    final readded = <String>[];
    for (final path in externalBefore) {
      if (!state.activeExternalSubtitlePaths.contains(path) &&
          await File(path).exists()) {
        await state.addNextSubtitle(path, p.basename(path));
        readded.add(path);
      }
    }
    out['externalSubtitles'] = {
      'before': [for (final s in externalBefore) redactHarnessText(s)],
      'after': [
        for (final s in state.activeExternalSubtitlePaths) redactHarnessText(s)
      ],
      'readded': [for (final s in readded) redactHarnessText(s)],
    };
    return out;
  }
}

/// playback.kernel and the per-playback kernel changes.
final class KernelControlCapability implements Capability {
  KernelControlCapability(KernelControl control)
      : actions = [
          ClassicAction(
              const ActionSpec(
                  id: 'playback.kernel',
                  title: 'Read the player kernel',
                  description:
                      'Read the kernel under the internal player, asked at call time: kernel (id mdk/media_kit/video_player/erika, name, configured = the kernel setting, version: mpv and ffmpeg for Media Kit, mdk for MDK, null where the kernel gives none), controls (what this kernel lets set_kernel_properties change and which kernels reopen_with_kernel can use here), snapshot (Media Kit: a fixed list of mpv properties; MDK: a fixed list of MDK properties, which MDK reports only once set on this player), properties (the names asked for in properties: value and the kernel\'s own error), decoders (MDK: the ordered video/audio decoder lists and the decoders opened), erika (Erika: decoder backend from its last decoder event with hardware and fellBack read off it, frame, audio and HDR counters, output, resources, upscaler, tracks, debug HUD; counters are cumulative, window gives their change since the previous playback.kernel read of the same player and media, or over sampleMs when given; notReported lists what Erika does not expose). A value the kernel does not give is null. overrides are the changes in force, kernelOverride a reopen on a kernel other than the setting, changes the last 20 records (who, when, before, requested, after). Values are redacted.',
                  effect: Effect.read,
                  input: ObjectSchema({
                    'properties': ArraySchema(StringSchema(minLength: 1),
                        minItems: 1, maxItems: 100),
                    'sampleMs': IntegerSchema(minimum: 500, maximum: 10000),
                  }),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, _) => control.read(input)),
          ClassicAction(
              const ActionSpec(
                  id: 'playback.set_kernel_properties',
                  title: 'Change kernel properties for this playback',
                  description:
                      'Set kernel values on the current player for the media playing now. properties: Media Kit takes any mpv property (applied through mpv now, not made an option of later files); MDK takes any player property (MDK applies many when a stream or decoder opens); Erika takes upscaler (off/artCnnC4F16/artCnnC4F32/artCnnC4F16Ds) and debugHud (true/false). videoDecoders/audioDecoders: MDK\'s ordered decoder lists. Each change reports before, requested, after (read back from the kernel) and the kernel\'s error, and is recorded with origin and time. A change holds until another media opens: then NipaPlay puts back the original when the kernel still holds the value set here (a value changed since is left), and when the kernel never reported the original (restorable=false) the next media opens on a fresh player. playback.retry keeps the same player and the changes; turning Next off restores them. Settings that can send traffic or credentials elsewhere (proxy, user agent, headers, cookies, referrer, TLS trust, option text such as stream-lavf-o that sets one of these, or a value holding an address) wait for the person at NipaPlay to allow them; a refusal fails with 用户没有同意这次播放使用这些网络设置 and changes nothing. Settings stay as they are; lasting changes are made with settings.set.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': StringSchema(minLength: 1),
                    'properties': ObjectSchema({}, additionalProperties: true),
                    'videoDecoders':
                        ArraySchema(StringSchema(minLength: 1), minItems: 1),
                    'audioDecoders':
                        ArraySchema(StringSchema(minLength: 1), minItems: 1),
                  }, required: [
                    'sessionId'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              control.set),
          ClassicAction(
              const ActionSpec(
                  id: 'playback.restore_kernel_properties',
                  title: 'Restore kernel properties',
                  description:
                      'Put back the originals of kernel values set by set_kernel_properties on the current player: names (property names, videoDecoders, audioDecoders), all when omitted. A value the kernel no longer holds as set (changed since) is left and reported changed_since; one whose original the kernel never reported stays and is reported original_unknown. Each restore is recorded.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': StringSchema(minLength: 1),
                    'names': ArraySchema(StringSchema(minLength: 1), minItems: 1),
                  }),
                  output: ObjectSchema({}, additionalProperties: true)),
              control.restore),
          ClassicAction(
              const ActionSpec(
                  id: 'playback.kernel_command',
                  title: 'Run an mpv command',
                  description:
                      'Media Kit only. Runs command, an mpv command as an array of strings passed to mpv as given (name first, mpv prefixes allowed), on the current player, and returns mpv\'s result data (strings, numbers, flags, lists, maps; byte output read as UTF-8) or mpv\'s own error text, with the playback error when the player reports one afterwards. Any command runs, including filters (vf, af), shaders through change-list glsl-shaders, run and subprocess; load-script takes a script inside the harness repository. A command that changes a property (set, add, cycle, cycle-values, multiply, change-list, vf, af) reports the property before and after and holds like set_kernel_properties: restored when another media opens, restorable through restore_kernel_properties. lasting is property, none (nothing stays past this file) or unknown; after an unknown one (load-script, loadfile, playlist commands, apply-profile and others) the next media opens on a fresh player. A command that sends traffic or credentials elsewhere (an address or a proxy, header, cookie, user agent or referrer among its arguments, or such a property) waits for the person at NipaPlay; run and subprocess do not wait. timeoutMs (default 10000) bounds the wait for mpv\'s answer; the command itself keeps running past it. Every call is recorded (who, when, command, before, result, error).',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': StringSchema(minLength: 1),
                    'command': ArraySchema(StringSchema(),
                        minItems: 1, maxItems: 64),
                    'timeoutMs': IntegerSchema(minimum: 100, maximum: 120000),
                  }, required: [
                    'sessionId',
                    'command'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              control.command),
          ClassicAction(
              const ActionSpec(
                  id: 'playback.kernel_invoke',
                  title: 'Invoke an Erika method',
                  description:
                      'Erika only. Hands method and arguments to Erika as they are: to erika_flutter\'s own invoke when the installed erika_flutter has one, else over its method channel with this player\'s id (on Linux the channel passes methods it does not know to Erika\'s JSON entry). Returns Erika\'s result, or supported=false when this Erika has no such method on this platform, Erika\'s own error, and the playback error when the player reports one afterwards. After a method not named get… (or tracks, danmakuTracks) succeeds, the next media opens on a fresh player. Arguments that name or hold a network setting or an address wait for the person at NipaPlay. Every call is recorded.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': StringSchema(minLength: 1),
                    'method': StringSchema(minLength: 1),
                    'arguments': ObjectSchema({}, additionalProperties: true),
                  }, required: [
                    'sessionId',
                    'method'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              control.invoke),
          ClassicAction(
              const ActionSpec(
                  id: 'playback.watch_kernel_properties',
                  title: 'Watch kernel properties',
                  description:
                      'Media Kit and MDK. Reads properties (mpv properties; MDK properties set on this player) once, then every intervalMs (default 250) for durationMs (default 0 = read once and end; at most 30000), and returns initial and final values (with the kernel\'s error) and each change seen (at, elapsedMs, name, value, error). Ends early when the media or the player changes (endedBy media_changed / player_replaced) or after 500 changes; otherwise endedBy=duration. Nothing keeps watching after the call returns. Values are redacted.',
                  effect: Effect.read,
                  input: ObjectSchema({
                    'properties': ArraySchema(StringSchema(minLength: 1),
                        minItems: 1, maxItems: 20),
                    'durationMs': IntegerSchema(minimum: 0, maximum: 30000),
                    'intervalMs': IntegerSchema(minimum: 100, maximum: 5000),
                  }, required: [
                    'properties'
                  ]),
                  output: ObjectSchema({}, additionalProperties: true)),
              (input, _) => control.watch(input)),
          ClassicAction(
              ActionSpec(
                  id: 'playback.reopen_with_kernel',
                  title: 'Reopen this media on another kernel',
                  description:
                      'Replace the player with one on kernel and reopen the current media at its position, through Classic\'s kernel switch, without changing the kernel setting. Pause, rate, the audio and subtitle track (matched by language, title and codec, else index) and mounted external subtitles are carried over. Reports the kernel requested, the one actually running (a kernel this device cannot run is refused), whether it opened, the playback error, and each carried value before and after. Changes made by set_kernel_properties end with the old player. The next media opens on the kernel setting again.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': const StringSchema(minLength: 1),
                    'kernel': StringSchema(values: kernelTypesById.keys.toList()),
                  }, required: [
                    'sessionId',
                    'kernel'
                  ]),
                  output: const ObjectSchema({}, additionalProperties: true)),
              control.reopen),
        ];

  @override
  final List<Action> actions;
}
