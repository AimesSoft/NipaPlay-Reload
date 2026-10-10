import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';

import 'api_uri.dart';

/// Next's bridge to Classic. Resolve for each request so router failover and
/// settings changes apply to already-created hosts and providers.
final class DandanplayGateway {
  DandanplayGateway({
    required this.client,
    Future<String> Function()? apiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl ?? DandanplayService.getApiBaseUrl;

  final DandanplayHttpClient client;
  final Future<String> Function() _apiBaseUrl;

  Future<Uri> resolve(Uri endpoint) async =>
      appendApiPath(Uri.parse(await _apiBaseUrl()), endpoint.path)
          .replace(query: endpoint.query.isEmpty ? null : endpoint.query);
}
