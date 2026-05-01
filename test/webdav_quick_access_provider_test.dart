import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('WebDAVQuickAccessProvider', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('loads WebDAV as effective default tab when enabled', () async {
      SharedPreferences.setMockInitialValues({
        'show_webdav_tab': true,
        'default_home_tab': WebDAVQuickAccessProvider.tabWebDAV,
      });

      final provider = WebDAVQuickAccessProvider();
      await provider.loadSettings();

      expect(provider.defaultHomeTab, WebDAVQuickAccessProvider.tabWebDAV);
      expect(provider.effectiveDefaultHomeTab,
          WebDAVQuickAccessProvider.tabWebDAV);
    });

    test('falls back to home when WebDAV default tab is disabled', () async {
      SharedPreferences.setMockInitialValues({
        'show_webdav_tab': false,
        'default_home_tab': WebDAVQuickAccessProvider.tabWebDAV,
      });

      final provider = WebDAVQuickAccessProvider();
      await provider.loadSettings();

      expect(provider.defaultHomeTab, WebDAVQuickAccessProvider.tabWebDAV);
      expect(
          provider.effectiveDefaultHomeTab, WebDAVQuickAccessProvider.tabHome);
    });
  });
}
