import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/data/login_requests.dart';

/// A login the agent starts must always reach NipaPlay's own window or end:
/// the Next shell may hold it as a card, but never leaves the job waiting
/// forever, and the secret only comes from the window.
void main() {
  test('shell not on screen: the window opens at once, as before', () async {
    final logins = LoginRequests();
    var shown = 0;
    final result = await logins.request<String>('弹弹play', () async {
      shown++;
      return 'from-window';
    }, Completer<void>().future);
    expect(shown, 1);
    expect(result, 'from-window');
    expect(logins.pending, isEmpty);
  });

  test('shell on screen: a card waits; the button opens the window', () async {
    final logins = LoginRequests()..showing = () => true;
    var shown = 0;
    final future = logins.request<String>('Bangumi', () async {
      shown++;
      return 'from-window';
    }, Completer<void>().future);
    await Future<void>.delayed(Duration.zero);
    expect(shown, 0);
    expect(logins.pending.single.platform, 'Bangumi');
    await logins.open(logins.pending.single);
    expect(await future, 'from-window');
    expect(shown, 1);
    expect(logins.pending, isEmpty);
  });

  test('a cancelled login takes its card away and ends with nothing',
      () async {
    final logins = LoginRequests()..showing = () => true;
    final stopped = Completer<void>();
    final future = logins.request<String>(
        'Emby', () async => fail('no window after cancel'), stopped.future);
    stopped.complete();
    expect(await future, isNull);
    expect(logins.pending, isEmpty);
  });

  test('leaving Next opens the windows of logins still waiting', () async {
    final logins = LoginRequests()..showing = () => true;
    final future = logins.request<String>(
        '弹弹play', () async => 'from-window', Completer<void>().future);
    logins.dispose();
    expect(await future, 'from-window');
  });
}
