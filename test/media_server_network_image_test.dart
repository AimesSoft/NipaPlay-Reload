import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/media_server_image_loader.dart';
import 'package:nipaplay/themes/nipaplay/widgets/emby_library_card.dart';
import 'package:nipaplay/widgets/media_server_network_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(clearMediaServerImageMemoryCache);
  tearDown(clearMediaServerImageMemoryCache);

  testWidgets('loads the Emby library image through its media-server loader',
      (tester) async {
    final requestedImages = <Uri>[];
    final imageBytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    final emby = EmbyService.instance
      ..serverUrl = 'http://emby.invalid'
      ..accessToken = 'emby-token'
      ..isConnected = true;
    addTearDown(() {
      emby
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 640,
          height: 360,
          child: EmbyLibraryCard(
            library: EmbyLibrary(
              id: 'library-id',
              name: 'Anime',
              imageTagsPrimary: 'tag',
            ),
            onTap: () {},
            imageLoader: (uri) async {
              requestedImages.add(uri);
              return imageBytes;
            },
          ),
        ),
      ),
    );

    expect(requestedImages, [
      Uri.parse(
        'http://emby.invalid/emby/Items/library-id/Images/Primary?maxWidth=600',
      ),
    ]);
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect((image.image as MemoryImage).bytes, imageBytes);
  });

  testWidgets('uses the image fallback when downloaded bytes cannot decode',
      (tester) async {
    var loaderCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaServerNetworkImage(
          Uri.parse('http://media.invalid/Items/1/Images/Primary'),
          loader: (_) async {
            loaderCalls += 1;
            return Uint8List.fromList([1, 2, 3]);
          },
          errorBuilder: (_, __, ___) => const Text('image fallback'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loaderCalls, 1);
    expect(find.text('image fallback'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the aware network image routes a registered server image loader',
      (tester) async {
    setMediaServerBaseUrl('widget-test', 'http://media.invalid');
    addTearDown(() => setMediaServerBaseUrl('widget-test', null));
    final requestedUris = <Uri>[];
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaServerAwareNetworkImage(
          'http://media.invalid/Items/7/Images/Primary',
          loader: (uri) async {
            requestedUris.add(uri);
            return bytes;
          },
        ),
      ),
    );

    expect(
      requestedUris,
      [Uri.parse('http://media.invalid/Items/7/Images/Primary')],
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect((image.image as MemoryImage).bytes, bytes);
  });

  testWidgets('the aware cached image routes a registered server image loader',
      (tester) async {
    setMediaServerBaseUrl('cached-widget-test', 'http://media.invalid');
    addTearDown(() => setMediaServerBaseUrl('cached-widget-test', null));
    final requestedUris = <Uri>[];
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    Future<Uint8List> loader(Uri uri) async {
      requestedUris.add(uri);
      return bytes;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MediaServerAwareCachedNetworkImage(
          imageUrl: 'http://media.invalid/Items/8/Images/Primary',
          loader: loader,
        ),
      ),
    );

    expect(
      requestedUris,
      [Uri.parse('http://media.invalid/Items/8/Images/Primary')],
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect((image.image as MemoryImage).bytes, bytes);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: MediaServerAwareCachedNetworkImage(
          imageUrl: 'http://media.invalid/Items/8/Images/Primary',
          loader: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(requestedUris, hasLength(1));
  });

  testWidgets('aware image widgets preserve non-media network delegates',
      (tester) async {
    const imageUrl = 'https://lain.bgm.tv/pic/cover/l/example.jpg';

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            MediaServerAwareNetworkImage(
              imageUrl,
              width: 12,
              height: 34,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            const MediaServerAwareCachedNetworkImage(
              imageUrl: imageUrl,
              width: 56,
              height: 78,
              fit: BoxFit.cover,
            ),
          ],
        ),
      ),
    );

    final networkImage = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is NetworkImage,
      ),
    );
    expect(networkImage.image, isA<NetworkImage>());
    expect(networkImage.width, 12);
    expect(networkImage.height, 34);
    expect(networkImage.fit, BoxFit.contain);
    final cachedImage = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    expect(cachedImage.imageUrl, imageUrl);
    expect(cachedImage.width, 56);
    expect(cachedImage.height, 78);
    expect(cachedImage.fit, BoxFit.cover);
  });

  testWidgets('actor avatar preserves its circular placeholder while loading',
      (tester) async {
    setMediaServerBaseUrl('actor-test', 'http://media.invalid');
    addTearDown(() => setMediaServerBaseUrl('actor-test', null));
    final imageBytes = Completer<Uint8List>();
    final requestedUris = <Uri>[];

    await tester.pumpWidget(
      MaterialApp(
        home: MediaServerActorAvatar(
          imageUrl: 'http://media.invalid/Items/actor/Images/Primary',
          size: 64,
          backgroundColor: Colors.deepPurple,
          placeholder: const Icon(Icons.person, key: Key('actor-placeholder')),
          loader: (uri) {
            requestedUris.add(uri);
            return imageBytes.future;
          },
        ),
      ),
    );

    expect(find.byType(ClipOval), findsOneWidget);
    final box = tester
        .widgetList<SizedBox>(
          find.descendant(
            of: find.byType(ClipOval),
            matching: find.byType(SizedBox),
          ),
        )
        .singleWhere((widget) => widget.width == 64 && widget.height == 64);
    expect(box.width, 64);
    expect(box.height, 64);
    expect(find.byKey(const Key('actor-placeholder')), findsOneWidget);
    final background = tester
        .widgetList<ColoredBox>(
          find.descendant(
            of: find.byType(ClipOval),
            matching: find.byType(ColoredBox),
          ),
        )
        .singleWhere((widget) => widget.color == Colors.deepPurple);
    expect(background.color, Colors.deepPurple);

    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    imageBytes.complete(bytes);
    await tester.pumpAndSettle();
    expect(
      requestedUris,
      [Uri.parse('http://media.invalid/Items/actor/Images/Primary')],
    );
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect((image.image as MemoryImage).bytes, bytes);
  });

  testWidgets('actor avatar treats an empty image URL as no image',
      (tester) async {
    var loaderCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaServerActorAvatar(
          imageUrl: '',
          size: 60,
          backgroundColor: Colors.black,
          placeholder: const Icon(Icons.person),
          loader: (_) async {
            loaderCalls += 1;
            return Uint8List(0);
          },
        ),
      ),
    );

    expect(loaderCalls, 0);
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.person), findsOneWidget);
  });

  testWidgets('a synchronous loader failure is evicted and can be retried',
      (tester) async {
    setMediaServerBaseUrl('sync-failure-test', 'http://media.invalid');
    addTearDown(() => setMediaServerBaseUrl('sync-failure-test', null));
    var calls = 0;
    final bytes = Uint8List.fromList(base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    ));
    Future<Uint8List> loader(Uri _) {
      calls += 1;
      if (calls == 1) {
        throw StateError('synchronous failure');
      }
      return Future.value(bytes);
    }

    Widget buildImage() => MaterialApp(
          home: MediaServerNetworkImage(
            Uri.parse('http://media.invalid/Items/retry/Images/Primary'),
            loader: loader,
            errorBuilder: (_, __, ___) => const Text('load failed'),
          ),
        );

    await tester.pumpWidget(buildImage());
    await tester.pumpAndSettle();
    expect(find.text('load failed'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(buildImage());
    await tester.pumpAndSettle();
    expect(calls, 2);
    final image = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
    );
    expect((image.image as MemoryImage).bytes, bytes);
  });
}
