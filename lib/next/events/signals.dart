import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Classic callers have no subscriber. Next publishes only committed facts.
abstract final class BodySignals {
  static Future<void> Function(String event, String entityId, JsonMap facts)?
      emit;
  static final _transaction = Object();
  static final _notificationFailures = <JsonMap>[];
  static JsonMap get deliveryStatus => {
    'commitIndependent': true,
    'waitLimitMs': 5000,
    'recentUnconfirmed': [for (final failure in _notificationFailures) {...failure}],
    'scope': 'Current process, last 20 notification failures; timeout does not cancel delivery or roll back committed data.',
  };
  static void changed(String event, String entityId, JsonMap facts) {
    final events = Zone.current[_transaction] as List<JsonMap>?;
    if (events != null) {
      events.add({'event': event, 'entityId': entityId, 'facts': facts});
    } else {
      unawaited(emit?.call(event, entityId, facts));
    }
  }

  static Future<T> transaction<T>(
      Database db, Future<T> Function(Transaction) action,
      {Future<void> Function(T)? afterCommit,
      Duration? notificationTimeout,
      Future<void> Function(Object)? onNotificationError}) async {
    final events = <JsonMap>[];
    final result = await runZoned(() => db.transaction(action),
        zoneValues: {_transaction: events});
    await afterCommit?.call(result);
    Future<void> notify() async {
      for (final event in events) {
        await emit?.call(event['event'] as String, event['entityId'] as String,
            event['facts'] as JsonMap);
      }
    }

    try {
      final delivery = notify();
      await delivery.timeout(notificationTimeout ?? const Duration(seconds: 5));
    } catch (error) {
      // The database already committed. Report notification uncertainty without
      // turning a successful write into a failure that invites another write.
      _notificationFailures.add({
        'at': DateTime.now().toUtc().toIso8601String(),
        'status': 'unconfirmed',
        'error': error is TimeoutException ? 'notification_timeout' : 'notification_failed',
        'errorType': error.runtimeType.toString(),
        'eventCount': events.length,
        'events': events.map((event) => event['event']).toSet().toList(),
      });
      if (_notificationFailures.length > 20) _notificationFailures.removeAt(0);
      await onNotificationError?.call(error);
    }
    return result;
  }
}
