import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/body/television_storage.dart';

void main() {
  test('电视升级迁移图片容器；缓存清理后不再返回失效封面', () async {
    final root = await Directory.systemTemp.createTemp('tv-artwork-');
    addTearDown(() => root.delete(recursive: true));
    final image = File('${root.path}/source-artwork/cover');
    await image.parent.create();
    await image.writeAsBytes([1, 2, 3]);
    const previous = '/previous-container/next/source-artwork/cover';
    expect(await TelevisionStorage.cachedArtwork(root, previous), image.path);
    expect(await TelevisionStorage.cachedArtwork(root, image.path), image.path);
    await image.delete();
    expect(await TelevisionStorage.cachedArtwork(root, previous), isNull);
    expect(await TelevisionStorage.cachedArtwork(root, '/unrelated/cover'), isNull);
  });
}
