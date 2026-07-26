import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

final Map<String, Uri> _mediaServerBaseUris = {};

void setMediaServerBaseUrl(String serverKey, String? baseUrl) {
  final uri = baseUrl == null ? null : Uri.tryParse(baseUrl);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    _mediaServerBaseUris.remove(serverKey);
    return;
  }
  _mediaServerBaseUris[serverKey] = uri;
}

bool isMediaServerImageUri(Uri uri) {
  if (!_mediaServerBaseUris.values.any((base) => _isWithinBase(base, uri))) {
    return false;
  }
  final segments = uri.pathSegments
      .map((segment) => segment.toLowerCase())
      .toList(growable: false);
  for (var index = 0; index + 2 < segments.length; index += 1) {
    if (segments[index] == 'items' && segments[index + 2] == 'images') {
      return true;
    }
  }
  return false;
}

bool _isWithinBase(Uri base, Uri candidate) {
  if (!_sameOrigin(base, candidate)) {
    return false;
  }
  final baseSegments = base.pathSegments.where((segment) => segment.isNotEmpty);
  final candidateSegments = candidate.pathSegments.iterator;
  for (final baseSegment in baseSegments) {
    if (!candidateSegments.moveNext() ||
        candidateSegments.current.toLowerCase() != baseSegment.toLowerCase()) {
      return false;
    }
  }
  return true;
}

bool _sameOrigin(Uri left, Uri right) {
  return left.scheme.toLowerCase() == right.scheme.toLowerCase() &&
      left.host.toLowerCase() == right.host.toLowerCase() &&
      left.port == right.port;
}

Future<Uint8List> loadNetworkImageBytes(Uri originalUri) async {
  final requestUri = WebRemoteAccessService.proxyUri(originalUri);
  if (isMediaServerImageUri(originalUri)) {
    return loadMediaServerImage(requestUri);
  }

  final response = await http.get(requestUri);
  if (response.statusCode != 200) {
    throw http.ClientException(
      'Image request failed: HTTP ${response.statusCode}',
      requestUri,
    );
  }
  return response.bodyBytes;
}

Future<Uint8List> loadMediaServerImage(Uri uri) async {
  final transport = await MediaServerTransport.fromStoredSettings();
  try {
    final response = await transport.send(
      http.Request('GET', uri),
      timeout: const Duration(seconds: 20),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Media-server image request failed: HTTP ${response.statusCode}',
        uri,
      );
    }
    return response.bodyBytes;
  } finally {
    transport.close();
  }
}
