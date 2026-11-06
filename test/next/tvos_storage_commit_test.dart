import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/body/television_storage.dart';
import '../security/memory_vault.dart';

void main() {
  test('清除梨花选择后崩溃，旧缓存不能复活选择；按 UTF-8 字节限制记录', () async {
    final root = await Directory.systemTemp.createTemp('tv-commit-');
    addTearDown(() => root.delete(recursive: true));
    final vault = MemoryVault();
    final cached = File('${root.path}/nipa-peer.json');
    await cached.writeAsString('{"deviceId":"previous-host"}');
    await TelevisionStorage.restore(root, vault, television: true);
    await TelevisionStorage.save('nipa-peer.json', null, vault, television: true);
    // Simulate process death between the Keychain commit and deleting the file.
    expect(await cached.exists(), isTrue);
    await TelevisionStorage.restore(root, vault, television: true);
    expect(await cached.exists(), isFalse);
    await expectLater(TelevisionStorage.save('mesh.json', '电视' * 12000, vault,
        television: true), throwsStateError);
  });
}
