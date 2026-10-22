import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:nipaplay/services/address_probe.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What was last observed about each media source, kept across restarts.
///
/// Only facts are kept: when an attempt happened, what it found and a stable
/// code for why it failed. No credentials, no exception text, no judgement.
/// One JSON value per source under `next.source.<id>.facts`.
final class SourceFacts {
  SourceFacts({DateTime Function()? clock})
      : _clock = clock ?? (() => DateTime.now().toUtc());
  final DateTime Function() _clock;
  Future<void> _tail = Future.value();
  final _syncing = <String, String>{};

  /// Whether a source is still known; the probe observer ignores the rest
  /// (a test of an unsaved configuration is not a source).
  bool Function(String sourceId)? exists;

  static String key(String sourceId) => 'next.source.$sourceId.facts';

  /// Completes when every recorded fact has been written.
  Future<void> flush() => _tail;

  Future<JsonMap> read(String sourceId) async {
    final text = (await SharedPreferences.getInstance()).getString(key(sourceId));
    if (text == null) return {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _edit(String sourceId, void Function(JsonMap facts) change) {
    final done = _tail.then((_) async {
      final facts = await read(sourceId);
      change(facts);
      await (await SharedPreferences.getInstance())
          .setString(key(sourceId), jsonEncode(facts));
    });
    _tail = done.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done;
  }

  String _now() => _clock().toIso8601String();

  /// The observer attached to Classic's address probes.
  void probe(AddressProbe probe) {
    if (exists != null && !exists!(probe.sourceId)) return;
    unawaited(_edit(probe.sourceId, (facts) {
      final addresses = Map<String, Object?>.from(
          (facts['addresses'] as Map?) ?? const <String, Object?>{});
      final previous = (addresses[probe.role] as Map?)?.cast<String, Object?>();
      final at = probe.at.toUtc().toIso8601String();
      addresses[probe.role] = {
        'address': SecretRedactor.text(probe.address),
        'lastAttemptAt': at,
        'reachable': probe.reachable,
        'latencyMs': probe.latencyMs,
        'errorCode': probe.errorCode,
        'lastSuccessAt': probe.reachable ? at : (previous?['lastSuccessAt']),
        'lastFailureAt': probe.reachable ? (previous?['lastFailureAt']) : at,
      };
      facts['addresses'] = addresses;
    }));
  }

  /// The result of an explicit check of a source (media.sources.check).
  Future<void> checked(String sourceId,
      {required bool ok, String? errorCode, required int latencyMs}) {
    final at = _now();
    return _edit(sourceId, (facts) {
      facts['check'] = {
        'at': at,
        'result': ok ? 'succeeded' : 'failed',
        'errorCode': ok ? null : errorCode,
        'latencyMs': latencyMs,
      };
      if (ok) {
        _verified(facts, at);
      } else {
        _failed(facts, errorCode ?? 'unknown', at);
      }
    });
  }

  void _verified(JsonMap facts, String at) {
    final credential = Map<String, Object?>.from(
        (facts['credential'] as Map?) ?? const <String, Object?>{});
    credential['lastVerifiedAt'] = at;
    facts['credential'] = credential;
    facts.remove('lastError');
  }

  /// Codes for which the source turned the saved or given login away.
  static const rejections = {'auth_failed', 'login_required'};

  void _failed(JsonMap facts, String code, String at) {
    facts['lastError'] = {'code': code, 'at': at};
    if (rejections.contains(code)) {
      final credential = Map<String, Object?>.from(
          (facts['credential'] as Map?) ?? const <String, Object?>{});
      credential['lastRejectedAt'] = at;
      credential['lastRejectedCode'] = code;
      facts['credential'] = credential;
    }
  }

  /// A failure the source reported outside a check (login, sync).
  Future<void> failed(String sourceId, String code) {
    final at = _now();
    return _edit(sourceId, (facts) => _failed(facts, code, at));
  }

  Future<void> loggedIn(String sourceId) {
    final at = _now();
    return _edit(sourceId, (facts) => _verified(facts, at));
  }

  Future<void> syncStarted(String sourceId, String jobId) {
    _syncing[sourceId] = jobId;
    final at = _now();
    return _edit(sourceId, (facts) {
      final previous = (facts['sync'] as Map?)?.cast<String, Object?>();
      facts['sync'] = {
        'jobId': jobId,
        'startedAt': at,
        'finishedAt': null,
        'result': 'running',
        'indexed': null,
        'errorCode': null,
        'lastSuccessAt': previous?['lastSuccessAt'],
      };
    });
  }

  Future<void> syncFinished(String sourceId, String jobId,
      {required String result, int? indexed, String? errorCode}) {
    if (_syncing[sourceId] == jobId) _syncing.remove(sourceId);
    final at = _now();
    return _edit(sourceId, (facts) {
      final previous = (facts['sync'] as Map?)?.cast<String, Object?>();
      facts['sync'] = {
        'jobId': jobId,
        'startedAt': previous?['jobId'] == jobId ? (previous?['startedAt']) : null,
        'finishedAt': at,
        'result': result,
        'indexed': indexed,
        'errorCode': errorCode,
        'lastSuccessAt':
            result == 'succeeded' ? at : previous?['lastSuccessAt'],
      };
      if (result == 'failed') {
        _failed(facts, errorCode ?? 'unknown', at);
      } else if (result == 'succeeded') {
        facts.remove('lastError');
      }
    });
  }

  /// `running` is only true of a sync this process is still running; one
  /// left over from before a restart is `interrupted`.
  String? syncResult(String sourceId, JsonMap? sync) {
    final result = sync?['result'] as String?;
    if (result == 'running' && _syncing[sourceId] != sync?['jobId']) {
      return 'interrupted';
    }
    return result;
  }

  Future<void> clear(String sourceId) async {
    _syncing.remove(sourceId);
    final done = _tail.then((_) async {
      await (await SharedPreferences.getInstance()).remove(key(sourceId));
    });
    _tail = done.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await done;
  }

  /// The login or addresses of a source changed: what was observed of the
  /// old ones no longer describes it.
  Future<void> reset(String sourceId) => _edit(sourceId, (facts) {
        facts.remove('addresses');
        facts.remove('check');
        facts.remove('credential');
        facts.remove('lastError');
      });
}
