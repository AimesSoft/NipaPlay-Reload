import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart' show JsonMap;

import '../../security/credential_vault.dart';
import '../../security/secret_redactor.dart';
import '../chat/dsh_runtime.dart';
import '../chat/model_launch.dart';
import '../settings/responses_probe.dart';
import '../ui_data/host_settings.dart' show UiModelCheck;

/// The model Nipa thinks with on a headless host: provider, address, model
/// and wire API in `<data>/model.json`, the key in the host vault. It is the
/// same record the desktop settings page keeps (same file, same vault
/// reference), so what one writes the other reads.
///
/// Only the person at the host sets it (the command line); it is not an
/// Action or a setting, so Nipa cannot change her own model or read the key.
final class HeadlessModel {
  HeadlessModel({required this.root, required this.vault});

  final Directory root;
  final CredentialVault vault;

  File get file => File('${root.path}/model.json');

  /// Where the key of [value] is kept in the vault. Bound to the data
  /// directory, provider and address, so a key is never sent to an address it
  /// was not entered for. Identical to the desktop's reference.
  static CredentialRef keyRef(Directory root, JsonMap value) => CredentialRef(
      'next_model',
      sha256
          .convert(utf8.encode(jsonEncode(
              [root.absolute.path, value['provider'], value['baseUrl']])))
          .toString());

  Future<JsonMap> read() async {
    if (!await file.exists()) return {};
    try {
      return Map<String, Object?>.from(
          jsonDecode(await file.readAsString()) as Map);
    } on FormatException {
      return {};
    }
  }

  Future<String?> _key(JsonMap value) async {
    if (value['provider'] == null || value['baseUrl'] == null) return null;
    final ref = keyRef(root, value);
    final key = await vault.read(ref);
    if (key != null && key.isNotEmpty) SecretRedactor.remember(ref, key);
    return key;
  }

  static String _text(String? value, String field) {
    if (value == null ||
        value.trim().isEmpty ||
        value.length > 512 ||
        value.contains(RegExp(r'[\x00-\x1f]')) ||
        SecretRedactor.text(value) != value) {
      throw FormatException('$field is not valid.');
    }
    return value.trim();
  }

  static Uri _url(String? value) {
    final uri = Uri.tryParse(_text(value, 'Address'));
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
          'The address must be an HTTP or HTTPS address without credentials, query or fragment.');
    }
    return uri;
  }

  /// What is set and what is missing, without the key.
  Future<HeadlessModelFacts> facts() async {
    final value = await read();
    final hasAddress = value['baseUrl'] is String &&
        value['model'] is String &&
        value['provider'] is String;
    final key = hasAddress ? await _key(value) : null;
    final hasKey = key != null && key.isNotEmpty;
    return HeadlessModelFacts(
        provider: value['provider'] as String?,
        baseUrl: value['baseUrl'] as String?,
        model: value['model'] as String?,
        api: value['api'] == 'chat' ? 'chat' : 'responses',
        reasoning: value['reasoning'] as String?,
        revision: value['revision'] as int? ?? 0,
        keyConfigured: hasKey,
        missing: [if (!hasAddress) 'model', if (!hasKey) 'key']);
  }

  /// Saves the choice. [key] is written to the vault first (and read back),
  /// then the record, so a watcher that sees the record finds the key.
  /// A null [key] keeps the key already kept for the same provider and
  /// address; an empty one removes it.
  Future<HeadlessModelFacts> save(
      {String? provider,
      required String baseUrl,
      required String model,
      String api = 'responses',
      String? reasoning,
      String? key}) async {
    if (!const {'responses', 'chat'}.contains(api)) {
      throw const FormatException('The API must be responses or chat.');
    }
    if (reasoning != null &&
        reasoning.isNotEmpty &&
        !const {'low', 'medium', 'high'}.contains(reasoning)) {
      throw const FormatException('Reasoning must be low, medium or high.');
    }
    final before = await read();
    final value = <String, Object?>{
      ...before,
      'source': 'nipaplay',
      'revision': (before['revision'] as int? ?? 0) + 1,
      'provider': _text(
          provider != null && provider.trim().isNotEmpty ? provider : 'custom',
          'Provider'),
      'baseUrl': _url(baseUrl).toString().replaceFirst(RegExp(r'/$'), ''),
      'model': _text(model, 'Model'),
      'api': api,
    };
    if (reasoning != null) {
      if (reasoning.isEmpty) {
        value.remove('reasoning');
      } else {
        value['reasoning'] = reasoning;
      }
    }
    if (key != null) {
      if (key.contains(RegExp(r'[\x00-\x20]')) || key.length > 16384) {
        throw const FormatException('The key is not valid.');
      }
      final ref = keyRef(root, value);
      if (key.isEmpty) {
        await vault.delete(ref);
      } else {
        SecretRedactor.remember(ref, key);
        await vault.write(ref, key);
        if (await vault.read(ref) != key) {
          throw StateError('The vault did not keep the key.');
        }
      }
    }
    await _save(value);
    return facts();
  }

  /// Removes the record and the key kept for it.
  Future<void> clear() async {
    final value = await read();
    if (value['provider'] != null && value['baseUrl'] != null) {
      await vault.delete(keyRef(root, value));
    }
    if (await file.exists()) await file.delete();
  }

  Future<void> _save(JsonMap value) async {
    await root.create(recursive: true);
    final pending = File('${file.path}.pending');
    await pending.writeAsString(jsonEncode(value), flush: true);
    await pending.rename(file.path);
  }

  /// The launch snapshot a conversation host starts DeepSeek Harness with.
  /// Throws [HeadlessModelMissing] while the model or its key is not set.
  Future<ModelLaunch> launch() async {
    final value = await read();
    final facts = await this.facts();
    if (facts.missing.isNotEmpty) throw HeadlessModelMissing(facts.missing);
    final key = (await _key(value))!;
    final model = _text(value['model'] as String?, 'Model');
    final chat = value['api'] == 'chat';
    final base = _url(value['baseUrl'] as String?);
    final url = chat ? chatBase(base) : responsesBase(base);
    return ModelLaunch(
        revision: value['revision'] as int? ?? 0,
        model: model,
        provider: DshRoute.provider,
        route: DshRoute(
            baseUrl: url.toString().replaceFirst(RegExp(r'/$'), ''),
            model: model,
            key: key,
            api: chat ? 'openai-completions' : 'openai-responses',
            reasoningEffort: value['reasoning'] as String?,
            compat: (value['compat'] as Map?)?.cast<String, Object?>()));
  }

  /// One small request to the model, to see whether the address, model and
  /// key work. The key is only ever sent to the saved address.
  Future<UiModelCheck> check({HttpClient Function()? httpClient}) async {
    final value = await read();
    final facts = await this.facts();
    if (facts.missing.isNotEmpty) {
      return UiModelCheck(ok: false, message: facts.missing.contains('model')
          ? 'The model is not set.'
          : 'The key is not set.');
    }
    final key = (await _key(value))!;
    final client = (httpClient ?? HttpClient.new)();
    final watch = Stopwatch()..start();
    try {
      client.connectionTimeout = const Duration(seconds: 15);
      final base = _url(value['baseUrl'] as String?);
      final model = _text(value['model'] as String?, 'Model');
      final result = await (value['api'] == 'chat'
              ? probeChatCompletions(client, base, model, key)
              : probeResponses(client, base, model, key))
          .timeout(const Duration(seconds: 30));
      return UiModelCheck(
          ok: result.ok,
          message: result.message,
          latency: result.latency ?? watch.elapsed);
    } on TimeoutException {
      return UiModelCheck(
          ok: false,
          message: 'The server did not answer in time.',
          latency: watch.elapsed);
    } on SocketException {
      return UiModelCheck(
          ok: false,
          message: 'Cannot reach the server.',
          latency: watch.elapsed);
    } on HandshakeException {
      return UiModelCheck(
          ok: false,
          message: 'The server certificate cannot be verified.',
          latency: watch.elapsed);
    } on HttpException {
      return UiModelCheck(
          ok: false,
          message: 'The server connection was interrupted.',
          latency: watch.elapsed);
    } finally {
      client.close(force: true);
    }
  }
}

/// The model setup as facts. Never carries the key.
final class HeadlessModelFacts {
  const HeadlessModelFacts(
      {this.provider,
      this.baseUrl,
      this.model,
      this.api = 'responses',
      this.reasoning,
      this.revision = 0,
      this.keyConfigured = false,
      this.missing = const []});
  final String? provider, baseUrl, model, reasoning;
  final String api;
  final int revision;
  final bool keyConfigured;

  /// `model` (address, model name or provider not set) and/or `key`.
  final List<String> missing;
  bool get ready => missing.isEmpty;

  JsonMap toJson() => {
        'provider': provider,
        'baseUrl': baseUrl,
        'model': model,
        'api': api,
        'reasoning': reasoning,
        'keyConfigured': keyConfigured,
        'ready': ready,
        if (missing.isNotEmpty) 'missing': missing,
      };
}

/// Starting needs a model or a key that is not there yet.
final class HeadlessModelMissing implements Exception {
  HeadlessModelMissing(this.missing)
      : message = missing.contains('model')
            ? 'No model is set up on this host; run --model-set.'
            : 'The model key is not set on this host; run --model-set with --key-stdin.';
  final List<String> missing;
  final String message;
  @override
  String toString() => message;
}
