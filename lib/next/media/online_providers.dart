import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import '../network/dandanplay_gateway.dart';
import 'metadata_provider.dart';
import 'provider_transport.dart';
import 'providers.dart';

/// Both hosts use the same providers, request transport and credential refs.
List<MetadataProvider> onlineMetadataProviders({
  required CredentialResolver credentials,
  required http.Client tmdb,
  required http.Client bangumi,
  required DandanplayGateway dandanplay,
}) =>
    [
      TmdbMetadataProvider(HttpMetadataTransport(
          provider: 'tmdb',
          baseUri: Uri.parse('https://api.themoviedb.org'),
          client: tmdb,
          headers: (_) async {
            final secret = await credentials
                .resolve(const CredentialRef('metadata', 'tmdb'));
            return secret.contains('.')
                ? {'Authorization': 'Bearer $secret'}
                : {};
          },
          privateQuery: () async {
            final secret = await credentials
                .resolve(const CredentialRef('metadata', 'tmdb'));
            return secret.contains('.') ? {} : {'api_key': secret};
          })),
      BangumiMetadataProvider(HttpMetadataTransport(
          provider: 'bangumi',
          baseUri: Uri.parse('https://api.bgm.tv'),
          client: bangumi)),
      DandanplayMetadataProvider(HttpMetadataTransport.dandanplay(dandanplay)),
    ];

final class HostVaultResolver implements CredentialResolver {
  const HostVaultResolver(this.vault);
  final CredentialVault vault;
  @override
  Future<String> resolve(CredentialRef ref) async {
    final secret = await vault.read(ref);
    if (secret == null || secret.isEmpty) {
      throw Failure(
          FailureCode.unavailable, '$ref is not configured in the host vault.');
    }
    return secret;
  }
}
