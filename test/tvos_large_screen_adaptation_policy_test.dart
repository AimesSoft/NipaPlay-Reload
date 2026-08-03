import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tvOS removes controls that cannot be used on Apple TV', () {
    final scaffold = File(
      'lib/themes/nipaplay/widgets/large_screen_scaffold_layout.dart',
    ).readAsStringSync();
    final labs = File(
      'lib/settings/pages/labs_settings_content.dart',
    ).readAsStringSync();
    final plugins = File(
      'lib/settings/pages/plugin_settings_content.dart',
    ).readAsStringSync();
    final remote = File(
      'lib/settings/pages/remote_media_library_settings_content.dart',
    ).readAsStringSync();

    expect(
      scaffold,
      contains('globals.isTvOS ? null : widget.onToggleLargeScreen'),
    );
    expect(
      scaffold,
      isNot(contains('globals.isTvOS ? null : widget.onOpenSettings')),
    );
    expect(scaffold, contains('widget.onOpenSettings,'));
    expect(scaffold, contains('onOpenSettings: _toggleSettingsPanel'));
    expect(
      scaffold,
      contains('globals.isTvOS && !usePlayerContextPanel'),
    );
    expect(labs, contains('if (!isTvOS)'));
    expect(plugins, contains('if (!globals.isTvOS)'));
    expect(remote, contains('if (!globals.isTvOS)'));
    expect(remote, contains('if (!globals.isTvOS &&'));
  });

  test('large screen account and settings use supported controls', () {
    final account = File(
      'lib/themes/nipaplay/pages/account/desktop_account_view.dart',
    ).readAsStringSync();
    final appearance = File(
      'lib/settings/pages/appearance_settings_content.dart',
    ).readAsStringSync();
    final player = File(
      'lib/settings/pages/player_settings_content.dart',
    ).readAsStringSync();
    final about = File(
      'lib/settings/pages/about_settings_content.dart',
    ).readAsStringSync();

    expect(account, contains('if (!globals.isTvOS) ...['));
    expect(account, contains('AdaptiveMediaTextField('));
    expect(account, contains("remoteInputFieldId: 'bangumi_access_token'"));
    expect(
      RegExp(r'if \(!isLargeScreen\)').allMatches(appearance).length,
      greaterThanOrEqualTo(4),
    );
    expect(
      player,
      contains('if (visibleKernelType == PlayerKernelType.mediaKit)'),
    );
    expect(
      player,
      contains('else if (visibleKernelType == PlayerKernelType.mdk)'),
    );
    expect(about, contains('NipaplayLargeScreenFocusableAction('));
  });

  test('plugin market and terminal expose focusable large screen surfaces', () {
    final market = File(
      'lib/themes/nipaplay/widgets/plugin_market_dialog.dart',
    ).readAsStringSync();
    final terminal = File(
      'lib/themes/nipaplay/pages/settings/debug_log_viewer_page.dart',
    ).readAsStringSync();
    final folders = File(
      'lib/themes/nipaplay/widgets/library_management_layout.dart',
    ).readAsStringSync();

    expect(market, contains('NipaplayLargeScreenViewContainer.show'));
    expect(market, contains('AdaptiveMediaActionButton('));
    expect(terminal, contains('NipaplayLargeScreenViewContainer.show'));
    expect(terminal, contains('NipaplayLargeScreenFocusableAction('));
    expect(terminal, contains('TvOSRemoteTextInputControl('));
    expect(folders, contains('NipaplayLargeScreenFocusableAction('));
    expect(folders, contains('onActivate: onTap'));
  });

  test('large screen anime cards keep a stable size while focused', () {
    for (final path in <String>[
      'lib/themes/nipaplay/widgets/anime_card.dart',
      'lib/themes/nipaplay/widgets/horizontal_anime_card.dart',
      'lib/pages/dashboard_home_page.dart',
      'lib/themes/nipaplay/widgets/dashboard_home_page_build_hero.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'focusScale:\s*1\.0[1-9]'))),
        reason: '$path must not enlarge focused anime content',
      );
    }
  });

  test('search and manual danmaku matching use television focus surfaces', () {
    final search = File(
      'lib/themes/nipaplay/widgets/tag_search_widget.dart',
    ).readAsStringSync();
    final matcher = File(
      'lib/services/manual_danmaku_matcher.dart',
    ).readAsStringSync();
    final manualDialog = File(
      'lib/themes/nipaplay/widgets/manual_danmaku_dialog.dart',
    ).readAsStringSync();
    final batchDialog = File(
      'lib/themes/nipaplay/widgets/batch_danmaku_dialog.dart',
    ).readAsStringSync();

    expect(search, contains('NipaplayLargeScreenViewContainer.show<void>'));
    expect(search, contains('NipaplayLargeScreenEditableSlider('));
    expect(matcher, contains('NipaplayLargeScreenViewContainer.show'));
    expect(manualDialog, contains('NipaplayLargeScreenFocusableAction('));
    expect(
        manualDialog, contains("remoteInputFieldId: 'manual_danmaku_search'"));
    expect(batchDialog, contains('NipaplayLargeScreenViewContainer.show'));
    expect(batchDialog, contains('NipaplayLargeScreenFocusableAction('));
    expect(batchDialog, contains("remoteInputFieldId: 'batch_danmaku_search'"));
  });

  test('tvOS player menu hides local danmaku and uses Fluent switches', () {
    final tracks = File(
      'lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_tracks_pane.dart',
    ).readAsStringSync();
    final primitives = File(
      'lib/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart',
    ).readAsStringSync();
    final largeScreenPanel = File(
      'lib/themes/nipaplay/widgets/large_screen_player_menu_panel.dart',
    ).readAsStringSync();
    final switchPanes = <String>[
      'lib/themes/cupertino/widgets/player_menu/cupertino_jellyfin_quality_pane.dart',
      'lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_settings_pane.dart',
      'lib/themes/cupertino/widgets/player_menu/cupertino_danmaku_list_pane.dart',
      'lib/themes/cupertino/widgets/player_menu/cupertino_subtitle_settings_pane.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(tracks, contains('if (!globals.isTvOS)'));
    expect(tracks, contains("const Text('加载本地弹幕文件')"));
    expect(primitives, contains('FluentSettingsSwitch('));
    expect(largeScreenPanel, contains('FluentSettingsSwitch('));
    expect(largeScreenPanel, isNot(contains('Icons.toggle_on_rounded')));
    expect(largeScreenPanel, isNot(contains('Icons.toggle_off_rounded')));
    expect(switchPanes, contains('AdaptivePlayerMenuSwitch('));
    expect(switchPanes, isNot(contains('AdaptiveSwitch(')));
  });
}
