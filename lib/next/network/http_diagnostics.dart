import 'package:nipaplay/security/secret_redactor.dart';

/// Exclude userinfo, queries, headers, bodies and content-type parameters.
String httpDiagnostics(Uri? uri, {int? statusCode, String? contentType}) {
  final mediaType = contentType?.split(';').first.trim().toLowerCase();
  final safeType = mediaType != null &&
          RegExp(r'^[a-z0-9!#$&^_.+-]+/[a-z0-9!#$&^_.+-]+$').hasMatch(mediaType)
      ? mediaType
      : 'unavailable';
  return SecretRedactor.text('HTTP ${statusCode ?? "unavailable"}; '
      'host=${uri?.host ?? "unavailable"}; '
      'path=${uri?.path ?? "unavailable"}; content-type=$safeType');
}
