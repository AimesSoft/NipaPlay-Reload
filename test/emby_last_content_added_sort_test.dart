import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_library_sort_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sortBy = 'DateLastContentAdded';

  test('Emby exposes last episode added with both sort orders', () {
    final option = getMediaSortOptions(
      MediaLibraryType.emby,
    ).singleWhere((option) => option.value == sortBy);

    expect(option.label, '最后一集添加时间');
    expect(option.description, '按最后一集添加时间排序');
    expect(
      getMediaSortOptions(
        MediaLibraryType.jellyfin,
      ).where((option) => option.value == sortBy),
      isEmpty,
    );
    expect(mediaLibrarySortOrders, <Map<String, String>>[
      <String, String>{'value': 'Ascending', 'label': '升序'},
      <String, String>{'value': 'Descending', 'label': '降序'},
    ]);
  });

  test('Emby provider sends last-content sorting to the HTTP API', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/emby/Users/test-user/Items/library-id') {
        request.response.write('{"CollectionType":"tvshows"}');
      } else if (request.uri.path == '/emby/Items') {
        request.response.write('{"Items":[],"TotalRecordCount":0}');
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });

    final service = EmbyService.instance;
    final previousServerUrl = service.serverUrl;
    final previousUserId = service.userId;
    final previousAccessToken = service.accessToken;
    final previousConnected = service.isConnected;
    final previousProfile = service.currentProfile;
    final provider = EmbyProvider();
    addTearDown(() async {
      provider.dispose();
      await server.close(force: true);
      service.currentProfile = previousProfile;
      service.serverUrl = previousServerUrl;
      service.userId = previousUserId;
      service.accessToken = previousAccessToken;
      service.isConnected = previousConnected;
      SharedPreferences.setMockInitialValues({});
    });

    service.currentProfile = null;
    service.serverUrl = 'http://${server.address.address}:${server.port}';
    service.userId = 'test-user';
    service.accessToken = 'test-token';
    service.isConnected = true;
    provider.setLibrarySortSettings('library-id', sortBy, 'Descending');

    await HttpOverrides.runWithHttpOverrides(
      () => provider.fetchMediaItemsForLibrary('library-id', limit: 37),
      _RealHttpOverrides(),
    );

    final itemsRequest = requests.singleWhere(
      (uri) => uri.path == '/emby/Items',
    );
    expect(itemsRequest.queryParameters['ParentId'], 'library-id');
    expect(itemsRequest.queryParameters['SortBy'], sortBy);
    expect(itemsRequest.queryParameters['SortOrder'], 'Descending');
    expect(itemsRequest.queryParameters['Limit'], '37');
  });

  test('large Emby sorted libraries are fetched in bounded pages', () async {
    SharedPreferences.setMockInitialValues({});
    const totalItems = 201;
    final itemRequests = <Uri>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/emby/Users/test-user/Items/library-id') {
        request.response.write('{"CollectionType":"tvshows"}');
      } else if (request.uri.path == '/emby/Items') {
        itemRequests.add(request.uri);
        final startIndex =
            int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ?? 0;
        final requestedLimit =
            int.tryParse(request.uri.queryParameters['Limit'] ?? '') ??
                totalItems;
        final remaining = totalItems - startIndex;
        final count = remaining <= 0
            ? 0
            : (remaining < requestedLimit ? remaining : requestedLimit);
        request.response.write(
          jsonEncode({
            'Items': [
              for (var index = 0; index < count; index++)
                {
                  'Id': 'item-${startIndex + index}',
                  'Name': 'Item ${startIndex + index}',
                  'Type': 'Series',
                  'DateCreated': '2026-01-01T00:00:00Z',
                },
            ],
            'TotalRecordCount': totalItems,
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });

    final service = EmbyService.instance;
    final previousServerUrl = service.serverUrl;
    final previousUserId = service.userId;
    final previousAccessToken = service.accessToken;
    final previousConnected = service.isConnected;
    final previousProfile = service.currentProfile;
    addTearDown(() async {
      await server.close(force: true);
      service.currentProfile = previousProfile;
      service.serverUrl = previousServerUrl;
      service.userId = previousUserId;
      service.accessToken = previousAccessToken;
      service.isConnected = previousConnected;
      SharedPreferences.setMockInitialValues({});
    });

    service.currentProfile = null;
    service.serverUrl = 'http://${server.address.address}:${server.port}';
    service.userId = 'test-user';
    service.accessToken = 'test-token';
    service.isConnected = true;

    final items = await HttpOverrides.runWithHttpOverrides(
      () => service.getLatestMediaItemsByLibrary(
        'library-id',
        limit: 99999,
        sortBy: sortBy,
        sortOrder: 'Descending',
      ),
      _RealHttpOverrides(),
    );

    expect(items, hasLength(totalItems));
    expect(itemRequests.length, greaterThan(1));
    final startIndices = itemRequests
        .map(
          (uri) => int.tryParse(uri.queryParameters['StartIndex'] ?? '') ?? 0,
        )
        .toList();
    final pageLimits = itemRequests
        .map((uri) => int.parse(uri.queryParameters['Limit']!))
        .toList();
    expect(startIndices.first, 0);
    for (var index = 1; index < startIndices.length; index++) {
      expect(
        startIndices[index],
        startIndices[index - 1] + pageLimits[index - 1],
      );
    }
    expect(pageLimits, everyElement(lessThanOrEqualTo(200)));
    expect(
      itemRequests.map((uri) => uri.queryParameters['SortBy']).toSet(),
      <String>{sortBy},
    );
    expect(
      itemRequests.map((uri) => uri.queryParameters['SortOrder']).toSet(),
      <String>{'Descending'},
    );
  });

  testWidgets('selecting the Emby sort option uses bounded library requests', (
    tester,
  ) async {
    await HttpOverrides.runWithHttpOverrides(() async {
      SharedPreferences.setMockInitialValues({});
      const totalItems = 201;
      final sortedItemRequests = <Uri>[];
      final sortedResponsesCompleted = Completer<void>();
      final server = (await tester.runAsync(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          var completesSortedResponse = false;
          request.response.headers.contentType = ContentType.json;
          final uri = request.uri;
          if (uri.path == '/emby/Library/MediaFolders') {
            request.response.write(
              '{"Items":[{"Id":"library-id","Name":"Test Library",'
              '"CollectionType":"tvshows"}]}',
            );
          } else if (uri.path == '/emby/Users/test-user/Items' &&
              uri.queryParameters['Limit'] == '0') {
            request.response.write(
              '{"Items":[],"TotalRecordCount":$totalItems}',
            );
          } else if (uri.path == '/emby/Users/test-user/Items') {
            request.response.write('{"Items":[],"TotalRecordCount":0}');
          } else if (uri.path == '/emby/Users/test-user/Items/library-id') {
            request.response.write('{"CollectionType":"tvshows"}');
          } else if (uri.path == '/emby/Items') {
            final isTargetSort = uri.queryParameters['SortBy'] == sortBy;
            if (isTargetSort) sortedItemRequests.add(uri);
            final startIndex =
                int.tryParse(uri.queryParameters['StartIndex'] ?? '') ?? 0;
            final requestedLimit =
                int.tryParse(uri.queryParameters['Limit'] ?? '') ?? totalItems;
            final remaining = totalItems - startIndex;
            final count = isTargetSort && remaining > 0
                ? (remaining < requestedLimit ? remaining : requestedLimit)
                : 0;
            completesSortedResponse =
                isTargetSort && startIndex + count >= totalItems;
            request.response.write(
              jsonEncode({
                'Items': [
                  for (var index = 0; index < count; index++)
                    {
                      'Id': 'item-${startIndex + index}',
                      'Name': 'Item ${startIndex + index}',
                      'Type': 'Series',
                      'DateCreated': '2026-01-01T00:00:00Z',
                    },
                ],
                'TotalRecordCount': isTargetSort ? totalItems : 0,
              }),
            );
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write('{}');
          }
          await request.response.close();
          if (completesSortedResponse &&
              !sortedResponsesCompleted.isCompleted) {
            sortedResponsesCompleted.complete();
          }
        });
        return server;
      }))!;

      final service = EmbyService.instance;
      final previousServerUrl = service.serverUrl;
      final previousUserId = service.userId;
      final previousAccessToken = service.accessToken;
      final previousConnected = service.isConnected;
      final previousProfile = service.currentProfile;
      final previousSelectedLibraryIds = List<String>.of(
        service.selectedLibraryIds,
      );
      final provider = EmbyProvider();
      final appearanceProvider = AppearanceSettingsProvider();
      addTearDown(() async {
        provider.dispose();
        appearanceProvider.dispose();
        await tester.runAsync(() => server.close(force: true));
        service.clearServiceData();
        service.currentProfile = previousProfile;
        service.serverUrl = previousServerUrl;
        service.userId = previousUserId;
        service.accessToken = previousAccessToken;
        service.isConnected = previousConnected;
        service.selectedLibraryIds = previousSelectedLibraryIds;
        SharedPreferences.setMockInitialValues({});
      });

      service.currentProfile = null;
      service.clearServiceData();
      service.serverUrl = 'http://${server.address.address}:${server.port}';
      service.userId = 'test-user';
      service.accessToken = 'test-token';
      service.isConnected = true;
      service.selectedLibraryIds = <String>['library-id'];
      await tester.runAsync(service.loadAvailableLibraries);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<EmbyProvider>.value(value: provider),
            ChangeNotifierProvider<AppearanceSettingsProvider>.value(
              value: appearanceProvider,
            ),
          ],
          child: const MaterialApp(
            home: AppDisplaySurfaceScope(
              surface: AppDisplaySurface.desktopTablet,
              child: SizedBox(
                width: 1000,
                height: 700,
                child: NetworkMediaLibraryView(
                  serverType: NetworkMediaServerType.emby,
                ),
              ),
            ),
          ),
        ),
      );
      try {
        await tester.pump();

        await tester.tap(find.text('Test Library'));
        await tester.pump();
        expect(find.byType(AdaptiveMediaActivityIndicator), findsOneWidget);
        await _pumpUntil(
          tester,
          () => find.byType(AdaptiveMediaActivityIndicator).evaluate().isEmpty,
          description: 'initial library load to finish',
          timeout: const Duration(seconds: 2),
        );
        await tester.tap(find.byIcon(Icons.sort_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        await _pumpUntil(
          tester,
          () => find.text('最后一集添加时间 (降序)').evaluate().isNotEmpty,
          description: 'remote sort options to appear',
          timeout: const Duration(seconds: 2),
        );
        final sortOption = find.text('最后一集添加时间 (降序)');
        await tester.ensureVisible(sortOption);
        await tester.pump();
        await tester.tap(sortOption);
        await _pumpUntil(
          tester,
          () =>
              provider.getLibrarySortSettings('library-id')['sortBy'] == sortBy,
          description: 'remote sort selection to apply',
          timeout: const Duration(seconds: 2),
        );
        await _pumpUntil(
          tester,
          () => sortedResponsesCompleted.isCompleted,
          description: 'all sorted responses to complete',
          timeout: const Duration(seconds: 2),
        );

        expect(provider.getLibrarySortSettings('library-id'), <String, String>{
          'sortBy': sortBy,
          'sortOrder': 'Descending',
        });
        expect(sortedItemRequests.length, greaterThan(1));
        expect(
          sortedItemRequests.map(
            (uri) => int.parse(uri.queryParameters['Limit']!),
          ),
          everyElement(lessThanOrEqualTo(200)),
        );
        expect(
          sortedItemRequests
              .map((uri) => uri.queryParameters['SortOrder'])
              .toSet(),
          <String>{'Descending'},
        );
      } finally {
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider<EmbyProvider>.value(value: provider),
              ChangeNotifierProvider<AppearanceSettingsProvider>.value(
                value: appearanceProvider,
              ),
            ],
            child: const MaterialApp(home: SizedBox.shrink()),
          ),
        );
        await tester.pump();
      }
    }, _RealHttpOverrides());
  });
}

class _RealHttpOverrides extends HttpOverrides {}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String description,
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $description');
    }
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}
