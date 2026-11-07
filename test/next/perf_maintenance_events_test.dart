import 'dart:async';
import 'dart:convert';
import 'dart:io';

// 由 flutter_test 提供。
// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/mesh/credential_watch.dart';
import 'package:nipaplay/next/headless/vault.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/system/credential_changes.dart';
import 'package:nipaplay/next/system/foreground.dart';
import 'package:nipaplay/next/system/foreground_broadcast.dart';
import 'package:nipaplay/next/system/midnight_refresh.dart';
import 'package:nipaplay/next/system/network_watch.dart';
import 'package:nipaplay/next/system/network_changes_flutter.dart';
import 'package:nipaplay/security/credential_vault.dart';

String _token(DateTime expiry) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({
          'exp': expiry.millisecondsSinceEpoch ~/ 1000,
        })))}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => NextForeground.setActive(true));
  tearDown(() => NextForeground.setActive(true));

  test('本地午夜只触发一次，后台取消，恢复后等待下一个午夜', () {
    fakeAsync((clock) {
      final now = clock.getClock(DateTime(2026, 11, 8, 23, 59, 50)).now;
      var refreshes = 0;
      final midnight = MidnightRefresh(() => refreshes++, now: now)..start();
      expect(clock.periodicTimerCount, 0);
      clock.elapse(const Duration(seconds: 9));
      expect(refreshes, 0);
      clock.elapse(const Duration(seconds: 1));
      expect(refreshes, 1);
      clock.elapse(const Duration(seconds: 60));
      expect(refreshes, 1);
      NextForeground.setActive(false);
      expect(clock.nonPeriodicTimerCount, 0);
      clock.elapse(const Duration(days: 2));
      expect(refreshes, 1);
      NextForeground.setActive(true);
      clock.elapse(const Duration(hours: 23, minutes: 59));
      expect(refreshes, 2);
      midnight.close();
      clock.flushMicrotasks();
      expect(clock.nonPeriodicTimerCount, 0);
    });
  });

  test('系统网络事件不轮询，后台解除订阅，回前台补查一次', () {
    fakeAsync((clock) {
      final events = StreamController<void>.broadcast(sync: true);
      var checks = 0;
      final watch =
          ForegroundNetworkWatch(() => checks++, events: events.stream)
            ..start();
      expect(checks, 1);
      clock.elapse(const Duration(seconds: 60));
      expect(checks, 1);
      expect(clock.periodicTimerCount, 0);
      events.add(null);
      expect(checks, 2);
      NextForeground.setActive(false);
      clock.flushMicrotasks();
      expect(events.hasListener, false);
      events.add(null);
      clock.elapse(const Duration(minutes: 1));
      expect(checks, 2);
      NextForeground.setActive(true);
      expect(checks, 3);
      watch.close();
      clock.flushMicrotasks();
      expect(events.hasListener, false);
      events.close();
      clock.flushMicrotasks();
    });
  });

  test('无系统网络事件的平台只在前台保留兼容检查', () {
    fakeAsync((clock) {
      var checks = 0;
      final watch = ForegroundNetworkWatch(() => checks++, events: null)
        ..start();
      clock.elapse(const Duration(seconds: 10));
      expect(checks, 3);
      NextForeground.setActive(false);
      clock.elapse(const Duration(minutes: 1));
      expect(checks, 3);
      expect(clock.periodicTimerCount, 0);
      NextForeground.setActive(true);
      expect(checks, 4);
      watch.close();
      clock.flushMicrotasks();
    });
  });

  test('凭据成功提交才通知，稳定登录不按秒读令牌', () {
    fakeAsync((clock) {
      var checks = 0;
      final previous = SettingsAccess.registry;
      SettingsAccess.registry = null;
      final watch = MeshCredentialWatch(() => checks++)..start();
      clock.elapse(const Duration(minutes: 1));
      expect(checks, 0);
      SettingsAccess.persist('unrelated', () async => true);
      SettingsAccess.persist('dandanplay_token', () async => false);
      clock.flushMicrotasks();
      expect(checks, 0);
      SettingsAccess.persist('dandanplay_token', () async => true);
      clock.flushMicrotasks();
      expect(checks, 1);
      CredentialChanges.committed(
          const CredentialRef('preferences', 'dandanplay_token'));
      clock.flushMicrotasks();
      expect(checks, 2);
      NextForeground.setActive(false);
      clock.elapse(const Duration(minutes: 2));
      expect(checks, 2);
      NextForeground.setActive(true);
      expect(checks, 3);
      expect(clock.periodicTimerCount, 0);
      watch.close();
      clock.flushMicrotasks();
      SettingsAccess.registry = previous;
    });
  });

  test('到期前截止点对同一凭据仅触发一次，后台到期留到前台处理', () {
    fakeAsync((clock) {
      final now = clock.getClock(DateTime.utc(2026, 11, 8)).now;
      var checks = 0;
      final watch = MeshCredentialWatch(() => checks++, now: now)..start();
      final token = _token(now().add(const Duration(minutes: 2)));
      watch.observed(token);
      clock.elapse(const Duration(seconds: 59));
      expect(checks, 0);
      clock.elapse(const Duration(seconds: 1));
      expect(checks, 1);
      watch.observed(token);
      clock.elapse(const Duration(minutes: 10));
      expect(checks, 1);
      watch.observed(_token(now().add(const Duration(minutes: 2))));
      NextForeground.setActive(false);
      clock.elapse(const Duration(minutes: 3));
      expect(checks, 1);
      NextForeground.setActive(true);
      clock.elapse(Duration.zero);
      expect(checks, 2); // 回前台一次读取同时覆盖错过的截止点。
      watch.observed('malformed');
      expect(watch.pending, false);
      watch.close();
      clock.flushMicrotasks();
    });
  });

  test('无界面凭据写入和删除发布引用，失败或读取不产生通知', () async {
    final root = await Directory.systemTemp.createTemp('perf-headless-vault-');
    final vault = HeadlessVault(root);
    final refs = <CredentialRef>[];
    final subscription = CredentialChanges.changes.listen(refs.add);
    const ref = CredentialRef('preferences', 'dandanplay_token');
    try {
      await vault.write(ref, 'synthetic-test-token');
      expect(await vault.read(ref), 'synthetic-test-token');
      await vault.delete(ref);
      await Future<void>.delayed(Duration.zero);
      expect(refs, [ref, ref]);
    } finally {
      await subscription.cancel();
      await root.delete(recursive: true);
    }
  });

  test('移动设备后台不广播，恢复立即广播；桌面后台维持原频率', () {
    fakeAsync((clock) {
      var mobile = 0, desktop = 0;
      final handheld = ForegroundBroadcast(() => mobile++, foregroundOnly: true)
        ..start();
      final host = ForegroundBroadcast(() => desktop++, foregroundOnly: false)
        ..start();
      clock.elapse(const Duration(seconds: 30));
      expect(mobile, 2);
      expect(desktop, 2);
      NextForeground.setActive(false);
      clock.elapse(const Duration(minutes: 1));
      expect(mobile, 2);
      expect(desktop, 4);
      NextForeground.setActive(true);
      expect(mobile, 3);
      expect(desktop, 4);
      handheld.close();
      host.close();
      clock.flushMicrotasks();
      expect(clock.periodicTimerCount, 0);
    });
  });

  test('原生网络监视器由多个订阅共享，最后一个离开才停止', () async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final methods = <String>[];
    const channel = SystemNetworkChanges.channel;
    messenger.setMockMethodCallHandler(channel,
        (call) async {
      methods.add(call.method);
      return null;
    });
    var first = 0, second = 0;
    final one = SystemNetworkChanges.changes!.listen((_) => first++);
    final two = SystemNetworkChanges.changes!.listen((_) => second++);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['start']);
    await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('changed')),
        null);
    await Future<void>.delayed(Duration.zero);
    expect(first, 1);
    expect(second, 1);
    await one.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['start']);
    await two.cancel();
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['start', 'stop']);
    messenger.setMockMethodCallHandler(channel, null);
  }, skip: !Platform.isMacOS && !Platform.isIOS);
}
