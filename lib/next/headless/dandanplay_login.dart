import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../security/credential_vault.dart';
import '../../services/dandanplay_http_client.dart';
import '../../services/nipaplay_server_router.dart';
import '../harness_redaction.dart';
import 'host_marker.dart';
import 'routing_preferences.dart' as routing;
import 'vault.dart';

const _appId = 'nipaplayv1';

/// `--login-dandanplay`: the person at the host signs in to Dandanplay. The
/// account name is the first line of standard input and the password is the
/// rest, so neither is an argument, in shell history or in a log. The token
/// goes to the host vault (`preferences/dandanplay_token`); only the host's
/// command line can do this, no Action can.
///
/// [server] names the gateway (default: the router's choice from
/// `network.json`). One JSON object goes to [write]; the exit code is 0 when
/// signed in.
Future<int> runHeadlessDandanplayLogin(Directory root,
    {Stream<List<int>>? input,
    void Function(String line)? write,
    Future<String> Function()? server,
    DandanplayHttpClient? client}) async {
  final out = write ?? stdout.writeln;
  void say(Map<String, Object?> value) => out(jsonEncode(value));
  final http = client ?? DandanplayHttpClient(authorization: () => const {});
  try {
    await ensureHeadlessMarker(root);
    final supplied = await utf8.decodeStream(input ?? stdin);
    final newline = supplied.indexOf('\n');
    if (newline < 0) {
      throw const FormatException(
          'Standard input is the account name, a line break, then the password.');
    }
    final username = supplied.substring(0, newline).replaceFirst(RegExp(r'\r$'), '');
    final password = supplied.substring(newline + 1).replaceFirst(RegExp(r'\r?\n$'), '');
    if (username.isEmpty || password.isEmpty) {
      throw const FormatException('The account name and the password are both required.');
    }
    final String base;
    if (server != null) {
      base = await server();
    } else {
      await routing.SharedPreferences.configure(root);
      base = await NipaplayServerRouter.instance.effectiveServer();
    }
    final timestamp = (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    // The gateway holds the real application secret; the client signs with
    // the same placeholder the application does.
    const secret = 'server-managed';
    const path = '/api/v2/login';
    final signature = base64.encode(
        sha256.convert(utf8.encode('$_appId$timestamp$path$secret')).bytes);
    final hash = md5
        .convert(utf8.encode('$_appId$password$timestamp$username$secret'))
        .toString();
    final response = await http.post(
      Uri.parse('${base.replaceFirst(RegExp(r'/+$'), '')}$path'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'NipaPlay/1.0',
        'X-AppId': _appId,
        'X-Signature': signature,
        'X-Timestamp': '$timestamp',
      },
      body: jsonEncode({
        'userName': username,
        'password': password,
        'appId': _appId,
        'unixTimestamp': timestamp,
        'hash': hash,
      }),
    ).timeout(const Duration(seconds: 30));
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    final token = decoded is Map ? decoded['token'] : null;
    if (response.statusCode == 200 && token is String && token.isNotEmpty) {
      if (token.length > 4096 || RegExp(r'\s').hasMatch(token)) {
        throw StateError('The server returned an unusable token.');
      }
      await HeadlessVault(Directory(p.join(root.path, 'vault')))
          .write(const CredentialRef('preferences', 'dandanplay_token'), token);
      say({
        'status': 'signed_in',
        'note': 'Restart a running host so it joins the device network with this account.',
      });
      return 0;
    }
    final message = decoded is Map && decoded['errorMessage'] != null
        ? '${decoded['errorMessage']}'
        : 'HTTP ${response.statusCode}';
    say({'status': 'failed', 'problem': redactHarnessText(message)});
    return 1;
  } catch (error) {
    say({'status': 'failed', 'problem': redactHarnessText('$error')});
    return 1;
  } finally {
    if (client == null) http.close();
  }
}
