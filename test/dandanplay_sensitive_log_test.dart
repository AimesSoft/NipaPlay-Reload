import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_api_service.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shared_preferences/shared_preferences.dart';
import 'security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'WebToken and account URLs stay usable while logs omit credentials and responses',
      () async {
    SharedPreferences.setMockInitialValues(
        {'dandanplay_server_mode': 'hongkong'});
    final previous = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    addTearDown(() => CredentialStore.instance = previous);
    await DandanplayService.saveLoginInfo(
        'synthetic-account-secret', 'fixture', 'fixture');
    addTearDown(DandanplayService.clearLoginInfo);
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = original);
    final requested = <http.Request>[];
    final client = MockClient((request) async {
      requested.add(request);
      expect(
          request.headers['authorization'], 'Bearer synthetic-account-secret');
      return http.Response(
          jsonEncode({
            'success': true,
            'webToken': 'synthetic-web-secret',
            'token': 'synthetic-renew-secret'
          }),
          200);
    });
    await http.runWithClient(() async {
      final data =
          await DandanplayService.getWebToken(business: 'deleteAccount');
      expect(data['webToken'], 'synthetic-web-secret');
      expect(await DandanplayService.startDeleteAccountProcess(),
          contains('webToken=synthetic-web-secret'));
      expect(await DandanplayService.startBangumiManageProcess(),
          contains('webToken=synthetic-web-secret'));
      final renewed = await WebApiService().handleRefreshLoginRequest(shelf.Request(
          'POST',
          Uri.parse(
              'http://user:synthetic-password@host/api/dandanplay/refresh_login?key=synthetic-query')));
      expect(
          (jsonDecode(await renewed.readAsString()) as Map)['success'], true);
    }, () => client);
    expect(requested, hasLength(4));
    expect(logs.join('\n'), isNot(contains('synthetic-')));
    expect(logs.join('\n'), isNot(contains('https://')));
  });

  test('upstream errors cannot inject a credential into account diagnostics',
      () async {
    SharedPreferences.setMockInitialValues(
        {'dandanplay_server_mode': 'hongkong'});
    final previous = CredentialStore.instance;
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    addTearDown(() => CredentialStore.instance = previous);
    await DandanplayService.saveLoginInfo(
        'synthetic-account-secret', 'fixture', 'fixture');
    addTearDown(DandanplayService.clearLoginInfo);
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = original);
    await http.runWithClient(() async {
      await expectLater(
          DandanplayService.startDeleteAccountProcess(), throwsException);
    },
        () => MockClient((_) async => http.Response(
            'synthetic-secret-body', 400,
            headers: {'x-error-message': 'synthetic-secret-error'})));
    expect(logs.join('\n'), isNot(contains('synthetic-')));
  });
}
