import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart'
    show PlayerKernelType;
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:path/path.dart' as p;

import '../harness_redaction.dart';
import '../player/core/host.dart';
import '../player/core/session.dart';
import '../player/kernel/driver.dart';
import '../player/kernel/native.dart';
import '../player/next_playback.dart';
import '../tasks/user_consent.dart';
import 'classic_action.dart';
import 'kernel_facts.dart';

/// Asks the person at NipaPlay; [stopped] completes when the question no
/// longer applies (the media or the kernel changed).
typedef KernelConsent = Future<bool> Function(
    String title, String message, String accept, Future<void> stopped);

Future<bool> _askUser(
        String title, String message, String accept, Future<void> stopped) =>
    showUserConsent(title, message, accept, stopped: stopped);

/// A kernel value Next changed on one kernel instance, and what it was
/// before.
final class _Override {
  _Override(
      this.name, this.kind, this.original, this.originalKnown, this.firstAt);
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

/// Kernel reads and per-playback kernel changes for NipaPlay Next, over
/// Next's own playback layer: the kernel instance of the session that plays
/// now, through the handle it gives ([KernelNative], queued and fenced like
/// its own calls), never the kernel itself (I3).
///
/// A change holds for the kernel instance it was made on: the next media
/// opens a new instance on the settings (D6), and a swap to another kernel
/// is another instance, so either ends the changes (they are recorded as
/// ended). Nothing here writes a setting.
final class KernelControl {
  KernelControl(
    this.host,
    this.playback, {
    KernelConsent? consent,
    String? Function()? harness,
  })  : _consent = consent ?? _askUser,
        _harness = harness ?? (() => null);

  final NextPlayerHost host;

  /// The playback's own snapshot and failure facts.
  final KernelHost playback;
  final KernelConsent _consent;
  final String? Function() _harness;

  static const historyCapacity = 200;
  final _overrides = <String, _Override>{};
  final _history = ListQueue<JsonMap>();
  KernelDriver? _bound;
  Future<void> _work = Future.value();
  ErikaSample? _erikaSample;
  int _sequence = 0;

  /// The changes in force, newest first, and the record of all of them.
  List<JsonMap> get history => List.unmodifiable(_history.toList().reversed);

  Future<T> _serial<T>(Future<T> Function() run) {
    final result = _work.then((_) => run());
    _work = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  // ---- inputs ----

  PlaybackSession? get _session => host.current.value;

  /// [input]'s session is the one that plays now.
  void _check(JsonMap input, {bool required = true}) {
    final sessionId = input['sessionId'];
    if (sessionId == null && !required) return;
    if (sessionId != _session?.id) {
      throw const Failure(FailureCode.conflict,
          'Playback session changed. Read playback.state.');
    }
  }

  /// The kernel instance that plays, ready for a call.
  KernelDriver _driver() {
    if (ExternalPlayerConsoleService.hasActiveSession) {
      throw const Failure(FailureCode.unavailable,
          'An external player is playing; its kernel is not NipaPlay\'s.');
    }
    final session = _session;
    if (session == null || session.phase.value.done) {
      throw const Failure(
          FailureCode.unavailable, 'No internal media is open.');
    }
    final driver = session.driver;
    if (session.phase.value == SessionPhase.swapping ||
        driver == null ||
        driver.fenced) {
      throw const Failure(FailureCode.conflict,
          'The playback is changing kernels or has no kernel open; read again in a moment.',
          retryable: true);
    }
    _endChangesOf(driver);
    return driver;
  }

  /// Changes belong to one kernel instance: once another plays they are
  /// over, and recorded so.
  void _endChangesOf(KernelDriver driver) {
    final bound = _bound;
    if (identical(bound, driver)) return;
    for (final override in _overrides.values) {
      _record(
          'ended',
          override.name,
          {
            'trigger': 'player_replaced',
            'original': safeKernelValue(override.name, override.original),
          },
          driver: bound);
    }
    _overrides.clear();
    _bound = driver;
  }

  String _id(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';

  JsonMap _record(String action, String name, JsonMap facts,
      {Invocation? invocation, KernelDriver? driver}) {
    final kernel = driver ?? _session?.driver;
    final path = _session?.path;
    final entry = <String, Object?>{
      'changeId': _id('kc'),
      'at': DateTime.now().toUtc().toIso8601String(),
      'action': action,
      'name': name,
      'origin': invocation?.origin ?? 'nipaplay',
      'invocationId': invocation?.id,
      'kernel': kernel?.kernel.id,
      'path': path == null ? null : redactHarnessText(path),
      ...facts,
    };
    _history.add(entry);
    while (_history.length > historyCapacity) {
      _history.removeFirst();
    }
    return entry;
  }

  String get _configured => host.configuredKernel();

  // ---- reading ----

  static bool _equal(Object? a, Object? b) =>
      a is List && b is List ? a.join('\u0000') == b.join('\u0000') : a == b;

  Future<Object?> _currentValue(KernelNative native, _Override override) async {
    switch (override.kind) {
      case 'mpv':
        return (await native.read([override.name]))[override.name]?.value;
      case 'mdk':
        return (await native.read([override.name]))[override.name]?.value;
      case 'decoders':
        return (native as MdkNative)
            .decoders(video: override.name == 'videoDecoders');
      case 'erika':
        final erika = native as ErikaNative;
        return override.name == 'debugHud'
            ? (await erika.debugHud()).toString()
            : erikaUpscalerName(await erika.upscaler());
    }
    return null;
  }

  /// playback.kernel: who the kernel is, what it lets Next read and set,
  /// what it reports now, and the changes in force.
  Future<JsonMap> read(JsonMap input) async {
    _check(input, required: false);
    final driver = _driver();
    final native = driver.native;
    final kernel = driver.kernel.id;
    final asked = [
      for (final n in (input['properties'] as List? ?? const []).cast<String>())
        n
    ];
    final result = <String, Object?>{
      'sessionId': _session?.id,
      'observedAt': DateTime.now().toUtc().toIso8601String(),
      'player': 'internal',
      'kernel': {
        'id': kernel,
        'name': driver.kernel.label,
        'instance': driver.instance,
        'configured': _configured,
        'version': null,
      },
      'controls': kernelControls(kernel, _reopenable),
    };
    switch (native) {
      case MpvNative():
        final names = {...mpvKernelSnapshot, ...asked}.toList();
        final reads = await native.read(names);
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
      case MdkNative():
        final reads = await native.read([...mdkKernelSnapshot, ...asked]);
        result['kernel'] = {
          ...result['kernel'] as JsonMap,
          'version': await native.version(),
        };
        result['snapshot'] = {
          for (final n in mdkKernelSnapshot)
            n: safeKernelValue(n, reads[n]?.value)
        };
        result['decoders'] = {
          'video': await native.decoders(video: true),
          'audio': await native.decoders(video: false),
          'activeVideo': await native.activeDecoder(video: true),
          'activeAudio': await native.activeDecoder(video: false),
        };
        result['properties'] = {
          for (final n in asked)
            n: {'value': safeKernelValue(n, reads[n]?.value), 'error': null}
        };
      case StateNative():
        final reads = await native.read([...native.names, ...asked]);
        result['kernel'] = {
          ...result['kernel'] as JsonMap,
          'version': await native.version(),
        };
        result['snapshot'] = {
          for (final n in native.names) n: safeKernelValue(n, reads[n]?.value)
        };
        result['properties'] = {
          for (final n in asked)
            n: {
              'value': safeKernelValue(n, reads[n]?.value),
              'error': reads[n]?.error,
            }
        };
      case ErikaNative():
        result['kernel'] = {
          ...result['kernel'] as JsonMap,
          'version': await native.version(),
        };
        result['erika'] =
            await _readErika(driver, native, input['sampleMs'] as int?);
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
    final running = kernel;
    result['overrides'] = [for (final o in _overrides.values) o.toJson()];
    result['kernelOverride'] = running == _configured
        ? null
        : {'kernel': running, 'configured': _configured};
    result['nextMediaOpensFreshPlayer'] = true;
    final history = _history.toList().reversed.toList();
    result['changes'] = history.take(20).toList();
    result['changesTotal'] = history.length;
    return result;
  }

  /// The kernels a reopen may name on this device.
  List<PlayerKernelType> get _reopenable => [
        for (final k in host.supportedKernels) kernelTypesById[k.id]!,
      ];

  Future<JsonMap> _readErika(
      KernelDriver driver, ErikaNative native, int? sampleMs) async {
    final path = _session?.path;
    var status = await native.status();
    ErikaSample? sample(JsonMap status) {
      final stats = status['presenterStats'];
      final at = status['presenterStatsAt'];
      return stats is Map && at is String
          ? ErikaSample(DateTime.parse(at), driver.instance, path,
              {for (final e in stats.entries) '${e.key}': e.value})
          : null;
    }

    var previous = _erikaSample;
    var source = 'previous_read';
    if (sampleMs != null) {
      previous = sample(status);
      await Future<void>.delayed(Duration(milliseconds: sampleMs));
      status = await native.status();
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
            : {
                ...window.window!,
                'paused': !(_session?.transport.value.playIntent ?? false)
              },
        windowUnavailable: window.reason);
  }

  // ---- setting ----

  /// playback.set_kernel_properties.
  Future<JsonMap> set(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _check(input);
        final driver = _driver();
        final native = driver.native;
        final kernel = driver.kernel.id;
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
        switch (native) {
          case MpvNative():
            if (decoders.isNotEmpty) {
              throw const Failure(FailureCode.invalidInput,
                  'Media Kit has no decoder list; mpv picks its decoder through properties such as hwdec and vd.');
            }
          case MdkNative():
            break;
          case ErikaNative():
            if (decoders.isNotEmpty) {
              throw const Failure(
                  FailureCode.invalidInput, 'Erika takes no decoder list.');
            }
            for (final entry in properties.entries) {
              final values = erikaKernelSettings[entry.key];
              if (values == null || !values.contains(entry.value)) {
                throw Failure(FailureCode.invalidInput,
                    'Erika takes ${erikaKernelSettings.entries.map((e) => '${e.key} (${e.value.join('/')})').join(', ')}.');
              }
            }
          default:
            throw const Failure(
                FailureCode.unavailable, 'This kernel takes no properties.');
        }
        final network = {
          for (final entry in properties.entries)
            if (kernelSettingConsent(entry.key, entry.value) != null)
              entry.key: entry.value
        };
        final consent = network.isEmpty
            ? 'not_needed'
            : await _askNetwork(
                driver,
                [
                  for (final entry in network.entries)
                    '· ${entry.key}：${redactHarnessText(entry.value)}',
                ],
                network.keys.join(','),
                {
                  'requested': {
                    for (final e in network.entries)
                      e.key: safeKernelValue(e.key, e.value)
                  },
                },
                invocation);
        final changes = <JsonMap>[];
        for (final entry in properties.entries) {
          changes.add(await _apply(
              driver, native, entry.key, entry.value, invocation,
              consent: network.containsKey(entry.key) ? consent : null));
        }
        for (final entry in decoders.entries) {
          changes.add(
              await _apply(driver, native, entry.key, entry.value, invocation));
        }
        return {
          'sessionId': _session?.id,
          'kernel': {'id': kernel, 'name': driver.kernel.label},
          'changes': changes,
          'overrides': [for (final o in _overrides.values) o.toJson()],
          'nextMediaOpensFreshPlayer': true,
        };
      });

  Future<JsonMap> _apply(KernelDriver driver, KernelNative native, String name,
      Object value, Invocation invocation,
      {String? consent}) async {
    final kind = switch (native) {
      MpvNative() when value is String => 'mpv',
      MdkNative() when value is String => 'mdk',
      ErikaNative() => 'erika',
      _ => 'decoders',
    };
    final probe = _Override(name, kind, null, true, DateTime.now().toUtc());
    Object? before;
    String? beforeError;
    if (kind == 'mpv') {
      final read = (await native.read([name]))[name];
      before = read?.value;
      beforeError = read?.error;
    } else {
      before = await _currentValue(native, probe);
    }
    String? error;
    try {
      switch (kind) {
        case 'mpv':
          error = await (native as MpvNative).write(name, value as String);
        case 'mdk':
          await (native as MdkNative).write(name, value as String);
        case 'decoders':
          await (native as MdkNative).setDecoders(value as List<String>,
              video: name == 'videoDecoders');
        case 'erika':
          final erika = native as ErikaNative;
          if (name == 'debugHud') {
            await erika.setDebugHud(value == 'true');
          } else {
            await erika.setUpscaler(erikaUpscalerMode(value as String));
          }
      }
    } on KernelFenced {
      rethrow;
    } catch (e) {
      error = redactHarnessText('$e');
    }
    final after = await _currentValue(native, probe);
    final applied = error == null;
    if (applied) {
      final known = kind == 'mpv' ? beforeError == null : before != null;
      _noteOverride(name, kind, before, known, value, after);
    }
    final entry = _record(
        'set',
        name,
        {
          'before': safeKernelValue(name, before),
          if (beforeError != null) 'beforeError': beforeError,
          'requested': safeKernelValue(name, value),
          'after': safeKernelValue(name, after),
          'error': error,
          'consent': consent,
        },
        invocation: invocation,
        driver: driver);
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
  Future<JsonMap> _restoreOne(KernelDriver driver, _Override override,
      String trigger, Invocation? invocation) async {
    final native = driver.native;
    final current = await _currentValue(native, override);
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
            error = await (native as MpvNative)
                .write(override.name, original as String? ?? '');
          case 'mdk':
            await (native as MdkNative)
                .write(override.name, original as String);
          case 'decoders':
            await (native as MdkNative).setDecoders(
                (original as List).cast<String>(),
                video: override.name == 'videoDecoders');
          case 'erika':
            final erika = native as ErikaNative;
            if (override.name == 'debugHud') {
              await erika.setDebugHud(original == 'true');
            } else {
              await erika.setUpscaler(erikaUpscalerMode(original as String));
            }
        }
      } on KernelFenced {
        rethrow;
      } catch (e) {
        error = redactHarnessText('$e');
      }
      _overrides.remove(override.name);
      result = {'restored': error == null, if (error != null) 'error': error};
    }
    final after = await _currentValue(native, override);
    final entry = _record(
        'restore',
        override.name,
        {
          'trigger': trigger,
          'before': safeKernelValue(override.name, current),
          'original': safeKernelValue(override.name, override.original),
          'after': safeKernelValue(override.name, after),
          ...result,
        },
        invocation: invocation,
        driver: driver);
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
        _check(input, required: false);
        final driver = _driver();
        final names = (input['names'] as List?)?.cast<String>() ??
            _overrides.keys.toList();
        final results = <JsonMap>[];
        for (final name in names) {
          final override = _overrides[name];
          if (override == null) {
            results.add(
                {'name': name, 'restored': false, 'reason': 'not_changed'});
            continue;
          }
          results.add(
              await _restoreOne(driver, override, 'requested', invocation));
        }
        return {
          'restored': results,
          'overrides': [for (final o in _overrides.values) o.toJson()],
          'nextMediaOpensFreshPlayer': true,
        };
      });

  /// Asks the person at NipaPlay about [lines]; the answer, or a refusal
  /// recorded and thrown. The question goes away when the media or the
  /// kernel changes.
  Future<String> _askNetwork(KernelDriver driver, List<String> lines,
      String name, JsonMap facts, Invocation invocation) async {
    final session = _session;
    final stopped = Completer<void>();
    void watch() {
      final now = _session;
      if ((now != session || !identical(now?.driver, driver)) &&
          !stopped.isCompleted) {
        stopped.complete();
      }
    }

    host.current.addListener(watch);
    session?.phase.addListener(watch);
    bool approved;
    try {
      approved = await _consent(
          '播放器网络设置',
          ['这次播放将使用：', ...lines, '换到其他视频时恢复。'].join('\n'),
          '允许',
          stopped.future);
    } finally {
      host.current.removeListener(watch);
      session?.phase.removeListener(watch);
    }
    if (!approved) {
      _record('declined', name, facts, invocation: invocation, driver: driver);
      throw const Failure(FailureCode.conflict, '用户没有同意这次播放使用这些网络设置');
    }
    if (_session != session || !identical(_session?.driver, driver)) {
      throw const Failure(
          FailureCode.conflict, 'Playback changed while waiting for the user.');
    }
    return 'user_approved';
  }

  /// Records [name] as changed from [before] (known when the kernel reported
  /// it) to [after].
  _Override _noteOverride(String name, String kind, Object? before, bool known,
      Object? requested, Object? after) {
    final override = _overrides.putIfAbsent(name,
        () => _Override(name, kind, before, known, DateTime.now().toUtc()));
    override.requested = requested;
    override.lastSet = after;
    return override;
  }

  // ---- passing through ----

  /// playback.kernel_command.
  Future<JsonMap> command(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _check(input);
        final driver = _driver();
        final native = driver.native;
        if (native is! MpvNative) {
          throw Failure(FailureCode.unavailable,
              'Only Media Kit runs mpv commands; this player runs ${driver.kernel.id}.');
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
            : await _askNetwork(driver, ['· ${safeCommand.join(' ')}'],
                body.first, {'command': safeCommand}, invocation);
        final property = mpvCommandProperty(args);
        NativeRead? before;
        if (property != null) {
          before = (await native.read([property]))[property];
        }
        final reply = await native.command(args,
            timeout:
                Duration(milliseconds: input['timeoutMs'] as int? ?? 10000));
        String? after;
        if (property != null) {
          after = (await native.read([property]))[property]?.value;
        }
        final lasting = property != null
            ? 'property'
            : mpvTransientCommands.contains(body.first)
                ? 'none'
                : 'unknown';
        _Override? override;
        if (reply.error == null && property != null) {
          override = _noteOverride(property, 'mpv', before?.value,
              before?.error == null, safeCommand.join(' '), after);
        }
        final sessionId = _session?.id;
        final playerError =
            sessionId == null ? null : playback.error(sessionId);
        final entry = _record(
            'command',
            property ?? body.first,
            {
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
            },
            invocation: invocation,
            driver: driver);
        override?.changeIds.add(entry['changeId'] as String);
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
          'nextMediaOpensFreshPlayer': true,
        };
      });

  /// playback.kernel_invoke.
  Future<JsonMap> invoke(JsonMap input, Invocation invocation) =>
      _serial(() async {
        _check(input);
        final driver = _driver();
        final native = driver.native;
        if (native is! ErikaNative) {
          throw Failure(FailureCode.unavailable,
              'Only Erika takes invoke; this player runs ${driver.kernel.id}.');
        }
        final method = input['method'] as String;
        final arguments = <String, Object?>{
          for (final e in ((input['arguments'] as Map?) ?? const {}).entries)
            '${e.key}': e.value
        };
        final consent = kernelInvokeConsent(arguments) == null
            ? 'not_needed'
            : await _askNetwork(
                driver,
                ['· $method ${redactHarnessText(jsonEncode(arguments))}'],
                method,
                {'arguments': safeKernelResult(arguments)},
                invocation);
        final reply = await native.invoke(method, arguments);
        final sessionId = _session?.id;
        final playerError =
            sessionId == null ? null : playback.error(sessionId);
        final entry = _record(
            'invoke',
            method,
            {
              'arguments': safeKernelResult(arguments),
              'supported': reply.supported,
              'result': safeKernelResult(reply.result),
              'error': reply.error,
              'consent': consent,
              if (playerError != null) 'playerError': playerError['message'],
            },
            invocation: invocation,
            driver: driver);
        return {
          'changeId': entry['changeId'],
          'sessionId': sessionId,
          'method': method,
          'supported': reply.supported,
          'result': entry['result'],
          'error': reply.error,
          'consent': consent,
          'playerError': playerError,
          'nextMediaOpensFreshPlayer': true,
        };
      });

  /// playback.watch_kernel_properties: what the named properties were, and
  /// each change seen over a bounded time, read every [intervalMs].
  Future<JsonMap> watch(JsonMap input) async {
    _check(input, required: false);
    final driver = _driver();
    final native = driver.native;
    if (native is! MpvNative && native is! MdkNative) {
      throw Failure(FailureCode.unavailable,
          'Named properties are watched on Media Kit and MDK; this player runs ${driver.kernel.id}.');
    }
    final names = [for (final n in input['properties'] as List) '$n'];
    final duration = input['durationMs'] as int? ?? 0;
    final interval = input['intervalMs'] as int? ?? 250;
    final session = _session!;
    Future<Map<String, NativeRead>> sample() => native.read(names);
    JsonMap values(Map<String, NativeRead> read) => {
          for (final n in names)
            n: {
              'value': safeKernelValue(n, read[n]?.value),
              'error': read[n]?.error,
            }
        };
    final startedAt = DateTime.now().toUtc();
    final clock = Stopwatch()..start();
    final initial = await sample();
    var previous = initial;
    final changes = <JsonMap>[];
    var samples = 1;
    var endedBy = 'duration';
    while (clock.elapsedMilliseconds < duration) {
      await Future<void>.delayed(Duration(
          milliseconds:
              (duration - clock.elapsedMilliseconds).clamp(1, interval)));
      if (driver.fenced || !identical(_session?.driver, driver)) {
        endedBy =
            identical(_session, session) ? 'player_replaced' : 'media_changed';
        break;
      }
      final Map<String, NativeRead> current;
      try {
        current = await sample();
      } on KernelFenced {
        endedBy =
            identical(_session, session) ? 'player_replaced' : 'media_changed';
        break;
      }
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
      'sessionId': session.id,
      'kernel': driver.kernel.id,
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
        _check(input);
        final session = _session!;
        if (ExternalPlayerConsoleService.hasActiveSession) {
          throw const Failure(FailureCode.unavailable,
              'An external player is playing; its kernel is not NipaPlay\'s.');
        }
        if (session.phase.value.done) {
          throw const Failure(
              FailureCode.unavailable, 'No internal media is open.');
        }
        final id = input['kernel'] as String;
        final target = KernelId.byId(id)!;
        if (!host.supportedKernels.contains(target)) {
          throw Failure(FailureCode.unavailable,
              'This device cannot run $id; it runs ${host.supportedKernels.map((k) => k.id).join(', ')}.');
        }
        final previous = session.driver;
        final reply =
            await session.swapKernel(target, origin: invocation.origin);
        for (final override in _overrides.values) {
          _record(
              'ended',
              override.name,
              {
                'trigger': 'player_replaced',
                'original': safeKernelValue(override.name, override.original),
              },
              invocation: invocation,
              driver: previous);
        }
        _overrides.clear();
        _bound = null;
        final replaced = reply['replaced'] == true;
        final opened = reply['opened'] == true;
        final actual = session.driver?.kernel.id;
        final error = playback.error(session.id);
        _record(
            'reopen',
            'kernel',
            {
              'requested': id,
              'actual': actual,
              'configured': _configured,
              'opened': opened,
              'error': reply['failure'] ?? error?['message'],
            },
            invocation: invocation);
        return {
          'kernel': {
            'requested': id,
            'actual': actual,
            'name': session.driver?.kernel.label,
            'configured': _configured,
          },
          'replaced': replaced,
          'opened': opened,
          if (reply['reason'] != null) 'reason': reply['reason'],
          'failure': reply['failure'],
          'error': error,
          'preserved': reply['preserved'],
          'nextMediaOpensConfiguredKernel':
              actual != null && actual != _configured,
          'state': playback.snapshot().toJson(),
        };
      });
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
                      'Read the kernel under the internal player, asked at call time: kernel (id mdk/media_kit/video_player/erika, name, configured = the kernel setting, version: mpv and ffmpeg for Media Kit, mdk for MDK, null where the kernel gives none), controls (what this kernel lets set_kernel_properties change and which kernels reopen_with_kernel can use here), snapshot (Media Kit: a fixed list of mpv properties; MDK: a fixed list of MDK properties, which MDK reports only once set on this player), properties (the names asked for in properties: value and the kernel\'s own error), decoders (MDK: the ordered video/audio decoder lists and the decoders opened), erika (Erika: decoder backend from its last decoder event with hardware and fellBack read off it, frame, audio and HDR counters, output, resources, upscaler, tracks, debug HUD; counters are cumulative, window gives their change since the previous playback.kernel read of the same player and media, or over sampleMs when given; diagnostics is Erika\'s own snapshot as Erika gives it (schema 1: playback, media, decoder with requested/active backend, hardware, fellBack and reason, video frame counters, presenter timings, output, hdr, resources, upscaler, audio, buffers and queue depths, timing: scheduler late drops and lateness, presentation cadence and jitter, clock drift and corrections), null where this Erika has none; notReported lists what Erika does not expose). A value the kernel does not give is null. overrides are the changes in force, kernelOverride a reopen on a kernel other than the setting, changes the last 20 records (who, when, before, requested, after). Values are redacted.',
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
                      'Set kernel values on the current player for the media playing now. properties: Media Kit takes any mpv property (applied through mpv now, not made an option of later files); MDK takes any player property (MDK applies many when a stream or decoder opens); Erika takes upscaler (off/artCnnC4F16/artCnnC4F32/artCnnC4F16Ds) and debugHud (true/false). videoDecoders/audioDecoders: MDK\'s ordered decoder lists. Each change reports before, requested, after (read back from the kernel) and the kernel\'s error, and is recorded with origin and time. A change holds for the kernel instance that plays now: another media opens a new instance on the settings, and so does reopen_with_kernel, so the change is over then (recorded as ended). restore_kernel_properties puts an original back while it plays (restorable=false: the kernel never reported the original, so it cannot). Settings that can send traffic or credentials elsewhere (proxy, user agent, headers, cookies, referrer, TLS trust, option text such as stream-lavf-o that sets one of these, or a value holding an address) wait for the person at NipaPlay to allow them; a refusal fails with 用户没有同意这次播放使用这些网络设置 and changes nothing. Settings stay as they are; lasting changes are made with settings.set.',
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
                    'names':
                        ArraySchema(StringSchema(minLength: 1), minItems: 1),
                  }),
                  output: ObjectSchema({}, additionalProperties: true)),
              control.restore),
          ClassicAction(
              const ActionSpec(
                  id: 'playback.kernel_command',
                  title: 'Run an mpv command',
                  description:
                      'Media Kit only. Runs command, an mpv command as an array of strings passed to mpv as given (name first, mpv prefixes allowed), on the current player, and returns mpv\'s result data (strings, numbers, flags, lists, maps; byte output read as UTF-8) or mpv\'s own error text, with the playback error when the player reports one afterwards. Any command runs, including filters (vf, af), shaders through change-list glsl-shaders, run and subprocess; load-script takes a script inside the harness repository. A command that changes a property (set, add, cycle, cycle-values, multiply, change-list, vf, af) reports the property before and after and holds like set_kernel_properties: for this kernel instance, restorable through restore_kernel_properties. lasting is property, none (nothing stays past this file) or unknown (load-script, loadfile, playlist commands, apply-profile and others); either way the next media opens a new instance. A command that sends traffic or credentials elsewhere (an address or a proxy, header, cookie, user agent or referrer among its arguments, or such a property) waits for the person at NipaPlay; run and subprocess do not wait. timeoutMs (default 10000) bounds the wait for mpv\'s answer; the command itself keeps running past it. Every call is recorded (who, when, command, before, result, error).',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': StringSchema(minLength: 1),
                    'command':
                        ArraySchema(StringSchema(), minItems: 1, maxItems: 64),
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
                      'Erika only. Hands method and arguments as they are to Erika\'s JSON method table, the same table Erika\'s other hosts use. method listMethods (no arguments) returns that table: every method with its scope, a summary, its arguments (name, type, required), what it returns, whether it blocks until the work is done and whether it writes files; methods Erika adds later appear there and work here without a NipaPlay change. Returns Erika\'s value as result, or Erika\'s own error; supported=false when this Erika has no such method (or no table on this platform). The playback error is added when the player reports one afterwards. Arguments that name or hold a network setting or an address wait for the person at NipaPlay. Every call is recorded.',
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
                      'Move this playback to a new instance of kernel and reopen the current media at its position, without changing the kernel setting; the session stays and so does its watch record. Position, playing or paused, rate, volume, the audio and subtitle track (matched by language, title and codec, else index) and mounted external subtitle files are carried over, and what was asked meanwhile (a pause, a seek) is applied to the new instance. Reports the kernel requested, the one actually running (a kernel this device cannot run is refused), whether it opened, the playback error, and each carried value before and after. Changes made by set_kernel_properties end with the old instance. The next media opens on the kernel setting again.',
                  effect: Effect.write,
                  input: ObjectSchema({
                    'sessionId': const StringSchema(minLength: 1),
                    'kernel':
                        StringSchema(values: kernelTypesById.keys.toList()),
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
