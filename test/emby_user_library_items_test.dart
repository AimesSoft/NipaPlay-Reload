import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final random in [false, true]) {
    for (final cachedLibrary in [false, true]) {
      test(
          '${random ? 'random' : 'sorted'} library browsing uses user items '
          'with ${cachedLibrary ? 'Views metadata' : 'item metadata'}',
          () async {
        SharedPreferences.setMockInitialValues({});
        final requests = <Uri>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          requests.add(request.uri);
          request.response.headers.contentType = ContentType.json;
          if (request.uri.path == '/emby/Users/test-user/Items/library' &&
              !cachedLibrary) {
            request.response.write('{"CollectionType":"tvshows"}');
          } else if (request.uri.path == '/emby/Users/test-user/Items') {
            request.response.write(jsonEncode({
              'Items': [
                {'Id': 'series', 'Name': '番剧', 'Type': 'Series'}
              ],
              'TotalRecordCount': 1,
            }));
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.headers.contentType = ContentType.html;
            request.response.write('<html>404 Not Found</html>');
          }
          await request.response.close();
        });

        final service = EmbyService.instance;
        final oldUrl = service.serverUrl;
        final oldUser = service.userId;
        final oldToken = service.accessToken;
        final oldConnected = service.isConnected;
        final oldProfile = service.currentProfile;
        final oldLibraries = List<EmbyLibrary>.of(service.availableLibraries);
        addTearDown(() async {
          await server.close(force: true);
          service.currentProfile = oldProfile;
          service.serverUrl = oldUrl;
          service.userId = oldUser;
          service.accessToken = oldToken;
          service.isConnected = oldConnected;
          service.availableLibraries
            ..clear()
            ..addAll(oldLibraries);
        });
        service.currentProfile = null;
        service.serverUrl = 'http://${server.address.address}:${server.port}';
        service.userId = 'test-user';
        service.accessToken = 'test-token';
        service.isConnected = true;
        service.availableLibraries.clear();
        if (cachedLibrary) {
          service.availableLibraries.add(
            EmbyLibrary(id: 'library', name: '动漫剧集', type: 'tvshows'),
          );
        }

        final items = random
            ? await service.getRandomMediaItemsByLibrary('library', limit: 7)
            : await service.getLatestMediaItemsByLibrary('library',
                limit: 7, sortBy: 'SortName', sortOrder: 'Ascending');
        expect(items.map((item) => item.id), ['series']);
        final query = requests.last.queryParameters;
        expect(requests.last.path, '/emby/Users/test-user/Items');
        expect(query['ParentId'], 'library');
        expect(query['IncludeItemTypes'], 'Series');
        expect(query['Limit'], '7');
        expect(query['SortBy'], random ? 'Random' : 'SortName');
        if (!random) expect(query['SortOrder'], 'Ascending');
        if (cachedLibrary) expect(requests.length, 1);
      });
    }
  }
}
