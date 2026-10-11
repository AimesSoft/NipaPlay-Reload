import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/app/unified_app_view_presenter.dart';
import 'package:nipaplay/settings/unified_settings_page.dart';
import 'package:nipaplay/settings/pages/developer_options_settings_content.dart';
import 'package:nipaplay/settings/pages/about_settings_content.dart';
import 'package:nipaplay/settings/about_settings_data.dart';
import 'package:nipaplay/services/folder_opener.dart';
import 'package:nipaplay/services/file_log_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_upload_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/settings/pages/webdav_quick_settings_content.dart';
import 'package:nipaplay/media_library/adaptive_media_library_page.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/pages/new_series_page.dart';
import 'package:nipaplay/pages/media_server_detail_page.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tag_search_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/plugin_market_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/smb_connection_dialog.dart';
import 'classic_home.dart';
import 'package:nipaplay/app/app_navigation_scope.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// Observes the existing visible Classic widgets after dispatching navigation.
final class ClassicUiOpen {
  ClassicUiOpen({this.harnessPath});
  final Future<String> Function()? harnessPath;
  Element? _stateElement<T>([bool Function(T)? matches]) {
    Element? found;
    void visit(Element element) {
      if (element.widget is Offstage && (element.widget as Offstage).offstage)
        return;
      if (element is StatefulElement &&
          element.state is T &&
          ModalRoute.of(element)?.isCurrent != false &&
          (matches == null || matches(element.state as T))) found = element;
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  Future<JsonMap?> target(JsonMap target) async {
    final context = globals.navigatorKey.currentState?.overlay?.context;
    if (context == null) return null;
    if (target['system'] case final String system) {
      final path = system == 'harness'
          ? await harnessPath?.call()
          : await FileLogService().getLogDirectoryPath();
      if (path == null) return null;
      final accepted = system == 'harness'
          ? await FolderOpener.open(path)
          : await FileLogService().openLogDirectory();
      return !accepted
          ? null
          : {
              'kind': 'folder_request',
              'presentation': 'system',
              'folder': system,
              'path': path,
              'accepted': true,
              'visibilityVerified': false,
            };
    }
    if (target['aboutLink'] case final String link) {
      final (title, url) = switch (link) {
        'community' => (
            context.l10n.openSourceCommunity,
            AboutSettingsData.repositoryUrl
          ),
        'repository' => (
            'AimesSoft/NipaPlay-Reload',
            AboutSettingsData.repositoryUrl
          ),
        'qq_group' => (
            context.l10n.aboutQqGroup('961207150'),
            AboutSettingsData.qqGroupUrl
          ),
        'website' => (
            context.l10n.aboutOfficialWebsite,
            AboutSettingsData.officialWebsiteUrl
          ),
        'sponsor' => (
            context.l10n.aboutAfdianSponsorPage,
            AboutSettingsData.afdianUrl
          ),
        _ => throw StateError(link),
      };
      if (target['qr'] == true || globals.isTelevision) {
        if (await this.target({'page': 'settings', 'subpage': 'about'}) == null)
          return null;
        final state =
            (_stateElement<AboutWindowNavigation>() as StatefulElement?)?.state
                as AboutWindowNavigation?;
        if (state == null) return null;
        state.showLinkQr(title, url);
        await WidgetsBinding.instance.endOfFrame;
        return _find<QrImageView>((_) => true) == null ||
                _find<Text>((w) => w.data == url) == null
            ? null
            : {
                'kind': 'dialog',
                'dialog': 'about_link_qr',
                'link': link,
                'url': url,
              };
      }
      return !await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication)
          ? null
          : {
              'kind': 'webpage_request',
              'presentation': 'system',
              'link': link,
              'url': url,
              'accepted': true,
              'visibilityVerified': false
            };
    }
    if (target['page'] == 'settings') {
      final subpage = target['subpage'] as String? ?? 'about';
      if (subpage == 'webdav_quick') {
        unawaited(NipaplayWindow.show<void>(
            context: context, child: const WebDAVQuickSettingsContent()));
        await WidgetsBinding.instance.endOfFrame;
        return _find<WebDAVQuickSettingsContent>((_) => true) == null
            ? null
            : {
                'kind': 'settings_subpage',
                'page': 'settings',
                'subpage': subpage
              };
      }
      unawaited(UnifiedAppViewPresenter.show<void>(context,
          viewId: 'settings', initialSubpageId: subpage));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final element = _stateElement<UnifiedSettingsSelection>();
      final selected =
          (element as StatefulElement?)?.state as UnifiedSettingsSelection?;
      if (selected?.selectedSettingsEntry == null) return null;
      return {
        'kind': 'settings_subpage',
        'page': 'settings',
        'subpage': selected!.selectedSettingsEntry,
        'matched': selected.selectedSettingsEntry == subpage
      };
    }
    if (target['page'] == 'media_library') {
      if (!await page('media_library')) return null;
      final element =
          _stateElement<ClassicLibraryNavigation>() as StatefulElement?;
      final state = element?.state as ClassicLibraryNavigation?;
      final id = target['subpage'] as String;
      if (state == null) return null;
      final accepted = state.selectLibrarySection(id);
      await WidgetsBinding.instance.endOfFrame;
      return {
        'kind': 'page',
        'page': 'media_library',
        'subpage': state.selectedLibrarySection,
        'matched': accepted && state.selectedLibrarySection == id,
      };
    }
    if (target['page'] == 'new_series') {
      unawaited(NipaplayWindow.show<void>(
          context: context,
          child: const NipaplayWindowScaffold(
              child: NewSeriesPage(deferInitialLoad: true))));
      await WidgetsBinding.instance.endOfFrame;
      return _find<NewSeriesPage>((_) => true) == null
          ? null
          : {'kind': 'page', 'page': 'new_series', 'presentation': 'window'};
    }
    if (target['serverItem'] case final Map item) {
      final provider = item['provider'] as String;
      final id = item['itemId'] as String;
      final type = provider == 'jellyfin'
          ? MediaServerType.jellyfin
          : MediaServerType.emby;
      unawaited(
          MediaServerDetailPage.show(context, id, type).then((result) async {
        if (result == null) {
          return;
        }
        await PlaybackService().play(PlayableItem(
            videoPath: result.filePath,
            title: result.animeName,
            subtitle: result.episodeTitle,
            animeId: result.animeId,
            episodeId: result.episodeId,
            historyItem: result));
      }));
      await WidgetsBinding.instance.endOfFrame;
      return _find<MediaServerDetailPage>(
                  (w) => w.mediaId == id && w.serverType == type) ==
              null
          ? null
          : {'kind': 'server_detail', 'provider': provider, 'itemId': id};
    }
    if (target['sourceItem'] case final Map item) {
      if (!await page('home')) return null;
      final id = (item['animeId'] as num).toInt();
      if (classicHome()?.openSourceDetail(item['provider'] as String, id) !=
          true) return null;
      for (var attempt = 0; attempt < 400; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        final detail = _find<AnimeDetailPage>(
            (page) => page.animeId == id && page.sharedSummary != null);
        if (detail != null) {
          return {
            'kind': 'source_detail',
            'provider': item['provider'],
            'animeId': detail.animeId,
            'sourceLabel': detail.sharedSourceLabel,
            'episodeContext': detail.sharedEpisodeLoader != null
          };
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return null;
    }
    if (target['libraryItem'] case final Map item) {
      final source = item['source'] as String;
      final section = source == 'local' ? 'local_library' : '${source}_library';
      final openedSection =
          await this.target({'page': 'media_library', 'subpage': section});
      if (openedSection == null || openedSection['matched'] == false)
        return null;
      final state = (_stateElement<ClassicLibraryCardNavigation>(
              (state) => state.librarySource == source) as StatefulElement?)
          ?.state as ClassicLibraryCardNavigation?;
      final id = (item['animeId'] as num).toInt();
      if (state?.librarySource != source || !state!.openLibraryAnime(id))
        return null;
      await WidgetsBinding.instance.endOfFrame;
      final detail = _find<AnimeDetailPage>((page) => page.animeId == id);
      return detail == null
          ? null
          : {
              'kind': 'library_detail',
              'source': source,
              'animeId': detail.animeId,
              'episodeContext': detail.sharedEpisodeLoader != null
            };
    }
    final dialog = target['dialog'] as String;
    switch (dialog) {
      case 'video_picker' || 'video_gallery':
        if (dialog == 'video_gallery' && globals.isDesktop) return null;
        if (!await page('video')) return null;
        final state =
            (_stateElement<ClassicVideoPickerNavigation>() as StatefulElement?)
                ?.state as ClassicVideoPickerNavigation?;
        if (state == null) return null;
        unawaited(state.pickVideo(dialog == 'video_gallery'));
        await WidgetsBinding.instance.endOfFrame;
        return {
          'kind': 'native_picker_request',
          'dialog': dialog,
          'requested': true,
          'visibilityVerified': false
        };
      case 'quarterly_comment':
        if (!await page('home') ||
            classicHome()
                    ?.openQuarterlyComment(target['reviewAnimeId'] as int) !=
                true) return null;
      case 'account_login' || 'account_register':
        if (!await page('account')) return null;
        final element =
            _stateElement<AccountPageController>() as StatefulElement?;
        final state = element?.state as AccountPageController?;
        if (state == null) return null;
        if (dialog == 'account_login') {
          state.showLoginDialog();
        } else {
          state.showRegisterDialog();
        }
      case 'appreciation':
        if (await this.target({'page': 'settings', 'subpage': 'about'}) == null)
          return null;
        final state =
            (_stateElement<AboutWindowNavigation>() as StatefulElement?)?.state
                as AboutWindowNavigation?;
        if (state == null) return null;
        state.showAppreciation();
      case 'plugin_readme':
        unawaited(PluginMarketDialog.show(context));
        await WidgetsBinding.instance.endOfFrame;
        final state =
            (_stateElement<PluginMarketNavigation>() as StatefulElement?)?.state
                as PluginMarketNavigation?;
        if (state == null ||
            !await state
                .openReadme(target['pluginId'] as String)
                .timeout(const Duration(seconds: 30))) return null;
        await WidgetsBinding.instance.endOfFrame;
        return {
          'kind': 'dialog',
          'dialog': dialog,
          'pluginId': state.readmePluginId
        };
      case 'search':
        unawaited(TagSearchModal.show(context));
      case 'watch_history' || 'trending' || 'trending_filter':
        if (classicHome() == null) {
          if (!await page('home')) return null;
        }
        final home = classicHome();
        if (home == null) return null;
        home.openHomeDialog(dialog);
      case 'plugin_market':
        unawaited(PluginMarketDialog.show(context));
      case 'jellyfin_connection' || 'emby_connection':
        unawaited(NetworkMediaServerDialog.show(
            context,
            dialog == 'jellyfin_connection'
                ? MediaServerType.jellyfin
                : MediaServerType.emby));
      case 'webdav_connection':
        unawaited(WebDAVConnectionDialog.show(context));
      case 'smb_connection':
        unawaited(SMBConnectionDialog.show(context));
      case 'logs' || 'dependency_versions' || 'ui_preview' || 'build_info':
        const DeveloperOptionsSettingsContent().openWindow(context, dialog);
      default:
        return null;
    }
    await WidgetsBinding.instance.endOfFrame;
    final names = switch (dialog) {
      'search' => ['TagSearchModal'],
      'quarterly_comment' => ['BangumiCommentDialog'],
      'watch_history' => ['WatchHistoryPage'],
      'account_login' || 'account_register' => [
          'BlurLoginDialog',
          'CupertinoAlertDialog'
        ],
      'appreciation' => ['NipaplayWindowScaffold', 'CupertinoBottomSheet'],
      'trending' => ['_NipaplayFullTrendingView'],
      'trending_filter' => ['_NipaplayTrendingFilterControls'],
      'plugin_market' => ['PluginMarketDialog'],
      'jellyfin_connection' || 'emby_connection' => [
          'NetworkMediaServerDialog',
          'BlurLoginDialog'
        ],
      'webdav_connection' => ['_WebDAVForm'],
      'smb_connection' => ['_SMBConnectionForm'],
      'logs' => ['DebugLogViewerPage', 'CupertinoDebugLogViewerSheet'],
      'dependency_versions' => [
          'DependencyVersionsWindow',
          'CupertinoDependencyVersionsSheet'
        ],
      'ui_preview' => ['NipaplayUiPreviewWindow'],
      'build_info' => ['NipaplayWindowScaffold', 'CupertinoBuildInfoSheet'],
      _ => <String>[],
    };
    final opened =
        _findElement<Widget>((w) => names.contains(w.runtimeType.toString()));
    if (dialog == 'build_info' &&
        _find<Text>((w) => w.data == context.l10n.buildInfo) == null)
      return null;
    if (dialog == 'appreciation' &&
        _find<Text>((w) => w.data == context.l10n.appreciationCode) == null)
      return null;
    return opened == null
        ? null
        : {
            'kind': 'dialog',
            'dialog': dialog,
            'widget': opened.widget.runtimeType.toString()
          };
  }

  Future<JsonMap> close() async {
    final navigator = globals.navigatorKey.currentState;
    if (navigator == null || !navigator.canPop()) return {'closed': false};
    navigator.pop();
    await WidgetsBinding.instance.endOfFrame;
    return {'closed': true};
  }

  Element? _findElement<T extends Widget>(bool Function(T) matches,
      {Element? root}) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is T &&
          matches(widget) &&
          ModalRoute.of(element)?.isCurrent != false) found = element;
      element.visitChildren(visit);
    }

    (root ?? WidgetsBinding.instance.rootElement)?.visitChildren(visit);
    return found;
  }

  T? _find<T extends Widget>(bool Function(T) matches) =>
      _findElement(matches)?.widget as T?;

  Future<bool> page(String page) async {
    globals.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    final scope =
        _find<AppNavigationScope>((scope) => scope.pageIds.contains(page));
    if (scope == null) return false;
    scope.onSelectPage(page);
    final controller = _find<CustomScaffold>(
            (widget) => widget.pageIsHome && widget.pageIds.contains(page))
        ?.tabController;
    if (controller != null && controller.indexIsChanging) {
      final settled = Completer<bool>();
      void observe() {
        if (!controller.indexIsChanging && !settled.isCompleted)
          settled.complete(true);
      }

      controller.addListener(observe);
      try {
        if (!await settled.future
            .timeout(const Duration(seconds: 2), onTimeout: () => false)) {
          return false;
        }
      } finally {
        controller.removeListener(observe);
      }
    }
    await WidgetsBinding.instance.endOfFrame;
    final scaffold = _findElement<CustomScaffold>(
        (widget) => widget.pageIsHome && widget.pageIds.contains(page));
    if (scaffold != null) {
      final targetIndex =
          (scaffold.widget as CustomScaffold).pageIds.indexOf(page);
      // The ancestor scope can retain its old selectedPageId while the
      // scaffold rebuilds from its TabController. Observe the rendered body.
      final body = _findElement<SwitchableView>((_) => true, root: scaffold);
      return (body?.widget as SwitchableView?)?.currentIndex == targetIndex;
    }
    return _find<AppNavigationScope>((scope) => scope.selectedPageId == page) !=
        null;
  }

  Future<bool> detail(int animeId) async {
    final context = globals.navigatorKey.currentState?.overlay?.context;
    if (context == null) return false;
    if (_find<AnimeDetailPage>((_) => true) != null) {
      AnimeDetailPage.popIfOpen();
    }
    unawaited(ThemedAnimeDetail.show(context, animeId));
    await WidgetsBinding.instance.endOfFrame;
    return _find<AnimeDetailPage>((page) => page.animeId == animeId) != null;
  }
}
