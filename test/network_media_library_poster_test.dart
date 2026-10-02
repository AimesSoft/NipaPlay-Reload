import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  Directory? previousStorageDirectory;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('nipaplay_poster_test');
    previousStorageDirectory = StorageService.debugAppStorageDirectoryOverride;
    StorageService.debugAppStorageDirectoryOverride = tempDir;
    // Initialize the singleton outside the widget test's fake timer zone.
    ImageCacheManager.instance.clear();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'NipaPlay',
      packageName: 'nipaplay',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    JellyfinService.instance
      ..serverUrl = 'http://jellyfin.test'
      ..accessToken = 'test-token'
      ..userId = 'user'
      ..currentProfile = null
      ..selectedLibraryIds = []
      ..isConnected = true;
    EmbyService.instance
      ..serverUrl = 'http://emby.test'
      ..accessToken = 'test-token'
      ..userId = 'user'
      ..currentProfile = null
      ..selectedLibraryIds = []
      ..isConnected = true;
  });

  tearDown(() {
    ImageCacheManager.instance.clear();
    JellyfinService.instance
      ..serverUrl = null
      ..accessToken = null
      ..userId = null
      ..isConnected = false;
    EmbyService.instance
      ..serverUrl = null
      ..accessToken = null
      ..userId = null
      ..isConnected = false;
  });

  tearDownAll(() async {
    StorageService.debugAppStorageDirectoryOverride = previousStorageDirectory;
    await tempDir.delete(recursive: true);
  });

  for (final server in NetworkMediaServerType.values) {
    testWidgets('${server.name} folders and media display available posters',
        (tester) async {
      final fixture = _PosterFixture(server, [
        _item('series', 'Series', true, hasImage: true),
        _item('season', 'Season', true, hasImage: true),
        _item('folder', 'Folder', true, hasImage: true),
        _item('movie', 'Movie', false, hasImage: true),
      ]);
      await tester.runAsync(() => fixture.seedPosters());
      await http.runWithClient(() async {
        await _openLibrary(tester, server);
        final images = tester.widgetList<CachedNetworkImageWidget>(
          find.byType(CachedNetworkImageWidget),
        );
        expect(
            images.map((image) => image.imageUrl),
            unorderedEquals(
                fixture.items.map((item) => fixture.imageUrl(item))));
        expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .where((image) => image.image != null),
          hasLength(4),
        );
        expect(find.byIcon(Icons.folder_open_rounded), findsNothing);
        await _disposeLibrary(tester);
      }, () => MockClient(fixture.handleRequest));
    });

    testWidgets('${server.name} missing posters use the correct fallback',
        (tester) async {
      final fixture = _PosterFixture(server, [
        _item('empty-folder', 'Folder', true),
        _item('empty-movie', 'Movie', false),
      ]);
      await http.runWithClient(() async {
        await _openLibrary(tester, server);
        expect(find.byType(CachedNetworkImageWidget), findsNothing);
        _expectFallback('empty-folder', Icons.folder_open_rounded);
        _expectFallback('empty-movie', Icons.movie_creation_outlined);
        expect(fixture.imageRequests, isEmpty);
        await _disposeLibrary(tester);
      }, () => MockClient(fixture.handleRequest));
    });

    testWidgets('${server.name} failed posters use the correct fallback',
        (tester) async {
      final fixture = _PosterFixture(server, [
        _item('broken-folder', 'Folder', true, hasImage: true),
        _item('broken-movie', 'Movie', false, hasImage: true),
      ]);
      await http.runWithClient(() async {
        await _openLibrary(tester, server);
        // Let disk-cache misses and failed HTTP requests finish in real time.
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
          if (find.byIcon(Icons.folder_open_rounded).evaluate().isNotEmpty &&
              find
                  .byIcon(Icons.movie_creation_outlined)
                  .evaluate()
                  .isNotEmpty) {
            break;
          }
        }
        expect(find.byType(CachedNetworkImageWidget), findsNWidgets(2));
        _expectFallback('broken-folder', Icons.folder_open_rounded);
        _expectFallback('broken-movie', Icons.movie_creation_outlined);
        expect(fixture.imageRequests,
            containsAll(['broken-folder', 'broken-movie']));
        await _disposeLibrary(tester);
      }, () => MockClient(fixture.handleRequest));
    });
  }
}

Map<String, dynamic> _item(String id, String type, bool isFolder,
        {bool hasImage = false}) =>
    {
      'Id': id,
      'Name': id,
      'Type': type,
      'IsFolder': isFolder,
      'DateCreated': '2026-01-01T00:00:00Z',
      if (hasImage) 'ImageTags': {'Primary': 'poster-tag'},
    };

Future<void> _openLibrary(
    WidgetTester tester, NetworkMediaServerType server) async {
  await tester.binding.setSurfaceSize(const Size(1920, 1080));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<JellyfinProvider>(
          create: (_) => _JellyfinProvider()),
      ChangeNotifierProvider<EmbyProvider>(create: (_) => _EmbyProvider()),
      ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
      ChangeNotifierProvider(create: (_) => LargeScreenUiSfxService()),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: NipaplayLargeScreenModeScope(
        isActive: true,
        child: Scaffold(body: NetworkMediaLibraryView(serverType: server)),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Test library'));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
}

Future<void> _disposeLibrary(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  // Drain retries already scheduled by the image widget before disposal.
  await tester.pump(const Duration(seconds: 2));
}

void _expectFallback(String title, IconData icon) {
  final card = find.ancestor(
    of: find.text(title),
    matching: find.byType(NipaplayLargeScreenFocusableAction),
  );
  expect(
      find.descendant(of: card, matching: find.byIcon(icon)), findsOneWidget);
  expect(
      find.descendant(of: card, matching: find.byType(RawImage)), findsNothing);
}

class _JellyfinProvider extends JellyfinProvider {
  @override
  List<String> get selectedLibraryIds => ['library'];

  @override
  List<JellyfinLibrary> get availableLibraries => [
        JellyfinLibrary(id: 'library', name: 'Test library', type: 'tvshows'),
      ];
}

class _EmbyProvider extends EmbyProvider {
  @override
  List<String> get selectedLibraryIds => ['library'];

  @override
  List<EmbyLibrary> get availableLibraries => [
        EmbyLibrary(id: 'library', name: 'Test library', type: 'tvshows'),
      ];
}

class _PosterFixture {
  _PosterFixture(this.server, this.items);

  final NetworkMediaServerType server;
  final List<Map<String, dynamic>> items;
  final List<String> imageRequests = [];

  String imageUrl(Map<String, dynamic> item) =>
      server == NetworkMediaServerType.jellyfin
          ? JellyfinService.instance.getImageUrl(item['Id'], width: 460)
          : EmbyService.instance.getImageUrl(item['Id'], width: 460);

  Future<void> seedPosters() async {
    final appDir = await StorageService.getAppStorageDirectory();
    final cacheDir = Directory('${appDir.path}/compressed_images');
    await cacheDir.create(recursive: true);
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    for (final item in items) {
      final url = imageUrl(item);
      final key = sha256.convert(utf8.encode(url));
      await File('${cacheDir.path}/$key.jpg').writeAsBytes(bytes);
      await ImageCacheManager.instance.loadImage(url);
    }
  }

  Future<http.Response> handleRequest(http.Request request) async {
    final path = request.url.path.startsWith('/emby/')
        ? request.url.path.substring('/emby'.length)
        : request.url.path;
    if (path.contains('/Images/')) {
      final segments = request.url.pathSegments;
      imageRequests.add(segments[segments.indexOf('Items') + 1]);
      return http.Response('', 404);
    }
    if (path == '/Users/user/Items/library') {
      return http.Response(jsonEncode({'CollectionType': 'tvshows'}), 200);
    }
    if (path == '/Items') {
      return http.Response(jsonEncode({'Items': items}), 200);
    }
    throw StateError('Unexpected request: ${request.url}');
  }
}
