import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_library_management_tab.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/pages/media_library_page.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/library_management_tab.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_library_view.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_library_view.dart';

class FluentMediaLibraryTabs extends StatefulWidget {
  final int initialIndex;
  final ValueChanged<WatchHistoryItem> onPlayEpisode;
  final int mediaLibraryVersion;

  const FluentMediaLibraryTabs({
    super.key,
    this.initialIndex = 0,
    required this.onPlayEpisode,
    required this.mediaLibraryVersion,
  });

  @override
  State<FluentMediaLibraryTabs> createState() => _FluentMediaLibraryTabsState();
}

class _FluentMediaLibraryTabsState extends State<FluentMediaLibraryTabs> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<JellyfinProvider, EmbyProvider>(
      builder: (context, jellyfinProvider, embyProvider, child) {
        final sharedProvider = Provider.of<SharedRemoteLibraryProvider>(context);
        final isJellyfinConnected = jellyfinProvider.isConnected;
        final isEmbyConnected = embyProvider.isConnected;

        final tabs = _buildTabs(isJellyfinConnected, isEmbyConnected, sharedProvider);

        // Ensure currentIndex is valid
        if (_currentIndex >= tabs.length) {
          _currentIndex = 0;
        }

        return TabView(
          currentIndex: _currentIndex,
          onChanged: (index) => setState(() => _currentIndex = index),
          tabs: tabs,
          tabWidthBehavior: TabWidthBehavior.equal,
          closeButtonVisibility: CloseButtonVisibilityMode.never,
        );
      },
    );
  }

  List<Tab> _buildTabs(
    bool isJellyfinConnected,
    bool isEmbyConnected,
    SharedRemoteLibraryProvider sharedProvider,
  ) {
    final List<Tab> tabs = [
      Tab(
        text: const Text('媒体库'),
        body: MediaLibraryPage(
          key: ValueKey('mediaLibrary_${widget.mediaLibraryVersion}'),
          onPlayEpisode: widget.onPlayEpisode,
        ),
      ),
      Tab(
        text: const Text('库管理'),
        body: FluentLibraryManagementTab(
          onPlayEpisode: widget.onPlayEpisode,
        ),
      ),
    ];

    if (sharedProvider.hosts.isNotEmpty) {
      tabs.add(
        Tab(
          text: const Text('共享媒体'),
          body: SharedRemoteLibraryView(
            onPlayEpisode: widget.onPlayEpisode,
          ),
        ),
      );
    }

    if (isJellyfinConnected) {
      tabs.add(
        Tab(
          text: const Text('Jellyfin'),
          body: NetworkMediaLibraryView(
            serverType: NetworkMediaServerType.jellyfin,
            onPlayEpisode: widget.onPlayEpisode,
          ),
        ),
      );
    }

    if (isEmbyConnected) {
      tabs.add(
        Tab(
          text: const Text('Emby'),
          body: NetworkMediaLibraryView(
            serverType: NetworkMediaServerType.emby,
            onPlayEpisode: widget.onPlayEpisode,
          ),
        ),
      );
    }

    return tabs;
  }
}
