import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/anime_info/anime_info_service.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/utils/dandanplay_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unified media services never reuse a cached legacy AppSecret',
    () async {
      SharedPreferences.setMockInitialValues({
        'dandanplay_app_secret': 'legacy-test-secret',
      });
      expect(await DandanplayAuth.getAppSecret(), 'server-managed');
      expect(
        await DandanplayAuth.getAppSecret(),
        await DandanplayService.getAppSecret(),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dandanplay_app_secret'), 'legacy-test-secret');
    },
  );

  test(
    'unified media matching requires the current Dandanplay login',
    () async {
      SharedPreferences.setMockInitialValues({
        'dandanplay_app_secret': 'legacy-test-secret',
      });
      await expectLater(
        AnimeInfoService.requestDandanplayFileMatch(
          DandanplayFileMatchArgument(
            fileName: 'episode.mkv',
            fileHash: '00000000000000000000000000000000',
            fileSize: 1024,
          ),
        ),
        throwsA(isA<DandanplayLoginRequired>()),
      );
    },
  );
}
