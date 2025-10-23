import 'dart:ui';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/widgets/nipaplay_theme/themed_anime_detail.dart';

class CupertinoMediaLibraryPage extends StatefulWidget {
  const CupertinoMediaLibraryPage({super.key});

  @override
  State<CupertinoMediaLibraryPage> createState() => _CupertinoMediaLibraryPageState();
}

class _CupertinoMediaLibraryPageState extends State<CupertinoMediaLibraryPage> {
  final ScrollController _scrollController = ScrollController();
  final DateFormat _timeFormatter = DateFormat('MM-dd HH:mm');
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final cardColor = CupertinoColors.secondarySystemBackground;

    final titleOpacity = (1.0 - (_scrollOffset / 10.0)).clamp(0.0, 1.0);
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          Consumer<SharedRemoteLibraryProvider>(
            builder: (context, provider, _) {
              return CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.only(top: statusBarHeight + 52),
                    sliver: CupertinoSliverRefreshControl(
                      onRefresh: () => _refreshActiveHost(provider),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _buildSectionTitle('NipaPlay 共享媒体库'),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildHostCard(context, provider, cardColor),
                    ),
                  ),
                  if (provider.errorMessage != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _buildErrorBanner(context, provider, cardColor),
                      ),
                    ),
                  ..._buildLibrarySlivers(context, provider, cardColor),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                ],
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      backgroundColor,
                      backgroundColor.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Text(
                    '媒体库',
                    style: CupertinoTheme.of(context).textTheme.navLargeTitleTextStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshActiveHost(SharedRemoteLibraryProvider provider) async {
    if (!provider.hasActiveHost) {
      if (mounted) {
        BlurSnackBar.show(context, '请先添加共享客户端');
      }
      return;
    }
    await provider.refreshLibrary(userInitiated: true);
  }

  Widget _buildHostCard(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    Color cardColor,
  ) {
    final hasHosts = provider.hosts.isNotEmpty;
    final activeHost = provider.activeHost;
    final resolvedCardColor = CupertinoDynamicColor.resolve(cardColor, context);
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoDynamicColor.withBrightness(
            color: CupertinoColors.white,
            darkColor: CupertinoColors.darkBackgroundGray,
          ),
          context,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (provider.isLoading)
            Row(
              children: [
                const Expanded(child: SizedBox()),
                const CupertinoActivityIndicator(radius: 10),
              ],
            ),
          if (!hasHosts)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '尚未添加任何共享客户端',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: labelColor),
                ),
                const SizedBox(height: 6),
                Text(
                  '点击下方按钮添加一台已开启远程访问的 NipaPlay 客户端。',
                  style: TextStyle(fontSize: 14, color: secondaryLabelColor, height: 1.3),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: CupertinoButton(
                    onPressed: () => _openAddHostDialog(provider),
                    color: CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    borderRadius: BorderRadius.circular(14),
                    child: const Text(
                      '添加共享客户端',
                      style: TextStyle(fontSize: 15, color: CupertinoColors.white),
                    ),
                  ),
                ),
              ],
            )
          else if (activeHost == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '请先选择一个共享客户端',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: labelColor),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前未选定共享客户端，请点击下方按钮从已保存的列表中选择。',
                  style: TextStyle(fontSize: 14, color: secondaryLabelColor, height: 1.3),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildActionButton(
                    context,
                    label: '选择客户端',
                    icon: CupertinoIcons.arrow_right_circle,
                    onPressed: provider.hosts.isNotEmpty
                        ? () => SharedRemoteHostSelectionSheet.show(context)
                        : null,
                    primary: true,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow(
                  context,
                  label: '当前客户端',
                  value: activeHost.displayName.isNotEmpty
                      ? activeHost.displayName
                      : activeHost.baseUrl,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '访问地址',
                  value: activeHost.baseUrl,
                  allowWrap: true,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(context, activeHost),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '最后同步',
                  value: _formatDateTime(activeHost.lastConnectedAt),
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  context,
                  label: '番剧数量',
                  value: '${provider.animeSummaries.length}',
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _buildActionButton(
                      context,
                      label: '刷新媒体库',
                      icon: CupertinoIcons.refresh,
                      onPressed: () => _refreshActiveHost(provider),
                      primary: true,
                    ),
                    _buildActionButton(
                      context,
                      label: '切换客户端',
                      icon: CupertinoIcons.arrow_2_circlepath,
                      onPressed: provider.hosts.length > 1
                          ? () => SharedRemoteHostSelectionSheet.show(context)
                          : null,
                    ),
                    _buildActionButton(
                      context,
                      label: '添加客户端',
                      icon: CupertinoIcons.add,
                      onPressed: () => _openAddHostDialog(provider),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
    bool allowWrap = false,
  }) {
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final valueColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    final valueWidget = allowWrap
        ? Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14, height: 1.3),
          )
        : Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14),
            overflow: TextOverflow.ellipsis,
          );

    return Row(
      crossAxisAlignment: allowWrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: valueWidget),
      ],
    );
  }

  Widget _buildStatusRow(BuildContext context, SharedRemoteHost host) {
    final statusColor = host.isOnline
        ? CupertinoDynamicColor.resolve(CupertinoColors.activeGreen, context)
        : CupertinoDynamicColor.resolve(CupertinoColors.systemOrange, context);
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            '连接状态',
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            host.isOnline ? '在线' : '等待连接',
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (host.lastError != null && host.lastError!.isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              host.lastError!,
              style: TextStyle(
                color: CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context),
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    final bool enabled = onPressed != null;
    final Color primaryColor = CupertinoDynamicColor.resolve(CupertinoColors.activeBlue, context);
    final Color secondaryBackground = CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final Color textColor = primary
        ? CupertinoColors.white
        : CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final Color backgroundColor = primary ? primaryColor : secondaryBackground;

    return CupertinoButton(
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      borderRadius: BorderRadius.circular(12),
      minSize: 36,
      color: enabled ? backgroundColor : backgroundColor.withOpacity(0.4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: enabled ? textColor : textColor.withOpacity(0.5),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: enabled ? textColor : textColor.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    Color cardColor,
  ) {
    final resolvedCardColor = CupertinoDynamicColor.resolve(cardColor, context);
    final errorColor = CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: resolvedCardColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: errorColor.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill, color: errorColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.errorMessage ?? '',
              style: TextStyle(color: errorColor, fontSize: 13, height: 1.35),
            ),
          ),
          CupertinoButton(
            onPressed: provider.clearError,
            padding: EdgeInsets.zero,
            minSize: 28,
            child: Icon(
              CupertinoIcons.clear_circled_solid,
              color: errorColor.withOpacity(0.9),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLibrarySlivers(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    Color cardColor,
  ) {
    final hasHosts = provider.hosts.isNotEmpty;
    final hasActiveHost = provider.hasActiveHost;
    final animeSummaries = provider.animeSummaries;

    if (provider.isInitializing) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    if (!hasHosts) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyPlaceholder(
            context,
            icon: CupertinoIcons.cloud,
            title: '尚未添加共享客户端',
            subtitle: '请在下方按钮中添加一台已开启远程访问的 NipaPlay 客户端。',
          ),
        ),
      ];
    }

    if (!hasActiveHost) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyPlaceholder(
            context,
            icon: CupertinoIcons.tray,
            title: '尚未选择客户端',
            subtitle: '请选择一个可用的共享客户端以显示媒体库内容。',
          ),
        ),
      ];
    }

    if (provider.isLoading && animeSummaries.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const Center(child: CupertinoActivityIndicator()),
        ),
      ];
    }

    if (animeSummaries.isEmpty) {
      final subtitle = provider.hasReachableActiveHost
          ? '该客户端的媒体库为空，稍后再试试。'
          : '当前客户端离线或不可达，请确认远程设备在线后重试。';
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyPlaceholder(
            context,
            icon: CupertinoIcons.folder,
            title: '尚未同步到番剧',
            subtitle: subtitle,
          ),
        ),
      ];
    }

    final slivers = <Widget>[];

    if (provider.isLoading) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                CupertinoActivityIndicator(radius: 8),
                SizedBox(width: 8),
                Text('正在刷新…', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      );
    }

    slivers.add(
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 160,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.66,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final anime = animeSummaries[index];
              return _buildAnimeGridItem(context, provider, anime, cardColor);
            },
            childCount: animeSummaries.length,
          ),
        ),
      ),
    );

    return slivers;
  }

  Widget _buildEmptyPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final iconColor = CupertinoDynamicColor.resolve(CupertinoColors.inactiveGray, context);
    final titleColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final subtitleColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: subtitleColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimeGridItem(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime,
    Color cardColor,
  ) {
    final resolvedCardColor = CupertinoDynamicColor.resolve(cardColor, context);
    final labelColor = CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryLabelColor = CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final imageUrl = _resolveImageUrl(provider, anime.imageUrl);

    return GestureDetector(
      onTap: () => _openAnimeDetail(context, provider, anime),
      child: Container(
        decoration: BoxDecoration(
          color: resolvedCardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 7 / 10,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: _buildPosterImage(context, imageUrl),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      anime.nameCn?.isNotEmpty == true ? anime.nameCn! : anime.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _buildEpisodeLabel(anime),
                      style: TextStyle(fontSize: 12, color: secondaryLabelColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Text(
                      '最近观看 ${_timeFormatter.format(anime.lastWatchTime.toLocal())}',
                      style: TextStyle(fontSize: 11, color: secondaryLabelColor.withOpacity(0.8)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPosterImage(BuildContext context, String? imageUrl) {
    final placeholderColor = CupertinoDynamicColor.resolve(CupertinoColors.systemFill, context);

    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        color: placeholderColor,
        child: const Center(
          child: Icon(CupertinoIcons.photo_on_rectangle, size: 26, color: CupertinoColors.inactiveGray),
        ),
      );
    }

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return Container(
          color: placeholderColor,
          child: const Center(
            child: Icon(
              CupertinoIcons.exclamationmark_triangle,
              color: CupertinoColors.systemOrange,
              size: 24,
            ),
          ),
        );
      },
      filterQuality: FilterQuality.low,
    );
  }

  String _buildEpisodeLabel(SharedRemoteAnimeSummary anime) {
    final buffer = StringBuffer('共${anime.episodeCount}集');
    if (anime.hasMissingFiles) {
      buffer.write(' · 缺失文件');
    }
    return buffer.toString();
  }

  String _formatDateTime(DateTime? time) {
    if (time == null) {
      return '尚未同步';
    }
    return _timeFormatter.format(time.toLocal());
  }

  String? _resolveImageUrl(SharedRemoteLibraryProvider provider, String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    if (imageUrl.startsWith('http')) {
      return imageUrl;
    }
    final baseUrl = provider.activeHost?.baseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      return imageUrl;
    }
    if (imageUrl.startsWith('/')) {
      return '$baseUrl$imageUrl';
    }
    return '$baseUrl/$imageUrl';
  }

  Widget _buildSectionTitle(String title) {
    final textStyle = CupertinoTheme.of(context).textTheme.navTitleTextStyle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: textStyle?.copyWith(fontSize: 22, fontWeight: FontWeight.w600) ??
            const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }

  Future<void> _openAddHostDialog(SharedRemoteLibraryProvider provider) async {
    final result = await AdaptiveAlertDialog.show(
      context: context,
      title: '添加NipaPlay共享客户端',
      message: '请输入共享客户端的访问地址',
      icon: 'network',
      input: AdaptiveAlertDialogInput(
        placeholder: '例如：http://192.168.1.100:8080',
        initialValue: '',
        keyboardType: TextInputType.url,
      ),
      actions: [
        AlertAction(
          title: '取消',
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: '添加',
          style: AlertActionStyle.primary,
          onPressed: () {},
        ),
      ],
    );

    if (result != null && result.isNotEmpty) {
      final baseUrl = result.trim();
      if (baseUrl.isEmpty) {
        if (mounted) {
          BlurSnackBar.show(context, '请输入访问地址');
        }
        return;
      }

      try {
        await provider.addHost(
          displayName: baseUrl,
          baseUrl: baseUrl,
        );
        if (mounted) {
          BlurSnackBar.show(context, '已添加共享客户端');
        }
      } catch (e) {
        if (mounted) {
          BlurSnackBar.show(context, '添加失败：$e');
        }
      }
    }
  }

  Future<void> _openAnimeDetail(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    SharedRemoteAnimeSummary anime,
  ) async {
    try {
      await ThemedAnimeDetail.show(
        context,
        anime.animeId,
        sharedSummary: anime,
        sharedEpisodeLoader: () => provider.loadAnimeEpisodes(anime.animeId, force: true),
        sharedEpisodeBuilder: (episode) => provider.buildPlayableItem(
          anime: anime,
          episode: episode,
        ),
        sharedSourceLabel: provider.activeHost?.displayName,
      );
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '打开详情失败: $e');
    }
  }
}
