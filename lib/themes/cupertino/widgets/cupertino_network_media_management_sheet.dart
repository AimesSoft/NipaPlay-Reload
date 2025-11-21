import 'package:flutter/cupertino.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';

/// 原生 iOS 26 风格的网络媒体库管理页面（完整功能版）
class CupertinoNetworkMediaManagementSheet extends StatefulWidget {
  const CupertinoNetworkMediaManagementSheet({
    super.key,
    required this.serverType,
  });

  final MediaServerType serverType;

  @override
  State<CupertinoNetworkMediaManagementSheet> createState() =>
      _CupertinoNetworkMediaManagementSheetState();
}

class _CupertinoNetworkMediaManagementSheetState
    extends State<CupertinoNetworkMediaManagementSheet> {
  late Set<String> _selectedLibraryIds;
  bool _transcodeSettingsExpanded = false;
  bool _transcodeEnabled = false;
  late JellyfinVideoQuality _selectedQuality;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
    _initializeTranscodeSettings();
  }

  void _initializeSelection() {
    final provider = _getProvider();
    _selectedLibraryIds = provider.selectedLibraryIds.toSet();
  }

  void _initializeTranscodeSettings() {
    _selectedQuality = JellyfinVideoQuality.original;
    _transcodeEnabled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        if (widget.serverType == MediaServerType.jellyfin) {
          final provider = context.read<JellyfinTranscodeProvider>();
          if (mounted) {
            setState(() {
              _transcodeEnabled = provider.transcodeEnabled;
              _selectedQuality = provider.currentVideoQuality;
            });
          }
        } else {
          final provider = context.read<EmbyTranscodeProvider>();
          if (mounted) {
            setState(() {
              _transcodeEnabled = provider.transcodeEnabled;
              _selectedQuality = provider.currentVideoQuality;
            });
          }
        }
      } catch (e) {
        debugPrint('初始化转码设置失败: $e');
      }
    });
  }

  dynamic _getProvider() {
    if (widget.serverType == MediaServerType.jellyfin) {
      return context.read<JellyfinProvider>();
    } else {
      return context.read<EmbyProvider>();
    }
  }

  String get _serverName =>
      widget.serverType == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';

  Color get _accentColor => widget.serverType == MediaServerType.jellyfin
      ? CupertinoColors.systemBlue
      : const Color(0xFF52B54B);

  @override
  Widget build(BuildContext context) {
    final provider = _getProvider();
    final libraries = provider.availableLibraries;
    final username = provider.username;
    final serverUrl = provider.serverUrl;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: '$_serverName 媒体库',
        useNativeToolbar: true,
        actions: [
          AdaptiveAppBarAction(
            iosSymbol: 'checkmark',
            icon: CupertinoIcons.check_mark,
            onPressed: () async {
              await provider.updateSelectedLibraries(
                _selectedLibraryIds.toList(),
              );
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: CupertinoPageScaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground,
          context,
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // 顶部空间
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
              // 服务器信息部分
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemBackground,
                        context,
                      ),
                      border: Border.all(
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemGrey3,
                          context,
                        ),
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          // 服务器 URL
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: _accentColor.withValues(alpha: 0.15),
                                ),
                                child: Icon(
                                  CupertinoIcons.globe,
                                  color: _accentColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '服务器',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.secondaryLabel,
                                          context,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      serverUrl ?? '未知',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 用户信息
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  color: _accentColor.withValues(alpha: 0.15),
                                ),
                                child: Icon(
                                  CupertinoIcons.person,
                                  color: _accentColor,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '账户',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: CupertinoDynamicColor.resolve(
                                          CupertinoColors.secondaryLabel,
                                          context,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      username ?? '匿名',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 媒体库部分标题
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '媒体库',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label,
                        context,
                      ),
                    ),
                  ),
                ),
              ),

              // 媒体库列表
              if (libraries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.collections,
                            size: 44,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.inactiveGray,
                              context,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无媒体库',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.label,
                                context,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '请检查服务器连接',
                            style: TextStyle(
                              fontSize: 14,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.secondaryLabel,
                                context,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final library = libraries[index];
                        final isSelected =
                            _selectedLibraryIds.contains(library.id);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isSelected
                                ? _accentColor.withValues(alpha: 0.1)
                                : CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemBackground,
                                    context,
                                  ),
                            border: Border.all(
                              color: isSelected
                                  ? _accentColor
                                  : CupertinoDynamicColor.resolve(
                                      CupertinoColors.systemGrey3,
                                      context,
                                    ),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: CupertinoButton(
                            onPressed: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedLibraryIds.remove(library.id);
                                } else {
                                  _selectedLibraryIds.add(library.id);
                                }
                              });
                            },
                            padding: EdgeInsets.zero,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? CupertinoIcons.checkmark_circle_fill
                                        : CupertinoIcons.circle,
                                    color: isSelected
                                        ? _accentColor
                                        : CupertinoDynamicColor.resolve(
                                            CupertinoColors.secondaryLabel,
                                            context,
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          library.name,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? _accentColor
                                                : CupertinoDynamicColor.resolve(
                                                    CupertinoColors.label,
                                                    context,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _getLibraryTypeLabel(library.type),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: CupertinoDynamicColor.resolve(
                                              CupertinoColors.secondaryLabel,
                                              context,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: libraries.length,
                    ),
                  ),
                ),

              // 转码设置部分
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: _buildTranscodeSection(),
                ),
              ),

              // 底部空间
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTranscodeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 转码设置标题
        GestureDetector(
          onTap: () {
            setState(() {
              _transcodeSettingsExpanded = !_transcodeSettingsExpanded;
            });
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: _transcodeSettingsExpanded
                  ? const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                    )
                  : BorderRadius.circular(10),
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemBackground,
                context,
              ),
              border: Border.all(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.systemGrey3,
                  context,
                ),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: CupertinoColors.systemOrange.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    CupertinoIcons.settings,
                    color: CupertinoColors.systemOrange,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '转码设置',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: CupertinoDynamicColor.resolve(
                            CupertinoColors.label,
                            context,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '当前默认质量: ${_selectedQuality.displayName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoDynamicColor.resolve(
                            CupertinoColors.secondaryLabel,
                            context,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _transcodeSettingsExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondaryLabel,
                    context,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_transcodeSettingsExpanded)
          Container(
            margin: const EdgeInsets.only(top: 0),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(10),
                bottomRight: Radius.circular(10),
              ),
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemBackground,
                context,
              ),
              border: Border(
                left: BorderSide(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey3,
                    context,
                  ),
                ),
                right: BorderSide(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey3,
                    context,
                  ),
                ),
                bottom: BorderSide(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey3,
                    context,
                  ),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 启用转码开关
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '启用转码',
                          style: TextStyle(
                            fontSize: 14,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.label,
                              context,
                            ),
                          ),
                        ),
                      ),
                      CupertinoSwitch(
                        value: _transcodeEnabled,
                        onChanged: _handleTranscodeEnabledChanged,
                        activeColor: CupertinoColors.systemOrange,
                      ),
                    ],
                  ),
                  if (_transcodeEnabled) ...[
                    const SizedBox(height: 16),
                    Text(
                      '默认清晰度',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.label,
                          context,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...JellyfinVideoQuality.values.map((quality) {
                      final isSelected = _selectedQuality == quality;
                      return GestureDetector(
                        onTap: () => _handleQualityChanged(quality),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: isSelected
                                ? CupertinoColors.systemOrange.withValues(alpha: 0.1)
                                : CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemGrey5,
                                    context,
                                  ),
                            border: Border.all(
                              color: isSelected
                                  ? CupertinoColors.systemOrange
                                  : CupertinoDynamicColor.resolve(
                                      CupertinoColors.systemGrey4,
                                      context,
                                    ),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                color: isSelected
                                    ? CupertinoColors.systemOrange
                                    : CupertinoDynamicColor.resolve(
                                        CupertinoColors.secondaryLabel,
                                        context,
                                      ),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  quality.displayName,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? CupertinoColors.systemOrange
                                        : CupertinoDynamicColor.resolve(
                                            CupertinoColors.label,
                                            context,
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _handleTranscodeEnabledChanged(bool enabled) async {
    try {
      bool success = false;
      if (widget.serverType == MediaServerType.jellyfin) {
        try {
          final provider = context.read<JellyfinTranscodeProvider>();
          success = await provider.setTranscodeEnabled(enabled);
        } catch (_) {
          // 回退处理
          success = false;
        }
      } else {
        try {
          final provider = context.read<EmbyTranscodeProvider>();
          success = await provider.setTranscodeEnabled(enabled);
        } catch (_) {
          success = false;
        }
      }

      if (success) {
        setState(() {
          _transcodeEnabled = enabled;
          if (!enabled) {
            _selectedQuality = JellyfinVideoQuality.original;
          }
        });
      }
    } catch (e) {
      debugPrint('更新转码状态失败: $e');
    }
  }

  Future<void> _handleQualityChanged(JellyfinVideoQuality quality) async {
    if (_selectedQuality == quality) return;

    try {
      bool success = false;
      if (widget.serverType == MediaServerType.jellyfin) {
        try {
          final provider = context.read<JellyfinTranscodeProvider>();
          success = await provider.setDefaultVideoQuality(quality);
          if (quality != JellyfinVideoQuality.original) {
            await provider.setTranscodeEnabled(true);
          }
        } catch (_) {
          success = false;
        }
      } else {
        try {
          final provider = context.read<EmbyTranscodeProvider>();
          success = await provider.setDefaultVideoQuality(quality);
          if (quality != JellyfinVideoQuality.original) {
            await provider.setTranscodeEnabled(true);
          }
        } catch (_) {
          success = false;
        }
      }

      if (success) {
        setState(() {
          _selectedQuality = quality;
        });
      }
    } catch (e) {
      debugPrint('更新默认质量失败: $e');
    }
  }

  String _getLibraryTypeLabel(String? type) {
    switch (type) {
      case 'tvshows':
        return '电视剧库';
      case 'movies':
        return '电影库';
      case 'boxsets':
        return '合集库';
      case 'folders':
        return '文件夹';
      case 'mixed':
        return '混合库';
      default:
        return '媒体库';
    }
  }
}
