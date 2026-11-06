import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/body/next_body.dart';
import 'package:nipaplay/next/body/television_storage.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/television_focus.dart';
import '../security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cache eviction restores identity, certificate, configuration and peer', () async {
    final root = await Directory.systemTemp.createTemp('tvos-body-');
    addTearDown(() async { if (await root.exists()) await root.delete(recursive: true); });
    final vault = MemoryVault();
    const records = {
      'mesh-install-id': '01234567890123456789012345678901',
      'device.json': '{"deviceId":"television"}',
      'mesh-certificate.json': '{"certificate":{"pem":"test-certificate"}}',
      'mesh.json': '{"enabled":true,"name":"客厅电视"}',
      'nipa-peer.json': '{"deviceId":"host"}',
    };
    for (final record in records.entries) {
      await File('${root.path}/${record.key}').writeAsString(record.value);
    }
    await File('${root.path}/next.db').writeAsString('purgeable catalogue');
    await TelevisionStorage.restore(root, vault, television: true);
    // A crash can leave an old cached file after a committed Keychain write.
    await File('${root.path}/mesh.json').writeAsString('{"enabled":false}');
    await TelevisionStorage.restore(root, vault, television: true);
    expect(await File('${root.path}/mesh.json').readAsString(), records['mesh.json']);
    await root.delete(recursive: true);
    await TelevisionStorage.restore(root, vault, television: true);
    for (final record in records.entries) {
      expect(await File('${root.path}/${record.key}').readAsString(), record.value);
    }
    expect(await File('${root.path}/next.db').exists(), isFalse);
    await TelevisionStorage.save('nipa-peer.json', null, vault, television: true);
    await root.delete(recursive: true);
    await TelevisionStorage.restore(root, vault, television: true);
    expect(await File('${root.path}/nipa-peer.json').exists(), isFalse);
  });

  test('television-only storage leaves other platforms and large caches alone', () async {
    final root = await Directory.systemTemp.createTemp('tvos-other-');
    addTearDown(() => root.delete(recursive: true));
    final vault = MemoryVault();
    await TelevisionStorage.save('mesh.json', '{}', vault, television: false);
    await TelevisionStorage.save('next.db', 'large', vault, television: true);
    await TelevisionStorage.restore(root, vault, television: true);
    expect(await root.list().toList(), isEmpty);
    await expectLater(TelevisionStorage.save('mesh.json', 'x' * 65537, vault,
        television: true), throwsStateError);
  });

  test('a television exposes playback and hides downloads and folder scans', () {
    for (final id in ['download.add', 'download.list', 'media.scan',
      'media.library.roots.add', 'media.library.roots.list', 'media.library.scan_classic']) {
      expect(NextBody.excludesOnTelevision(id), isTrue, reason: id);
    }
    for (final id in ['playback.open', 'playback.seek', 'ui.capture',
      'media.sources.list', 'media.sources.play', 'settings.set']) {
      expect(NextBody.excludesOnTelevision(id), isFalse, reason: id);
    }
  });

  testWidgets('remote direction and Select navigate real Next buttons', (tester) async {
    final saved = TelevisionFocusable.isTelevision;
    TelevisionFocusable.isTelevision = () => true;
    addTearDown(() => TelevisionFocusable.isTelevision = saved);
    final activated = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body:
      FocusTraversalGroup(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          NextButton(label: '首页', onTap: () => activated.add('home')),
          NextButton(label: '媒体库', onTap: () => activated.add('library')),
        ]),
        NextButton(label: '播放第 5 集', onTap: () => activated.add('play')),
        const NextButton(label: '不可用'),
      ])),
    )));
    Focus.of(tester.element(find.text('首页'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(activated, ['library']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activated, ['library', 'play']);
    await tester.pumpWidget(const SizedBox());
  });
}
