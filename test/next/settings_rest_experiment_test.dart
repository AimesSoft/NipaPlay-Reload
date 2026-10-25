// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/classic_settings.dart';
import 'package:nipaplay/next/settings/capability.dart';
import 'package:nipaplay/next/settings/operations.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/pages/language_settings_content.dart';
import 'package:nipaplay/settings/pages/webdav_quick_settings_content.dart';
import 'package:nipaplay/utils/hotkey_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../security/memory_vault.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:path/path.dart' as ppath;

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'X18 isolated settings, Classic widgets, plugins and backup roundtrip',
      (tester) async {
    await tester.runAsync(() async {
      sqfliteFfiInit();
      final temporary = await Directory.systemTemp.createTemp('nipa-x18-');
      final root = Directory(await temporary.resolveSymbolicLinks());
      StorageService.debugAppStorageDirectoryOverride = root;
      final previous = CredentialStore.instance;
      CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
      SharedPreferences.setMockInitialValues(
          {'plugin_enabled_ids': <String>[]});
      PackageInfo.setMockInitialValues(
          appName: 'NipaPlay X18',
          packageName: 'nipa.x18',
          version: '99.0.0',
          buildNumber: '18',
          buildSignature: '');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => root.path);
      final preferences = SettingsProvider();
      await preferences.ready;
      final classic = ClassicSettings(
          appearance: AppearanceSettingsProvider(automaticUiScale: 1.3),
          language: AppLanguageProvider(),
          home: HomeSectionsSettingsProvider(),
          theme: ThemeNotifier(),
          developer: DeveloperOptionsProvider(),
          labs: LabsSettingsProvider(sandboxStatus: () async => false),
          webdav: WebDAVQuickAccessProvider(),
          plugins: PluginService());
      ClassicSettings.attached = classic;
      await classic.ready;
      await classic.plugins.ready;
      final db = await openNextDatabase(root, factory: databaseFactoryFfi);
      final registry = SettingsRegistry(db, ClassicSettings.entries());
      SettingsAccess.registry = registry;
      ApplicationSettings.authorizePath = (path, {directory = false}) async {
        final resolved = await (directory
            ? Directory(path).resolveSymbolicLinks()
            : File(path).resolveSymbolicLinks());
        if (!ppath.isWithin(root.path, resolved) && resolved != root.path) {
          throw const h.Failure(
              h.FailureCode.unavailable, 'Outside experiment root.');
        }
        return resolved;
      };
      void syncPlugins() {
        registry.replaceGroup('plugins.enabled.', []);
        registry.replaceGroup('plugins.settings.', classic.pluginEntries());
      }

      syncPlugins();
      classic.plugins.addListener(syncPlugins);
      final logs = DebugLogService.forTesting();
      final operations =
          ClassicOperations(registry, logs: logs, reloadHistory: () async {});
      final api = h.Harness([SettingsCapability(registry), operations]);
      Future<h.JsonMap> call(String id, h.JsonMap input) async {
        final result =
            await api.invokeJson(id, input, h.Invocation(origin: 'mcp'));
        expect(result, isA<h.Completed>(),
            reason: '$id ${input['key']}: ${jsonEncode(result.toEnvelope())}');
        final json = (result as h.Completed).value.toJson();
        expect(api.lookup(id)!.spec.output.validate(json), isEmpty);
        return json;
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        classic.plugins.removeListener(syncPlugins);
        await FileLogService().stop();
        logs.dispose();
        classic.plugins.dispose();
        classic.appearance.dispose();
        classic.language.dispose();
        classic.home.dispose();
        classic.theme.dispose();
        classic.developer.dispose();
        classic.labs.dispose();
        classic.webdav.dispose();
        preferences.dispose();
        await registry.drain();
        SettingsAccess.registry = null;
        ClassicSettings.attached = null;
        ApplicationSettings.authorizePath = null;
        await WatchHistoryDatabase.instance.close();
        await db.close();
        StorageService.debugAppStorageDirectoryOverride = null;
        CredentialStore.instance = previous;
        AppHttpProxy.clear();
        await root.delete(recursive: true);
      });
      final png = File(ppath.join(root.path, 'background.png'));
      await png.writeAsBytes([137, 80, 78, 71]);
      final overrides = <String, Object?>{
        'appearance.quarterlyReviewSort': 'ratingHigh',
        'appearance.accentColor': 'blue',
        'appearance.folderNameDisplayMode': 'multiline',
        'appearance.windowDisplayMode': 'filledScreen',
        'appearance.uiScale': 1.1,
        'appearance.automaticUiScale': false,
        'appearance.themeMode': 'dark',
        'appearance.backgroundImageMode': '自定义',
        'appearance.customBackgroundPath': png.path,
        'appearance.backgroundRenderMode': 'soft_light',
        'appearance.backgroundOverlayOpacity': 0.6,
        'appearance.blurPower': 15.0,
        'appearance.homeSectionsOrder':
            HomeSectionType.values.reversed.map((e) => e.storageKey).toList(),
        'appearance.homeSectionsDisabled': ['trending'],
        'language.mode': 'english',
        'general.desktopExitBehavior': 'closePlayer',
        'general.startupWindowState': 'windowed',
        'general.startupWindowPosition': 'bottomRight',
        'general.startupWindowWidth': 1440.0,
        'general.startupWindowHeight': 900.0,
        'general.pictureInPicturePosition': 'bottomLeft',
        'general.defaultHomeTab': 'video',
        'network.httpProxy': 'http://127.0.0.1:7890',
        'plugins.githubProxyUrl': '',
        'webdavQuick.defaultServerName': 'experiment-server',
        'webdavQuick.defaultDirectory': '/anime',
        'webdavQuick.sortPreset': 'name_desc',
        'webdavQuick.seasonFolderPattern': 'S*',
        'webdavQuick.bgmIdMatchPattern': r'bangumi=(\d+)',
        'webdavQuick.tmdbIdMatchPattern': r'movie=(\d+)',
        'webdavQuick.searchScope': 'global',
        'webdavQuick.searchDepthLimit': 5,
        'webdavQuick.searchTargets': ['video'],
        'webdavQuick.searchTimeout': 60,
        'webdavQuick.searchRequestInterval': 250,
        'webdavQuick.searchMaxResults': 1000,
      };
      final entries = registry.entries
          .where((e) =>
              !e.key.startsWith('plugins.enabled.') &&
              !e.key.startsWith('plugins.settings.'))
          .toList();
      // Exercise the automatic mode before the manual scale disables it.
      entries.sort((a, b) => a.key == 'appearance.automaticUiScale'
          ? -1
          : b.key == 'appearance.automaticUiScale'
              ? 1
              : a.key.compareTo(b.key));
      final counts = <String, int>{};
      var shortcutIndex = 0;
      for (final entry in entries) {
        if (!entry.visible()) continue;
        final before = await call('settings.get', {'key': entry.key});
        final value = overrides[entry.key] ??
            (entry.schema is h.BooleanSchema
                ? !(before['value'] as bool)
                : entry.domain == 'shortcuts'
                    ? 'Ctrl+F${++shortcutIndex}'
                    : throw StateError(
                        'Missing experiment value: ${entry.key}'));
        final result = await call('settings.set', {
          'key': entry.key,
          'value': value,
          'reason': 'X18 ${entry.domain} experiment'
        });
        final after = await call('settings.get', {'key': entry.key});
        expect(after['value'], value, reason: entry.key);
        final source = after['provenance'] as Map;
        expect(source['changedBy'], 'agent');
        expect(source['origin'], 'mcp');
        expect(source['reason'], 'X18 ${entry.domain} experiment');
        expect(DateTime.parse(source['changedAt'] as String).isUtc, true);
        expect(source['invocationId'], isNotEmpty);
        expect(after['revision'], result['revision']);
        counts.update(entry.domain, (n) => n + 1, ifAbsent: () => 1);
      }
      print(
          'X18 read/change/read/provenance: ${jsonEncode(counts)} total=${counts.values.fold(0, (a, b) => a + b)}');
      expect(classic.appearance.accentColorPreset.storageKey, 'blue');
      expect(classic.appearance.uiScale, 1.1);
      expect(classic.theme.themeMode, ThemeMode.dark);
      expect(classic.language.mode, AppLanguageMode.english);
      expect(classic.webdav.searchMaxResults, 1000);
      expect(HotkeyService().allShortcuts['play_pause'], startsWith('Ctrl+F'));
      expect(
          AppHttpProxy.findProxy(
              Uri.parse('https://example.invalid'), (_) => 'SYSTEM'),
          'PROXY 127.0.0.1:7890');
      await call('settings.set', {
        'key': 'network.httpProxy',
        'value': '',
        'reason': 'test system proxy'
      });
      expect(
          AppHttpProxy.findProxy(
              Uri.parse('https://example.invalid'), (_) => 'SYSTEM'),
          'SYSTEM');
      print('X18 proxy: explicit=PROXY 127.0.0.1:7890; empty=SYSTEM');
      // Mount real Classic pages against the providers changed by Agent.
      Widget gui(Widget page) => MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: classic.language),
                ChangeNotifierProvider.value(value: classic.webdav),
                ChangeNotifierProvider.value(value: classic.appearance),
                ChangeNotifierProvider.value(value: classic.theme),
              ],
              child: MaterialApp(
                  locale: classic.language.locale,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: Scaffold(
                      body: AdaptiveSettingsScope(
                          style: AdaptiveSettingsStyle.desktopTablet,
                          child: page))));
      await tester.pumpWidget(gui(const LanguageSettingsContent()));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsWidgets);
      await call('settings.set', {
        'key': 'webdavQuick.enableSearch',
        'value': true,
        'reason': 'X18 reveal Classic search controls',
      });
      await tester.pumpWidget(gui(const WebDAVQuickSettingsContent()));
      await tester.pumpAndSettle();
      AdaptiveSettingsTile tile(String title) =>
          tester.widget<AdaptiveSettingsTile>(find.byWidgetPredicate(
              (w) => w is AdaptiveSettingsTile && w.title == title));
      expect(tile('显示 WebDAV Tab').switchValue, true);
      await tester.scrollUntilVisible(find.text('最大结果数'), 300, maxScrolls: 30);
      expect(tile('最大结果数').sliderValue, 1000.0);
      print(
          'X18 Classic widgets: language=English; WebDAV maxResults=1000; showTab=true');
      await tester.pumpWidget(const SizedBox());
      await classic.appearance.setShowHomeHeroBanner(true);
      await registry.drain();
      final guiChange = (await registry
          .get('appearance.showHomeHeroBanner'))['provenance'] as Map;
      expect(guiChange['changedBy'], 'user');
      expect(guiChange['origin'], 'gui');
      print('X18 GUI provenance: ${jsonEncode(guiChange)}');
      print(
          'X18 Agent provenance: ${jsonEncode((await registry.get('language.mode'))['provenance'])}');
      await classic.appearance.setAutomaticUiScale(true);
      await classic.appearance.setUiScale(1.2);
      await registry.drain();
      final scaleChange =
          (await registry.get('appearance.uiScale'))['provenance'] as Map;
      expect(scaleChange['changedBy'], 'user');
      expect(scaleChange['previousValue'], 1.3);
      expect(scaleChange['value'], 1.2);
      for (final invalid in [
        {'key': 'webdavQuick.searchTargets', 'value': []},
        {'key': 'webdavQuick.searchTimeout', 'value': 12},
        {'key': 'webdavQuick.bgmIdMatchPattern', 'value': '['},
        {
          'key': 'appearance.homeSectionsOrder',
          'value': ['trending', 'trending']
        },
        {
          'key': 'network.httpProxy',
          'value': 'http://user:password@localhost:7890'
        },
      ]) {
        final rejected = await api.invokeJson(
            'settings.set', invalid, h.Invocation(origin: 'mcp'));
        expect(rejected, isA<h.Failed>());
      }
      // Use a real harmless JS plugin, Classic storage and runtime.
      final script = File(ppath.join(root.path, 'fixture.js'));
      await script.writeAsString("""
var pluginManifest = {id:'x18.fixture',name:'X18 fixture',version:'1.0.0',minHostVersion:'1.0.0',description:'isolated experiment',author:'NipaPlay'};
var pluginUIEntries = [
  {id:'feature',title:'Feature',enabled:false},
  {id:'label',title:'Label',textSetting:{default:'initial'}},
  {id:'password',title:'Password',textSetting:{default:''}},
  {id:'cookie',title:'Cookie',textSetting:{default:''}},
  {id:'inspect',title:'Inspect'}
];
function pluginOnEvent(event) {}
function pluginHandleUIAction(actionId) { return {type:'text',title:'Fixture',content:'roundtrip'}; }
""");
      final installed = await call('plugins.install',
          {'path': script.path, 'reason': 'X18 isolated install'});
      expect(installed['id'], 'x18.fixture');
      final enabled = await call('plugins.set_enabled',
          {'id': 'x18.fixture', 'enabled': true, 'reason': 'X18 enable'});
      expect(enabled['enabled'], true);
      expect(enabled['loaded'], true, reason: jsonEncode(enabled));
      const pluginSetting = 'plugins.settings.x18.fixture';
      for (final (key, value) in [
        ('$pluginSetting.feature', true),
        ('$pluginSetting.label', 'Agent label')
      ]) {
        final row = await call('settings.set',
            {'key': key, 'value': value, 'reason': 'X18 plugin setting'});
        expect(row['value'], value);
        expect((row['provenance'] as Map)['changedBy'], 'agent');
      }
      expect(registry.entries.any((e) => e.key == '$pluginSetting.password'),
          false);
      expect(
          registry.entries.any((e) => e.key == '$pluginSetting.cookie'), false);
      print(
          'X18 plugin install/enable/settings: ${jsonEncode(enabled)} secretField=excluded');
      final invoked = await call(
          'plugins.invoke', {'id': 'x18.fixture', 'actionId': 'inspect'});
      expect((invoked['result'] as Map)['content'], 'roundtrip');
      await script.writeAsString((await script.readAsString())
          .replaceFirst("version:'1.0.0'", "version:'2.0.0'"));
      final updated = await call('plugins.install',
          {'path': script.path, 'updateForId': 'x18.fixture'});
      expect(updated['version'], '2.0.0');
      expect(classic.plugins.getTextSettingValue('x18.fixture', 'label'),
          'Agent label');
      print(
          'X18 plugin update/invoke: version=2.0.0; text setting preserved; action=roundtrip');
      final disabled = await call('plugins.set_enabled',
          {'id': 'x18.fixture', 'enabled': false, 'reason': 'X18 disable'});
      expect(disabled['loaded'], false);
      await call('plugins.delete',
          {'id': 'x18.fixture', 'reason': 'X18 remove fixture'});
      expect(
          registry.entries.any((e) => e.key.startsWith(pluginSetting)), false);
      print(
          'X18 plugin disable/delete: loaded=false; dynamic settings removed');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final marketPaths = <String>[];
      final listening = server.listen((request) async {
        marketPaths.add(request.uri.path);
        if (request.uri.path.endsWith('plugins.json')) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode([
            {
              'id': 'x18.market',
              'name': 'X18 market',
              'version': '1.0.0',
              'file': 'plugins/x18-market.js',
              'author': 'NipaPlay',
              'description': 'fixture',
            }
          ]));
        } else {
          request.response.write((await script.readAsString())
              .replaceAll('x18.fixture', 'x18.market'));
        }
        await request.response.close();
      });
      addTearDown(() async {
        await listening.cancel();
        await server.close(force: true);
      });
      await HttpOverrides.runZoned(() async {
        await call('settings.set', {
          'key': 'plugins.githubProxyUrl',
          'value': 'http://127.0.0.1:${server.port}/',
          'reason': 'X18 loopback fixture'
        });
        final market = await call('plugins.market', {'refresh': true});
        expect((market['plugins'] as List).single['downloadUrl'],
            endsWith('/plugins/x18-market.js'));
        final remote =
            await call('plugins.install', {'remoteId': 'x18.market'});
        expect(remote['id'], 'x18.market');
      }, createHttpClient: _DirectHttp().createHttpClient);
      expect(
          marketPaths.last,
          contains(
              'https://github.com/AimesSoft/Nipaplay-plugins/blob/main/plugins/x18-market.js'));
      await call('plugins.delete', {'id': 'x18.market'});
      print(
          'X18 market/install: file field resolved; Classic proxy requests=${jsonEncode(marketPaths)}');
      logs.addLog('X18 diagnosis', tag: 'X18');
      final logPath = ppath.join(root.path, 'diagnostics.txt');
      await call('diagnostics.export', {'path': logPath});
      expect(await File(logPath).readAsString(), contains('X18 diagnosis'));
      final batch = await call('diagnostics.export', {
        'operations': [
          {'path': logPath},
          {'path': ppath.join(root.path, 'diagnostics-2.txt')}
        ]
      });
      expect((batch['results'] as List).map((e) => e['status']),
          ['failed', 'completed']);
      final linkedDestination = Link(ppath.join(root.path, 'broken-link.txt'));
      await linkedDestination.create(ppath.join(root.path, 'missing-target.txt'));
      final linkAttempt = await api.invokeJson('diagnostics.export',
          {'path': linkedDestination.path}, h.Invocation(origin: 'mcp'));
      expect(linkAttempt, isA<h.Failed>());
      expect(await File(ppath.join(root.path, 'missing-target.txt')).exists(), false);
      print(
          'X18 diagnostics export: text preserved; batch=[failed(conflict),completed]');
      // Roundtrip the Classic .npb format with preferences, history and matches.
      final video = File(ppath.join(root.path, 'episode.mkv'));
      await video.writeAsString('fixture');
      final history = WatchHistoryDatabase.instance;
      final historyDb = await history.database;
      await historyDb.insert('watch_history', {
        'file_path': video.path,
        'anime_name': 'X18 anime',
        'episode_title': 'Episode 1',
        'anime_id': 18,
        'episode_id': 1801,
        'watch_progress': 0.5,
        'last_position': 123000,
        'duration': 246000,
        'last_watch_time': '2026-10-11T00:00:00.000Z',
        'is_from_scan': 0,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('x18_preserve_string', 'exact payload');
      await prefs.setStringList('x18_preserve_list', ['α', 'β']);
      await prefs.setStringList('nipaplay_scanned_folders', [root.path]);
      await prefs.setInt('web_server_port', 1180);
      await prefs.setString(
          'server_profiles',
          jsonEncode([
            {
              'id': 'x18-server',
              'serverName': 'X18 public server',
              'serverType': 'emby',
              'username': 'fixture-user',
              'addresses': [],
            }
          ]));
      final selected = BackupCategory.values.map((e) => e.name).toList();
      final path = ppath.join(root.path, 'roundtrip.npb');
      await call('backup.export', {'path': path, 'categories': selected});
      final preview = await call('backup.preview', {'path': path});
      final beforeData = await FullBackupService()
          .collectBackupData(categories: BackupCategory.values.toSet());
      await call('settings.set', {
        'key': 'language.mode',
        'value': 'traditional',
        'reason': 'mutate before restore'
      });
      await prefs.setString('x18_preserve_string', 'changed');
      await prefs.setStringList('x18_preserve_list', ['changed']);
      await prefs.setStringList('nipaplay_scanned_folders', []);
      await historyDb.delete('watch_history');
      final restored = await call('backup.restore', {
        'path': path,
        'categories': selected,
        'reason': 'X18 restore roundtrip'
      });
      expect(restored['success'], true);
      expect(prefs.getString('x18_preserve_string'), 'exact payload');
      expect(prefs.getStringList('x18_preserve_list'), ['α', 'β']);
      final restoredItems = await history.getAllWatchHistory();
      expect(restoredItems.single.lastPosition, 123000);
      expect(restoredItems.single.episodeId, 1801);
      final afterData = await FullBackupService()
          .collectBackupData(categories: BackupCategory.values.toSet());
      expect(afterData['preferences'], beforeData['preferences']);
      expect(afterData['watchHistory'], beforeData['watchHistory']);
      expect(afterData['episodeMatches'], beforeData['episodeMatches']);
      expect(afterData['mediaLibraries'], beforeData['mediaLibraries']);
      expect(afterData['accounts'], beforeData['accounts']);
      final source = (await registry.get('language.mode'))['provenance'] as Map;
      expect(source['reason'], 'X18 restore roundtrip');
      expect(source['changedBy'], 'agent');
      print('X18 backup preview: ${jsonEncode(preview)}');
      print(
          'X18 backup roundtrip: ${jsonEncode(restored)} all five categories=exact; position=123000; provenance=agent/X18 restore roundtrip');
      final oldFormat = ppath.join(root.path, 'history.nph');
      await call('backup.history_export', {'path': oldFormat});
      await historyDb
          .update('watch_history', {'last_position': 0, 'watch_progress': 0.0});
      final restoredHistory =
          await call('backup.history_restore', {'path': oldFormat});
      expect(restoredHistory['restoredCount'], 1);
      expect((await history.getAllWatchHistory()).single.lastPosition, 123000);
      print('X18 .nph roundtrip: restoredCount=1; position=123000');
      await call('webdav_quick.reset', {'reason': 'X18 reset'});
      expect(classic.webdav.searchMaxResults, 500);
      expect(
          (await registry.get('webdavQuick.searchMaxResults'))['value'], 500);
      // Verify the repaired Classic backup treatment of plugin enable lists.
      final builtin = classic.plugins.plugins.firstWhere(
          (p) => p.manifest.id == 'builtin.danmaku_regex_filter');
      final enableKey = 'plugins.enabled.${builtin.manifest.id}';
      await call('settings.set', {
        'key': enableKey,
        'value': true,
        'reason': 'X18 Classic backup classification probe'
      });
      final probe = ppath.join(root.path, 'plugin-state.npb');
      await call('backup.export', {
        'path': probe,
        'categories': ['preferences']
      });
      await call('settings.set', {
        'key': enableKey,
        'value': false,
        'reason': 'X18 Classic backup classification probe'
      });
      await call('backup.restore', {
        'path': probe,
        'categories': ['preferences']
      });
      final restoredEnabled = prefs.getStringList('plugin_enabled_ids');
      expect(restoredEnabled, [builtin.manifest.id]);
      final probeData = jsonDecode(await File(probe).readAsString()) as Map;
      final exportedEnabled =
          probeData['preferences']['settings']['plugin_enabled_ids'];
      expect(exportedEnabled, [builtin.manifest.id]);
      print(
          'X18 repaired Classic backup: plugin_enabled_ids exported=${jsonEncode(exportedEnabled)}; after=${jsonEncode(restoredEnabled)}');
      await call('shortcuts.reset', {'reason': 'X18 reset'});
      expect(HotkeyService().allShortcuts, HotkeyService.defaultShortcuts);
      print('X18 reset: WebDAV maxResults=500; shortcuts=19 defaults');
    });
  });
}
