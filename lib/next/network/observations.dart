import 'dart:async';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:http/http.dart' as http;

/// Records transport facts without retaining URLs, headers, or exception text.
abstract final class NetworkObservations {
  static final _facts = <String, JsonMap>{};
  static final changes = StreamController<JsonMap>.broadcast(sync: true);
  static List<JsonMap> get facts => [
        for (final row in _facts.values) {...row}
      ];
  static String code(Object error) => switch (error) {
        TimeoutException() => 'timeout',
        HandshakeException() => 'tls_failed',
        SocketException() => 'connection_failed',
        http.ClientException() => 'transport_failed',
        _ => 'request_failed',
      };
  static void record(String source, {Uri? uri, int? status, String? error}) {
    final id = uri == null ? source : '$source:${uri.host}:${uri.port}';
    final previous = _facts[id];
    final now = DateTime.now().toUtc().toIso8601String();
    final failed =
        error ?? (status != null && status >= 400 ? 'http_$status' : null);
    final row = <String, Object?>{
      'id': id,
      'source': source,
      if (uri != null) 'origin': '${uri.scheme}://${uri.host}:${uri.port}',
      'lastAttemptAt': now,
      'lastSuccessAt': failed == null ? now : previous?['lastSuccessAt'],
      'httpStatus': status,
      'error': failed == null
          ? null
          : {
              'code': failed,
              'retryable': failed != 'http_401' && failed != 'http_403',
              'recoveryAction': failed == 'http_401' || failed == 'http_403'
                  ? 'Check this source login and authorization.'
                  : 'Inspect network.status and check the affected source.'
            },
      'availability': failed == null ? 'reachable' : 'failed'
    };
    _facts[id] = row;
    if (previous?['availability'] != row['availability'] ||
        (previous?['error'] as Map?)?['code'] != failed) {
      changes.add(row);
    }
  }
}
