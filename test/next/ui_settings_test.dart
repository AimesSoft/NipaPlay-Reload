import 'dart:async';

import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' show Failure, FailureCode;
import 'package:nipaplay/next/ui/data/login_requests.dart';
import 'package:nipaplay/next/ui/data/settings_data.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/settings/controls.dart';
import 'package:nipaplay/next/ui/settings/registry_rows.dart';
import 'package:nipaplay/next/ui/settings/section_host.dart';
import 'package:nipaplay/next/ui/settings/settings_layout.dart';
import 'package:nipaplay/next/ui/widgets/progress.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';

/// The settings page is built from the registry Nipa reads: each schema
/// gets its control, every setting lands in a section (a new one too),
/// a change the registry refuses is put back, and what Nipa changed shows
/// her reason and the way back.
void main() {
  testWidgets('program permission stays visible and revocable without an issuer',
      (tester) async {
    final data = _DeviceHost();
    await tester.pumpWidget(MaterialApp(
      home: Material(child: DevicesSection(host: data)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('此版本尚未配置组网签发者'), findsOneWidget);
    expect(find.text('允许别的设备在这里运行程序'), findsOneWidget);
    final toggles = tester.widgetList<NextToggle>(find.byType(NextToggle));
    expect(toggles.first.onChanged, isNull);
    expect(toggles.last.value, true);
    await tester.tap(find.byType(NextToggle).last);
    await tester.pumpAndSettle();
    expect(data.writes, [false]);
    expect(tester.widget<NextToggle>(find.byType(NextToggle).last).value, false);
  });

  testWidgets('Codex is fetched from the Nipa section; templates only fill in',
      (tester) async {
    final data = FakeSettings();
    data.host.codexState = 'none';
    final model = SettingsModel(data);
    await tester.runAsync(model.load);
    await tester.pumpWidget(MaterialApp(
      home: Material(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 900,
            child: NipaSection(
                data: data,
                model: model,
                onShow: (_) {},
                more: false,
                onMore: () {}),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('115 MB'), findsOneWidget);
    await tester.tap(find.text('下载'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('取消'), findsOneWidget);
    expect(find.byType(ThinBar), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('0.144.1'), findsOneWidget);
    expect(find.text('已就绪'), findsOneWidget);
    expect(find.text('下载'), findsNothing);

    await tester.ensureVisible(find.text('更多'));
    await tester.tap(find.text('更多'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('移除'));
    await tester.tap(find.text('移除'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('下载'), findsOneWidget);

    // A template fills the address and model; they stay editable.
    await tester.ensureVisible(find.text('智谱'));
    await tester.tap(find.text('智谱'));
    await tester.pump();
    expect(
        tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((e) => e.controller.text),
        containsAll(['https://open.bigmodel.cn/api/v1', 'glm-5.3-flash']));
    expect(find.text('保存'), findsOneWidget);
    model.dispose();
  });

  group('a registry row becomes a control by its schema', () {
    UiSetting row(Map<String, Object?> extra) =>
        UiSetting.fromRow({'key': 'x.y', 'title': 'T', ...extra});

    test('kinds', () {
      expect(row({'type': 'boolean'}).kind, UiSettingKind.toggle);
      expect(
          row({
            'type': 'string',
            'enum': ['a', 'b']
          }).kind,
          UiSettingKind.choice);
      expect(
          row({
            'type': 'number',
            'enum': [0.0, 1.0, 2.0]
          }).kind,
          UiSettingKind.choice);
      expect(row({'type': 'integer', 'minimum': 0, 'maximum': 15}).kind,
          UiSettingKind.number);
      expect(row({'type': 'string'}).kind, UiSettingKind.text);
      expect(
          row({'type': 'string', 'x-secret': true}).kind, UiSettingKind.secret);
      expect(row({'type': 'string', 'pattern': r'^#[0-9A-Fa-f]{8}$'}).kind,
          UiSettingKind.color);
      expect(
          UiSetting.fromRow({
            'key': 'player.minimalProgressBarColor',
            'type': 'integer',
            'enum': [0xFFFF7274, 0xFFFFFFFF]
          }).kind,
          UiSettingKind.color);
      // Named colours are a choice, not swatches.
      expect(
          UiSetting.fromRow({
            'key': 'appearance.accentColor',
            'type': 'string',
            'enum': ['rose', 'blue']
          }).kind,
          UiSettingKind.choice);
      expect(
          row({
            'type': 'array',
            'items': {'type': 'string'}
          }).kind,
          UiSettingKind.list);
      expect(row({'type': 'object'}).kind, UiSettingKind.other);
      expect(
          row({
            'type': ['number', 'null']
          }).kind,
          UiSettingKind.number);
    });

    test('paths, folders and the player’s live state', () {
      final folder = UiSetting.fromRow(
          {'key': 'download.directory', 'title': 'T', 'type': 'string'});
      expect(folder.kind, UiSettingKind.path);
      expect(folder.directory, isTrue);
      final file = UiSetting.fromRow(
          {'key': 'danmaku.fontFilePath', 'title': 'T', 'type': 'string'});
      expect(file.kind, UiSettingKind.path);
      expect(file.directory, isFalse);
      // A folder on the WebDAV server is not one on this computer.
      expect(
          UiSetting.fromRow({
            'key': 'webdavQuick.defaultDirectory',
            'title': 'T',
            'type': 'string'
          }).kind,
          UiSettingKind.text);
      expect(
          row({
            'type': 'number',
            'storage': {'kind': 'runtime'}
          }).runtime,
          isTrue);
    });

    test('provenance: Nipa’s change, its reason and the value before', () {
      final s = row({
        'type': 'number',
        'value': 0.6,
        'provenance': {
          'changedBy': 'agent',
          'reason': '太晃眼',
          'previousValue': 0.85,
          'changedAt': '2026-10-13T08:00:00Z',
        }
      });
      expect(s.byNipa, isTrue);
      expect(s.reason, '太晃眼');
      expect(s.previousValue, 0.85);
      expect(
          row({
            'provenance': {'changedBy': 'user'}
          }).byNipa,
          isFalse);
    });
  });

  group('every setting has a place', () {
    UiSetting s(String key, {String type = 'boolean'}) =>
        UiSetting.fromRow({'key': key, 'title': key, 'type': type});

    test('sections by key; a new domain lands in 通用', () {
      expect(
          SettingsLayout.sectionOf('player.kernel'), SettingsSection.playback);
      expect(SettingsLayout.sectionOf('player.screenshotFormat'),
          SettingsSection.storage);
      expect(
          SettingsLayout.sectionOf('subtitle.scale'), SettingsSection.danmaku);
      expect(SettingsLayout.sectionOf('plugins.githubProxyUrl'),
          SettingsSection.network);
      expect(SettingsLayout.sectionOf('appearance.themeMode'),
          SettingsSection.classic);
      expect(SettingsLayout.sectionOf('somethingNew.flag'),
          SettingsSection.general);
    });

    test('groups: named keys first, folded ones behind 更多', () {
      final all = [
        s('player.topSkipButtonVisible'),
        s('player.kernel', type: 'string'),
        s('player.externalEnabled'),
        s('player.somethingNew'),
        s('labs_use_next_interface'),
        UiSetting.fromRow({
          'key': 'player.volume',
          'title': 'v',
          'type': 'number',
          'storage': {'kind': 'runtime'}
        }),
      ];
      final groups = SettingsLayout.arrange(SettingsSection.playback, all);
      final where = {
        for (final (g, rows) in groups)
          for (final r in rows) r.key: (g.title, g.folded)
      };
      expect(where['player.kernel'], ('', false));
      expect(where['player.topSkipButtonVisible'], ('播放界面', true));
      expect(where['player.externalEnabled'], ('外部播放器', true));
      expect(where['player.somethingNew'], ('其他', true));
      expect(where.containsKey('player.volume'), isFalse);
      final general = SettingsLayout.arrange(SettingsSection.general, all);
      expect(general.expand((g) => g.$2).map((s) => s.key),
          isNot(contains('labs_use_next_interface')));
    });

    test('values are called by name; unknown ones show as they are', () {
      expect(
          SettingWords.choice('player.playbackEndAction', 'autoNext'), '下一集');
      expect(SettingWords.choice('danmaku.outlineWidth', 2.0), '粗');
      expect(SettingWords.choice('anything', 'system'), '跟随系统');
      expect(SettingWords.choice('anything', 'zzz'), 'zzz');
    });
  });

  group('the page changes settings as the person', () {
    Widget host(Widget child) => MaterialApp(
          home: Material(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 900, child: child),
            ),
          ),
        );

    testWidgets('a toggle saves; a refused value is put back with a word',
        (tester) async {
      final data = _Recording();
      final model = SettingsModel(data);
      await tester.runAsync(model.load);
      Widget page() => host(ListenableBuilder(
            listenable: model,
            builder: (context, _) => Column(children: [
              for (final key in ['player.introSkipEnabled', 'seek.skipSeconds'])
                RegistryRow(setting: model[key]!, model: model),
            ]),
          ));
      await tester.pumpWidget(page());
      await tester.tap(find.byType(NextToggle));
      await tester.pump();
      // Shown at once, before NipaPlay answers.
      expect(model['player.introSkipEnabled']!.value, false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(data.sets, [('player.introSkipEnabled', false)]);
      expect(model['player.introSkipEnabled']!.changedBy, 'user');

      data.refuse = true;
      await tester.enterText(find.byType(EditableText), '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(model['seek.skipSeconds']!.value, 90);
      // Enter and leaving the field hand it over once.
      expect(data.sets.where((s) => s.$1 == 'seek.skipSeconds'), hasLength(1));
      expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .controller
              .text,
          '90');
      expect(find.text('这个值不行'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('这个值不行'), findsNothing);
      model.dispose();
    });

    testWidgets('Nipa’s mark opens her reason; 改回 restores the value before',
        (tester) async {
      final data = _Recording();
      final model = SettingsModel(data);
      await tester.runAsync(model.load);
      await tester.pumpWidget(host(ListenableBuilder(
        listenable: model,
        builder: (context, _) =>
            RegistryRow(setting: model['danmaku.opacity']!, model: model),
      )));
      expect(find.byType(NipaMark), findsOneWidget);
      expect(find.text('你说晚上弹幕太晃眼，调淡了一些。'), findsNothing);
      await tester.tap(find.byType(NipaMark));
      await tester.pumpAndSettle();
      expect(find.text('你说晚上弹幕太晃眼，调淡了一些。'), findsOneWidget);
      await tester.tap(find.text('改回'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(data.sets.last, ('danmaku.opacity', 0.85));
      await tester.pumpAndSettle();
      // Changed by the person now: her mark goes.
      expect(find.byType(NipaMark), findsNothing);
      model.dispose();
    });
  });

  test('a login asked for on the settings page opens its window directly',
      () async {
    final logins = LoginRequests()..showing = () => true;
    logins.expect('Bangumi');
    var shown = 0;
    final result = await logins.request<String>('Bangumi', () async {
      shown++;
      return 'from-window';
    }, Completer<void>().future);
    expect(result, 'from-window');
    expect(shown, 1);
    expect(logins.pending, isEmpty);
    // Only once: the agent's next login waits as a card again.
    unawaited(logins.request<String>(
        'Bangumi', () async => 'x', Completer<void>().future));
    expect(logins.pending, hasLength(1));
  });
}

final class _DeviceHost implements NextHostSettings {
  bool enabled = true;
  final writes = <bool>[];
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<UiMeshSetup> mesh() async => const UiMeshSetup(
      available: false, problem: '此版本尚未配置组网签发者');
  @override
  Future<bool> remotePrograms() async => enabled;
  @override
  Future<void> setRemotePrograms(bool allowed) async {
    writes.add(allowed);
    enabled = allowed;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The scripted settings (the built-in sample of the registry), recording
/// what the page asked to save and refusing on demand.
final class _Recording implements NextSettingsData {
  final _fake = FakeSettings();
  final sets = <(String, Object?)>[];
  bool refuse = false;

  @override
  Future<UiSetting> set(String key, Object? value) async {
    sets.add((key, value));
    if (refuse) {
      throw const Failure(FailureCode.invalidInput, 'Invalid setting value.');
    }
    return _fake.set(key, value);
  }

  @override
  Future<List<UiSetting>> settings() => _fake.settings();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
