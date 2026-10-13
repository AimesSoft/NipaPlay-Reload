import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/media_server_transport.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../capabilities/classic_action.dart';
import '../media_sources/service.dart';
import 'observations.dart';

final class NetworkCapability implements Capability {
  NetworkCapability(this.sources);
  final MediaSourcesService sources;
  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'network.status',
                title: '网络路由与故障事实',
                description:
                    '读取当前路由、故障转移、媒体服务器 UA、最近请求与上次成功。未观察来源不宣称可达；不返回认证链接、请求头或秘密。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async {
          final prefs = await SharedPreferences.getInstance();
          final proxy = AppHttpProxy.validate(AppHttpProxy.endpoint);
          final gateway =
              Uri.parse(await NetworkSettings.getDandanplayServer());
          final registered = await sources.list();
          return {
            'observedAt': DateTime.now().toUtc().toIso8601String(),
            'effectiveProxy': proxy == null
                ? {'mode': 'system'}
                : {'mode': 'explicit', 'host': proxy.host, 'port': proxy.port},
            'routes': [
              {
                'provider': 'dandanplay',
                'mode': (await NetworkSettings.getDandanplayServerMode()).name,
                'effectiveGateway':
                    '${gateway.scheme}://${gateway.host}:${gateway.port}',
                'requestPrefixPresent':
                    gateway.path.isNotEmpty && gateway.path != '/',
                'failoverUntil': prefs.getInt(NetworkSettings.failoverUntilKey),
                'customOriginTrust':
                    'Selected by the user in Classic network settings.'
              }
            ],
            'mediaServerUserAgent':
                await MediaServerTransport.getStoredConnectionUserAgent(),
            'observations': NetworkObservations.facts,
            'sources': [
              for (final row in registered)
                {
                  'sourceId': row['sourceId'],
                  'type': row['type'],
                  'name': row['name'],
                  'connectionState': row['connectionState'],
                  'observationIds': [
                    for (final observation in NetworkObservations.facts)
                      if (observation['source'] == row['sourceId'] ||
                          observation['origin'] ==
                              _origin(row['url'] as String?))
                        observation['id']
                  ]
                }
            ],
            'historyScope': 'this process'
          };
        }),
        ClassicAction(
            const ActionSpec(
                id: 'network.check',
                title: '检查网络来源',
                description:
                    '显式检查已登记来源（sourceId），或官方网关的 healthz（dandanplay）。逐项结果保留故障与上次成功；复用 Classic 客户端，不改变路由或登录。',
                effect: Effect.read,
                input: ObjectSchema({
                  'targets': ArraySchema(StringSchema(minLength: 1),
                      minItems: 1, maxItems: 100)
                }, required: [
                  'targets'
                ]),
                output: ObjectSchema({}, additionalProperties: true)),
            (input, _) async {
          final results = <JsonMap>[];
          for (final target in (input['targets'] as List).cast<String>()) {
            final watch = Stopwatch()..start();
            try {
              final JsonMap facts;
              if (target == 'dandanplay') {
                final base = await NetworkSettings.getDandanplayServer();
                final uri = Uri.parse(
                    '${base.replaceFirst(RegExp(r'/$'), '')}/healthz');
                final client = DandanplayHttpClient();
                try {
                  final response = await client
                      .get(uri)
                      .timeout(const Duration(seconds: 10));
                  facts = {
                    'httpStatus': response.statusCode,
                    'reachable': response.statusCode < 400
                  };
                  NetworkObservations.record(target,
                      uri: uri, status: response.statusCode);
                } finally {
                  client.close();
                }
              } else {
                facts = await sources.check(target);
                NetworkObservations.record(target,
                    error: facts['connected'] == false
                        ? 'source_unreachable'
                        : null);
              }
              results.add({
                'source': target,
                'latencyMs': watch.elapsedMilliseconds,
                ...facts
              });
            } catch (error) {
              final code = error is Failure
                  ? error.code.name
                  : NetworkObservations.code(error);
              NetworkObservations.record(target, error: code);
              results.add({
                'source': target,
                'latencyMs': watch.elapsedMilliseconds,
                'reachable': false,
                'error': {
                  'code': code,
                  'stage': 'source_check',
                  'retryable': error is Failure ? error.retryable : true,
                  'recoveryAction':
                      'Read network.status; check this source configuration and login.'
                }
              });
            }
          }
          return {
            'results': [
              for (var i = 0; i < results.length; i++)
                {'index': i, ...results[i]}
            ],
            'observations': NetworkObservations.facts,
            'stageAvailability': {
              'dns': 'not exposed by Classic HTTP clients',
              'tls': 'only reported when a handshake error occurs'
            }
          };
        }),
      ];

  String? _origin(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    return uri == null || uri.host.isEmpty
        ? null
        : '${uri.scheme}://${uri.host}:${uri.port}';
  }
}
