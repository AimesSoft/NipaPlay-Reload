import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// One attempt to reach one configured address of a media source.
class AddressProbe {
  const AddressProbe({
    required this.sourceId,
    required this.role,
    required this.address,
    required this.at,
    required this.reachable,
    required this.latencyMs,
    this.errorCode,
  });

  /// `webdav:<id>`, `smb:<id>`, `jellyfin:<id>` or `emby:<id>`.
  final String sourceId;

  /// `lan`, `wan`, or the id of one address of a multi-address server.
  final String role;

  /// The address as configured (no credentials).
  final String address;
  final DateTime at;
  final bool reachable;
  final int latencyMs;

  /// Stable failure code; null when reachable.
  final String? errorCode;
}

/// Passive observation point: Classic probes addresses exactly as before and
/// tells the observer, when one is attached, what each attempt found.
abstract final class AddressProbes {
  static void Function(AddressProbe probe)? observer;

  static void report(AddressProbe probe) {
    try {
      observer?.call(probe);
    } catch (_) {
      // Observation never changes how a probe ends.
    }
  }
}

/// Failure reasons as stable codes. Exception text is never kept.
String classifyFailure(Object? error) {
  if (error == null) return 'unknown';
  if (error is TimeoutException) return 'timeout';
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'timeout';
      case DioExceptionType.badCertificate:
        return 'tls_failed';
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) return 'auth_failed';
        return status == null ? 'protocol_error' : 'http_$status';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        final inner = error.error;
        if (inner != null && inner is! DioException) {
          return classifyFailure(inner);
        }
        return 'connection_failed';
      case DioExceptionType.cancel:
        return 'cancelled';
    }
  }
  if (error is HandshakeException || error is TlsException) return 'tls_failed';
  // The error number says what happened on every system; the message text is
  // in the system's language (Windows reports it in the user's).
  if (error is SocketException && error.osError != null) {
    final code = error.osError!.errorCode;
    if (Platform.isWindows) {
      switch (code) {
        case 10061 || 1225:
          return 'connection_refused';
        case 10060 || 121:
          return 'timeout';
        case 10051 || 10065 || 1231 || 1232:
          return 'network_unreachable';
        case 11001 || 11004:
          return 'dns_failed';
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      switch (code) {
        case 61:
          return 'connection_refused';
        case 60:
          return 'timeout';
        case 51 || 65:
          return 'network_unreachable';
      }
    } else {
      switch (code) {
        case 111:
          return 'connection_refused';
        case 110:
          return 'timeout';
        case 101 || 113:
          return 'network_unreachable';
      }
    }
  }
  final text = error.toString().toLowerCase();
  if (text.contains('credential_missing')) return 'credential_missing';
  if (text.contains('credential_origin_changed')) {
    return 'credential_origin_changed';
  }
  if (text.contains('timeout') || text.contains('timed out')) return 'timeout';
  if (text.contains('refused')) return 'connection_refused';
  if (text.contains('failed host lookup') ||
      text.contains('nodename') ||
      text.contains('name or service not known') ||
      text.contains('no address associated')) {
    return 'dns_failed';
  }
  if (text.contains('unreachable')) return 'network_unreachable';
  if (text.contains('handshake') || text.contains('certificate')) {
    return 'tls_failed';
  }
  if (text.contains('logon') ||
      text.contains('authentication') ||
      text.contains('access denied') ||
      text.contains('access_denied') ||
      text.contains('unauthorized') ||
      text.contains('401') ||
      text.contains('认证失败') ||
      text.contains('密码')) {
    return 'auth_failed';
  }
  if (error is SocketException) return 'connection_failed';
  return 'connection_failed';
}
