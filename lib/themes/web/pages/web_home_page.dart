import 'package:flutter/material.dart';
import 'package:nipaplay/themes/web/models/web_playback_item.dart';
import 'package:nipaplay/themes/web/pages/web_history_page.dart';
import 'package:nipaplay/themes/web/pages/web_library_page.dart';
import 'package:nipaplay/themes/web/pages/web_management_page.dart';
import 'package:nipaplay/themes/web/pages/web_player_page.dart';
import 'package:nipaplay/themes/web/services/web_remote_api_client.dart';

class WebHomePage extends StatefulWidget {
  const WebHomePage({super.key});

  @override
  State<WebHomePage> createState() => _WebHomePageState();
}

class _WebHomePageState extends State<WebHomePage> {
  int _index = 1;
  final TextEditingController _searchController = TextEditingController();
  WebPlaybackItem? _nowPlaying;

  late final WebRemoteApiClient _api =
      WebRemoteApiClient(baseUrl: _resolveApiBaseUrl());

  void _play(WebPlaybackItem item) {
    setState(() {
      _nowPlaying = item;
      _index = 0;
    });
  }

  String? _resolveApiBaseUrl() {
    final uri = Uri.base;
    final rawBaseUrl = uri.queryParameters['api'] ??
        uri.queryParameters['apiBase'] ??
        uri.queryParameters['baseUrl'];
    final normalizedBaseUrl = rawBaseUrl?.trim();
    if (normalizedBaseUrl != null && normalizedBaseUrl.isNotEmpty) {
      return normalizedBaseUrl;
    }

    final rawPort = uri.queryParameters['apiPort']?.trim();
    final port = int.tryParse(rawPort ?? '');
    if (port != null && port > 0 && port < 65536) {
      final scheme = uri.scheme.isNotEmpty ? uri.scheme : 'http';
      final host = uri.host.isNotEmpty ? uri.host : 'localhost';
      return '$scheme://$host:$port';
    }

    return null;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bool showRail = width >= 980;
    final bool extendedRail = width >= 1200;

    final String searchQuery = _searchController.text;

    final page = switch (_index) {
      0 => WebPlayerPage(item: _nowPlaying),
      1 => WebLibraryPage(api: _api, searchQuery: searchQuery, onPlay: _play),
      2 => WebManagementPage(api: _api, onPlay: _play),
      3 => WebHistoryPage(api: _api, searchQuery: searchQuery, onPlay: _play),
      _ => WebLibraryPage(api: _api, searchQuery: searchQuery, onPlay: _play),
    };

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const _WebLogo(),
            const SizedBox(width: 12),
            Expanded(
              child: _SearchBar(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '打开 API /info',
            onPressed: () async {
              final info = await _api.fetchInfoSafe();
              if (!context.mounted) return;
              showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('远程访问 API'),
                  content: Text(info ?? '无法获取 /api/info（请确认服务端已开启远程访问）'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.info_outline),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: showRail
          ? null
          : Drawer(
              child: SafeArea(
                child: _NavList(
                  selectedIndex: _index,
                  onSelected: (index) {
                    setState(() {
                      _index = index;
                    });
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            ),
      body: Row(
        children: [
          if (showRail)
            NavigationRail(
              extended: extendedRail,
              selectedIndex: _index,
              onDestinationSelected: (value) {
                setState(() {
                  _index = value;
                });
              },
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.play_circle_outline),
                  selectedIcon: Icon(Icons.play_circle),
                  label: Text('播放'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.video_library_outlined),
                  selectedIcon: Icon(Icons.video_library),
                  label: Text('媒体库'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.folder_open_outlined),
                  selectedIcon: Icon(Icons.folder_open),
                  label: Text('库管理'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Text('观看记录'),
                ),
              ],
            ),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class _WebLogo extends StatelessWidget {
  const _WebLogo();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.play_circle_fill, color: colorScheme.primary),
        const SizedBox(width: 8),
        const Text(
          'NipaPlay',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: '搜索标题…',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

class _NavList extends StatelessWidget {
  const _NavList({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const ListTile(
          leading: Icon(Icons.play_circle_fill),
          title: Text('NipaPlay Web'),
          subtitle: Text('远程访问'),
        ),
        const Divider(),
        _navTile(
          context,
          index: 0,
          icon: Icons.play_circle_outline,
          selectedIcon: Icons.play_circle,
          label: '播放',
        ),
        _navTile(
          context,
          index: 1,
          icon: Icons.video_library_outlined,
          selectedIcon: Icons.video_library,
          label: '媒体库',
        ),
        _navTile(
          context,
          index: 2,
          icon: Icons.folder_open_outlined,
          selectedIcon: Icons.folder_open,
          label: '库管理',
        ),
        _navTile(
          context,
          index: 3,
          icon: Icons.history_outlined,
          selectedIcon: Icons.history,
          label: '观看记录',
        ),
      ],
    );
  }

  Widget _navTile(
    BuildContext context, {
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final bool selected = selectedIndex == index;
    return ListTile(
      leading: Icon(selected ? selectedIcon : icon),
      title: Text(label),
      selected: selected,
      onTap: () => onSelected(index),
    );
  }
}
