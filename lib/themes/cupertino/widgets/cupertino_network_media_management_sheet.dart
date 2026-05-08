import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/jellyfin_transcode_provider.dart';
import 'package:nipaplay/providers/emby_transcode_provider.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
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
  List<ServerAddress> _serverAddresses = [];
  String? _currentAddressId;
  bool _transcodeSettingsExpanded = false;
  bool _transcodeEnabled = false;
  late JellyfinVideoQuality _selectedQuality;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
    _loadAddressInfo();
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

  dynamic _getService() {
    if (widget.serverType == MediaServerType.jellyfin) {
      return JellyfinService.instance;
    } else {
      return EmbyService.instance;
    }
  }

  void _loadAddressInfo() {
    final service = _getService();
    _serverAddresses = List<ServerAddress>.from(service.getServerAddresses());
    _currentAddressId = service.currentAddressId;
    if (_serverAddresses.isEmpty) {
      _currentAddressId = null;
      service.currentAddressId = null;
      return;
    }

    final hasCurrentAddress = _currentAddressId != null &&
        _serverAddresses.any((address) => address.id == _currentAddressId);
    if (!hasCurrentAddress) {
      final provider = _getProvider();
      final currentUrl = provider.serverUrl?.toString();
      final matched = _serverAddresses.where(
        (address) => address.normalizedUrl == currentUrl,
      );
      _currentAddressId =
          matched.isNotEmpty ? matched.first.id : _serverAddresses.first.id;
      service.currentAddressId = _currentAddressId;
    }
  }

  String get _serverName =>
      widget.serverType == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby';

  Color get _accentColor => widget.serverType == MediaServerType.jellyfin
      ? CupertinoColors.systemBlue
      : const Color(0xFF52B54B);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = _getProvider();
    final libraries = provider.availableLibraries;
    final username = provider.username;
    final serverUrl = provider.serverUrl;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: l10n.serverMediaLibraryTitle(_serverName),
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
                                      l10n.serverLabel,
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
                                      serverUrl ?? l10n.mediaServerUnknown,
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
                                      l10n.accountLabel,
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
                                      username ?? l10n.mediaServerAnonymous,
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

              if (_serverAddresses.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: _buildAddressSection(),
                  ),
                ),

              // 媒体库部分标题
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    l10n.mediaLibrary,
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
                            l10n.noMediaLibrary,
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
                            l10n.checkServerConnection,
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
                                          _getLibraryTypeLabel(
                                            context,
                                            library.type,
                                          ),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                CupertinoDynamicColor.resolve(
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

  Widget _buildAddressSection() {
    final sortedAddresses = _sortedAddresses();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '服务器地址',
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
              CupertinoButton(
                minimumSize: Size.zero,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                onPressed: _handleAddAddress,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(CupertinoIcons.add_circled,
                        size: 17, color: _accentColor),
                    const SizedBox(width: 4),
                    Text(
                      '添加',
                      style: TextStyle(
                        color: _accentColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: CupertinoDynamicColor.resolve(
              CupertinoColors.systemBackground,
              context,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemGrey3,
                context,
              ),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < sortedAddresses.length; i++) ...[
                _buildAddressRow(sortedAddresses[i]),
                if (i != sortedAddresses.length - 1)
                  Container(
                    height: 1,
                    margin: const EdgeInsets.only(left: 56),
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.separator,
                      context,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressRow(ServerAddress address) {
    final isCurrent = address.id == _currentAddressId;
    final labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);
    final secondaryColor =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final statusColor = isCurrent
        ? _accentColor
        : CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey,
            context,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isCurrent
                  ? CupertinoIcons.checkmark_circle_fill
                  : CupertinoIcons.link,
              size: 18,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        address.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: labelColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 8),
                      _buildAddressBadge('当前', _accentColor),
                    ] else if (_isPreferredAddress(address)) ...[
                      const SizedBox(width: 8),
                      _buildAddressBadge('优先', _accentColor),
                    ] else if (address.priority > 0) ...[
                      const SizedBox(width: 8),
                      _buildAddressBadge(
                          'P${address.priority}', secondaryColor),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  address.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondaryColor,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    if (!isCurrent)
                      _buildAddressTextAction(
                        '切换',
                        () => _handleSwitchAddress(address),
                      ),
                    _buildAddressTextAction(
                      '优先级',
                      () => _showPriorityDialog(address),
                    ),
                    if (_serverAddresses.length > 1)
                      _buildAddressTextAction(
                        '删除',
                        () => _confirmRemoveAddress(address),
                        destructive: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAddressTextAction(
    String label,
    VoidCallback onPressed, {
    bool destructive = false,
  }) {
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Text(
        label,
        style: TextStyle(
          color: destructive ? CupertinoColors.systemRed : _accentColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<ServerAddress> _sortedAddresses() {
    final sorted = List<ServerAddress>.from(_serverAddresses);
    sorted.sort((a, b) {
      if (a.id == _currentAddressId) return -1;
      if (b.id == _currentAddressId) return 1;
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) return priorityCompare;
      return a.name.compareTo(b.name);
    });
    return sorted;
  }

  bool _isPreferredAddress(ServerAddress address) {
    if (_serverAddresses.length <= 1) return false;
    final priorities = _serverAddresses.map((item) => item.priority);
    final minPriority = priorities.reduce((a, b) => a < b ? a : b);
    return address.priority == minPriority;
  }

  Future<void> _handleAddAddress() async {
    final result = await _showAddAddressDialog();
    if (result == null) return;

    try {
      final service = _getService();
      final success = await service.addServerAddress(
        result.url,
        result.name,
      );
      if (!mounted) return;
      if (success) {
        setState(_loadAddressInfo);
        AdaptiveSnackBar.show(
          context,
          message: '地址添加成功',
          type: AdaptiveSnackBarType.success,
        );
      } else {
        AdaptiveSnackBar.show(
          context,
          message: '添加地址失败',
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '添加地址失败: ${_cleanErrorMessage(e)}',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<({String url, String name})?> _showAddAddressDialog() async {
    final urlController = TextEditingController();
    final nameController = TextEditingController();

    final result = await showCupertinoDialog<({String url, String name})>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('添加服务器地址'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              CupertinoTextField(
                controller: urlController,
                placeholder: 'http://192.168.1.100:8096',
                keyboardType: TextInputType.url,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: 10),
              CupertinoTextField(
                controller: nameController,
                placeholder: '地址名称（可留空）',
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final url = urlController.text.trim();
              if (url.isEmpty) return;
              Navigator.of(ctx).pop((
                url: url,
                name: nameController.text.trim(),
              ));
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );

    urlController.dispose();
    nameController.dispose();
    return result;
  }

  Future<void> _confirmRemoveAddress(ServerAddress address) async {
    if (_serverAddresses.length <= 1) {
      AdaptiveSnackBar.show(context, message: '至少需要保留一个地址');
      return;
    }

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('删除地址'),
        content: Text('确定要删除地址「${address.name}」吗？\n${address.url}'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final service = _getService();
      final success = await service.removeServerAddress(address.id);
      if (!mounted) return;
      if (success) {
        setState(_loadAddressInfo);
        AdaptiveSnackBar.show(
          context,
          message: '地址已删除',
          type: AdaptiveSnackBarType.success,
        );
      } else {
        AdaptiveSnackBar.show(
          context,
          message: '删除地址失败',
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '删除地址失败: ${_cleanErrorMessage(e)}',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _handleSwitchAddress(ServerAddress address) async {
    try {
      final service = _getService();
      final success = await service.switchToAddress(address.id);
      if (!mounted) return;
      if (success) {
        setState(_loadAddressInfo);
        AdaptiveSnackBar.show(
          context,
          message: '已切换到新地址',
          type: AdaptiveSnackBarType.success,
        );
      } else {
        AdaptiveSnackBar.show(
          context,
          message: '切换地址失败，请检查连接',
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '切换地址失败: ${_cleanErrorMessage(e)}',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showPriorityDialog(ServerAddress address) async {
    final controller = TextEditingController(text: '${address.priority}');

    final value = await showCupertinoDialog<int>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('设置优先级'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            keyboardType: TextInputType.number,
            placeholder: '数字越小优先级越高',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final priority = int.tryParse(controller.text.trim());
              if (priority == null || priority < 0) return;
              Navigator.of(ctx).pop(priority);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (value == null || value == address.priority) return;

    try {
      final service = _getService();
      final success = await service.updateServerPriority(address.id, value);
      if (!mounted) return;
      if (success) {
        setState(_loadAddressInfo);
        AdaptiveSnackBar.show(
          context,
          message: '优先级已更新',
          type: AdaptiveSnackBarType.success,
        );
      } else {
        AdaptiveSnackBar.show(
          context,
          message: '更新优先级失败',
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '更新优先级失败: ${_cleanErrorMessage(e)}',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String _cleanErrorMessage(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Widget _buildTranscodeSection() {
    final l10n = context.l10n;
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
                        l10n.transcodeSettings,
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
                        l10n.currentDefaultQuality(
                          _selectedQuality.displayName,
                        ),
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
                          l10n.enableTranscode,
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
                      l10n.defaultQuality,
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
                                ? CupertinoColors.systemOrange
                                    .withValues(alpha: 0.1)
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

  String _getLibraryTypeLabel(BuildContext context, String? type) {
    final l10n = context.l10n;
    switch (type) {
      case 'tvshows':
        return l10n.tvShowsLibrary;
      case 'movies':
        return l10n.moviesLibrary;
      case 'boxsets':
        return l10n.boxsetsLibrary;
      case 'folders':
        return l10n.folderLibrary;
      case 'mixed':
        return l10n.mixedLibrary;
      default:
        return l10n.mediaLibrary;
    }
  }
}
