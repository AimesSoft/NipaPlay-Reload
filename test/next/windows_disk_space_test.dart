import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/system/windows_disk_space_native.dart';

/// storage.status gives the space of the volume the data and the library
/// folders are on; on Windows it asks kernel32 (there is no `df`).
void main() {
  test('the free and total space of a volume, on a path with Chinese and spaces',
      () async {
    final directory = await Directory.systemTemp.createTemp('磁盘 空间-');
    try {
      final space = windowsDiskSpace(directory.path);
      expect(space, isNotNull);
      expect(space!.total, greaterThan(0));
      expect(space.available, inInclusiveRange(1, space.total));
      expect(windowsDiskSpace(r'Z:\no\such\volume\at\all'), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  }, skip: Platform.isWindows ? null : 'Windows kernel32');
}
