import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_page_component.dart';
import 'package:nipaplay/media_library/adaptive_media_library_page.dart';
import 'package:nipaplay/pages/dashboard_home_page.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/pages/torrent_download_page.dart';
import 'package:nipaplay/pages/webdav_browser_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/account/material_account_page.dart';

class AdaptiveAppPageContent extends StatelessWidget {
  const AdaptiveAppPageContent({
    super.key,
    required this.components,
  });

  final List<AppPageComponent> components;

  @override
  Widget build(BuildContext context) {
    const controls = UnifiedAppControlRegistry();
    final children = components
        .map(
          (component) => KeyedSubtree(
            key: ValueKey<String>('app-component-${component.id}'),
            child: controls.build(context, component),
          ),
        )
        .toList(growable: false);

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;
    return Column(
      children: [
        for (final child in children) Expanded(child: child),
      ],
    );
  }
}

class UnifiedAppControlRegistry {
  const UnifiedAppControlRegistry();

  Widget build(BuildContext context, AppPageComponent component) {
    return switch (component.type) {
      AppPageComponentType.homeFeed => const DashboardHomePage(),
      AppPageComponentType.playback => const PlayVideoPage(),
      AppPageComponentType.webdavBrowser => const WebDAVBrowserPage(),
      AppPageComponentType.mediaLibrary => const AdaptiveMediaLibraryPage(),
      AppPageComponentType.torrentTasks => const TorrentDownloadPage(),
      AppPageComponentType.account => const UnifiedAccountPage(),
    };
  }
}
