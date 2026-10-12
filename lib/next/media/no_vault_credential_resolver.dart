import 'dart:io';
import 'metadata_provider.dart';
import 'package:nipa_harness/nipa_harness.dart';

final class VaultCredentialResolver implements CredentialResolver {
  VaultCredentialResolver(Directory root);
  @override
  Future<String> resolve(CredentialRef ref) async => throw Failure(
      FailureCode.unavailable, '$ref requires a configured headless vault.');
}
