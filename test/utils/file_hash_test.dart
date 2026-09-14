import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/file_hash.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('computeFileHeadMd5 只使用前16MiB进行计算', () async {
    const headSize = defaultFileHeadHashBytes;
    final tempDir = await Directory.systemTemp.createTemp(
      'nipaplay-file-head-hash-test-',
    );
    addTearDown(() async {
      await tempDir.delete(recursive: true);
    });

    final file = File('${tempDir.path}/sample.bin');
    final headBytes = List<int>.generate(headSize, (index) => index % 251);
    final tailBytes = List<int>.filled(4096, 255);
    await file.writeAsBytes(<int>[...headBytes, ...tailBytes], flush: true);

    final expected = md5.convert(headBytes).toString();
    final actual = await computeFileHeadMd5(file.path);
    expect(actual, expected);
  });

  test('computeFileHeadMd5 在文件不存在时抛错', () async {
    await expectLater(
      () => computeFileHeadMd5('/tmp/nipaplay-not-exists-${DateTime.now().microsecondsSinceEpoch}.bin'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
