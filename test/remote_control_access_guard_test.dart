import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final request = Request(
      'GET', Uri.parse('http://host/api/remote/control/state'),
      headers: {'x-nipaplay-remote-client-id': 'controller'});

  test('revocation clears trusted and process approvals immediately', () async {
    await RemoteControlSettings.addTrustedDevice(
        {'clientKey': 'id:controller'});
    final guard = RemoteControlAccessGuardService.forTesting(
      approvalPrompt: (_) async => {'approved': false},
    );
    await guard.loadTrustedDevices();
    expect((await guard.evaluate(request, requestAccess: false)).isAuthorized,
        isTrue);
    final removal = guard.removeTrustedDevice('id:controller');
    expect((await guard.evaluate(request, requestAccess: false)).isAuthorized,
        isFalse);
    await removal;
    expect(await RemoteControlSettings.getTrustedDevices(), isEmpty);
    await guard.loadTrustedDevices();
    expect((await guard.evaluate(request, requestAccess: false)).status,
        RemoteControlAccessStatus.required);
  });

  test('obsolete approvals cannot trust again or remove a newer pending prompt',
      () async {
    final prompts = <Completer<Map<String, dynamic>>>[];
    final guard =
        RemoteControlAccessGuardService.forTesting(approvalPrompt: (_) {
      final prompt = Completer<Map<String, dynamic>>();
      prompts.add(prompt);
      return prompt.future;
    });
    await guard.evaluate(request, requestAccess: true);
    await guard.removeTrustedDevice('id:controller');
    await guard.evaluate(request, requestAccess: true);
    prompts.first.complete({'approved': true, 'trusted': true});
    await Future<void>.delayed(Duration.zero);
    expect((await guard.evaluate(request, requestAccess: false)).isAuthorized,
        isFalse);
    expect(await guard.getTrustedDevices(), isEmpty);
    expect(await RemoteControlSettings.getTrustedDevices(), isEmpty);
    expect((await guard.evaluate(request, requestAccess: true)).status,
        RemoteControlAccessStatus.pending);
    expect(prompts, hasLength(2));
    prompts.last.complete({'approved': true, 'trusted': true});
    await Future<void>.delayed(Duration.zero);
    expect((await guard.evaluate(request, requestAccess: false)).isAuthorized,
        isTrue);
    expect(await RemoteControlSettings.getTrustedDevices(), hasLength(1));
  });

  test('obsolete rejection cannot undo a fresh approval', () async {
    final old = Completer<Map<String, dynamic>>();
    var calls = 0;
    final guard = RemoteControlAccessGuardService.forTesting(
        approvalPrompt: (_) =>
            ++calls == 1 ? old.future : Future.value({'approved': true}));
    await guard.evaluate(request, requestAccess: true);
    await guard.removeTrustedDevice('id:controller');
    await guard.evaluate(request, requestAccess: true);
    await Future<void>.delayed(Duration.zero);
    old.complete({'approved': false});
    await Future<void>.delayed(Duration.zero);
    expect((await guard.evaluate(request, requestAccess: false)).isAuthorized,
        isTrue);
  });
}
