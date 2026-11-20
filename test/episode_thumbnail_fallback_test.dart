import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_episode_rail.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory cacheDirectory;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cacheDirectory =
        Directory.systemTemp.createTempSync('nipaplay-still-cache-');
    StorageService.debugAppStorageDirectoryOverride = cacheDirectory;
  });
  tearDown(() {
    ImageCacheManager.instance.clear();
    StorageService.debugAppStorageDirectoryOverride = null;
    cacheDirectory.deleteSync(recursive: true);
  });
  const url = 'https://image.tmdb.org/t/p/w300/still.jpg';
  Future<void> showCard(WidgetTester tester, {String? path}) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(
          child: SizedBox(
        width: 250,
        height: 220,
        child: ImmersiveEpisodeCard(
            episodeLabel: '第1话',
            title: '',
            onTap: () {},
            thumbnailPath: path,
            fallbackThumbnailUrl: url),
      )),
    ));
  }

  testWidgets('unplayed and missing local screenshots use the TMDB still',
      (tester) async {
    await showCard(tester);
    expect(
        tester
            .widget<CachedNetworkImageWidget>(
                find.byType(CachedNetworkImageWidget))
            .imageUrl,
        url);
    await showCard(tester, path: '/missing/nipaplay/screenshot.jpg');
    expect(
        tester
            .widget<CachedNetworkImageWidget>(
                find.byType(CachedNetworkImageWidget))
            .imageUrl,
        url);
    await tester.pumpWidget(const SizedBox.shrink());
    ImageCacheManager.instance.clear();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('existing playback screenshot takes priority', (tester) async {
    final dir = Directory.systemTemp.createTempSync('nipaplay-still-test-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/played.png')
      ..writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII='));
    await showCard(tester, path: file.path);
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CachedNetworkImageWidget), findsNothing);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
