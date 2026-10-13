import 'dart:async';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Classic callers have no subscriber. Next publishes only committed facts.
abstract final class BodySignals {
  static Future<void> Function(String event, String entityId, JsonMap facts)?
      emit;
  static final _transaction = Object();
  static void changed(String event, String entityId, JsonMap facts) {
    final events = Zone.current[_transaction] as List<JsonMap>?;
    if (events != null) {
      events.add({'event': event, 'entityId': entityId, 'facts': facts});
    } else {
      unawaited(emit?.call(event, entityId, facts));
    }
  }

  static Future<T> transaction<T>(
      Database db, Future<T> Function(Transaction) action) async {
    final events = <JsonMap>[];
    final result = await runZoned(() => db.transaction(action),
        zoneValues: {_transaction: events});
    for (final event in events) {
      await emit?.call(event['event'] as String, event['entityId'] as String,
          event['facts'] as JsonMap);
    }
    return result;
  }
}
