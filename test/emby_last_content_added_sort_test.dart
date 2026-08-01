import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_library_sort_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const sortBy = 'DateLastContentAdded';

  test('Emby exposes last episode added with both sort orders', () {
    final option = getMediaSortOptions(MediaLibraryType.emby).singleWhere(
      (option) => option.value == sortBy,
    );

    expect(option.label, '最后一集添加时间');
    expect(option.description, '按最后一集添加时间排序');
    expect(
      getMediaSortOptions(MediaLibraryType.jellyfin)
          .where((option) => option.value == sortBy),
      isEmpty,
    );
    expect(
      mediaLibrarySortOrders,
      <Map<String, String>>[
        <String, String>{'value': 'Ascending', 'label': '升序'},
        <String, String>{'value': 'Descending', 'label': '降序'},
      ],
    );
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
    service.serverUrl =
        'http://${server.address.address}:${server.port}';
    service.userId = 'test-user';
    service.accessToken = 'test-token';
    service.isConnected = true;
    provider.setLibrarySortSettings(
      'library-id',
      sortBy,
      'Descending',
    );

    await provider.fetchMediaItemsForLibrary('library-id', limit: 37);

    final itemsRequest = requests.singleWhere(
      (uri) => uri.path == '/emby/Items',
    );
    expect(itemsRequest.queryParameters['ParentId'], 'library-id');
    expect(itemsRequest.queryParameters['SortBy'], sortBy);
    expect(itemsRequest.queryParameters['SortOrder'], 'Descending');
    expect(itemsRequest.queryParameters['Limit'], '37');
  });

  test('large Emby sorts do not split into serial requests', () async {
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

    final items = await service.getLatestMediaItemsByLibrary(
      'library-id',
      limit: 99999,
      sortBy: sortBy,
      sortOrder: 'Descending',
    );

    expect(items, hasLength(totalItems));
    expect(itemRequests, hasLength(1));
    expect(itemRequests.single.queryParameters['StartIndex'], isNull);
    expect(itemRequests.single.queryParameters['Limit'], '99999');
    expect(itemRequests.single.queryParameters['SortBy'], sortBy);
    expect(itemRequests.single.queryParameters['SortOrder'], 'Descending');
  });
}
