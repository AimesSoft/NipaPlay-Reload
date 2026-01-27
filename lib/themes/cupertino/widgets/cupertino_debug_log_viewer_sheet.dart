import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/log_share_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoDebugLogViewerSheet extends StatefulWidget {
  const CupertinoDebugLogViewerSheet({super.key});

  @override
  State<CupertinoDebugLogViewerSheet> createState() =>
      _CupertinoDebugLogViewerSheetState();
}

class _CupertinoDebugLogViewerSheetState
    extends State<CupertinoDebugLogViewerSheet> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final List<String> _logLevels = const ['全部', 'DEBUG', 'INFO', 'WARN', 'ERROR'];
  List<String> _availableTags = const ['全部'];

  late final DebugLogService _logService;

  double _scrollOffset = 0;
  String _selectedLevel = '全部';
  String _selectedTag = '全部';
  String _searchQuery = '';
  bool _showTimestamp = true;
  bool _autoScroll = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _logService = DebugLogService();
    _logService.addListener(_handleLogsUpdated);
    _searchController.addListener(_handleSearchChanged);
    _scrollController.addListener(_handleScroll);
    _syncAvailableTags();
    _loadPreferences();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _logService.removeListener(_handleLogsUpdated);
    super.dispose();
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  void _handleSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _handleLogsUpdated() {
    if (!mounted) return;
    setState(() {
      _syncAvailableTags();
    });
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  Future<void> _loadPreferences() async {
    final showTimestamp = await SettingsStorage.loadBool(
      'debug_log_show_timestamp',
      defaultValue: true,
    );
    final autoScroll = await SettingsStorage.loadBool(
      'debug_log_auto_scroll',
      defaultValue: false,
    );
    if (!mounted) return;
    setState(() {
      _showTimestamp = showTimestamp;
      _autoScroll = autoScroll;
    });
  }

  void _syncAvailableTags() {
    final tags = _logService.logEntries
        .map((entry) => entry.tag)
        .toSet()
        .toList()
      ..sort();
    final newList = ['全部', ...tags];
    _availableTags = newList;
    if (!_availableTags.contains(_selectedTag)) {
      _selectedTag = '全部';
    }
  }

  List<LogEntry> _filteredLogs() {
    Iterable<LogEntry> logs = _logService.logEntries;
    if (_selectedLevel != '全部') {
      logs = logs.where((entry) => entry.level == _selectedLevel);
    }
    if (_selectedTag != '全部') {
      logs = logs.where((entry) => entry.tag == _selectedTag);
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      logs = logs.where((entry) => entry.message.toLowerCase().contains(query));
    }
    return logs.toList();
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      position,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _pickLevel() async {
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择日志级别'),
        actions: _logLevels
            .map(
              (level) => CupertinoActionSheetAction(
                isDefaultAction: level == _selectedLevel,
                onPressed: () => Navigator.of(context).pop(level),
                child: Text(level),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedLevel = result;
      });
    }
  }

  Future<void> _pickTag() async {
    final result = await showCupertinoModalPopup<String>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择日志标签'),
        actions: _availableTags
            .map(
              (tag) => CupertinoActionSheetAction(
                isDefaultAction: tag == _selectedTag,
                onPressed: () => Navigator.of(context).pop(tag),
                child: Text(tag),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedTag = result;
      });
    }
  }

  Future<void> _copyLogEntry(LogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: '该条日志已复制',
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _copyAllLogs() async {
    final logs = _logService.logEntries;
    if (logs.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: '当前没有可复制的日志',
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }
    final buffer = StringBuffer();
    for (final entry in logs) {
      buffer.writeln(entry.toFormattedString());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: '所有日志已复制到剪贴板',
      type: AdaptiveSnackBarType.success,
    );
  }

  void _clearLogs() {
    _logService.clearLogs();
    AdaptiveSnackBar.show(
      context,
      message: '日志已清空',
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _showQRCode() async {
    if (_isUploading) return;
    setState(() {
      _isUploading = true;
    });
    try {
      final url = await LogShareService.uploadLogs();
      if (!mounted) return;
      await CupertinoBottomSheet.show(
        context: context,
        title: '扫描二维码查看日志',
        floatingTitle: true,
        child: _CupertinoLogQrSheet(url: url),
      );
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: '生成二维码失败: $e',
          type: AdaptiveSnackBarType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  void _toggleTimestamp(bool value) {
    setState(() {
      _showTimestamp = value;
    });
    SettingsStorage.saveBool('debug_log_show_timestamp', value);
  }

  void _toggleAutoScroll(bool value) {
    setState(() {
      _autoScroll = value;
    });
    SettingsStorage.saveBool('debug_log_auto_scroll', value);
  }

  @override
  Widget build(BuildContext context) {
    final double titleOpacity = (1.0 - (_scrollOffset / 18.0)).clamp(0.0, 1.0);

    return CupertinoBottomSheetContentLayout(
      controller: _scrollController,
      floatingTitleOpacity: titleOpacity,
      sliversBuilder: (context, topSpacing) {
        final logs = _filteredLogs();
        return [
          SliverToBoxAdapter(
            child: _buildControlCard(context, topSpacing),
          ),
          SliverToBoxAdapter(
            child: _buildStatusRow(context),
          ),
          if (logs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  '尚未收集到日志，尝试执行一些操作后再试。',
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.secondaryLabel,
                      context,
                    ),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final entry = logs[index];
                  return _buildLogEntry(context, entry);
                },
                childCount: logs.length,
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
        ];
      },
    );
  }

  Widget _buildControlCard(BuildContext context, double topSpacing) {
    final Color cardColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              CupertinoSearchTextField(
                controller: _searchController,
                placeholder: '搜索日志内容...',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildFilterButton(
                    context,
                    icon: CupertinoIcons.line_horizontal_3_decrease,
                    label: '级别',
                    value: _selectedLevel,
                    onTap: _pickLevel,
                  ),
                  _buildFilterButton(
                    context,
                    icon: CupertinoIcons.tag,
                    label: '标签',
                    value: _selectedTag,
                    onTap: _pickTag,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildToggleRow(
                      context,
                      label: '显示时间戳',
                      value: _showTimestamp,
                      onChanged: _toggleTimestamp,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildToggleRow(
                      context,
                      label: '自动滚动',
                      value: _autoScroll,
                      onChanged: _toggleAutoScroll,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildPrimaryActionButton(
                    context,
                    icon: CupertinoIcons.doc_on_doc,
                    label: '复制全部',
                    onPressed: _copyAllLogs,
                  ),
                  _buildSecondaryActionButton(
                    context,
                    icon: CupertinoIcons.qrcode,
                    label: '生成二维码',
                    loading: _isUploading,
                    onPressed: _showQRCode,
                  ),
                  _buildDestructiveActionButton(
                    context,
                    icon: CupertinoIcons.delete,
                    label: '清空日志',
                    onPressed: _clearLogs,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context) {
    final Color textColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final logs = _filteredLogs();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '显示 ${logs.length} 条 / 共 ${_logService.logCount} 条',
            style: TextStyle(fontSize: 13, color: textColor),
          ),
          Text(
            _logService.isCollecting ? '收集中' : '已暂停',
            style: TextStyle(
              fontSize: 13,
              color: _logService.isCollecting
                  ? CupertinoDynamicColor.resolve(
                      CupertinoColors.activeBlue,
                      context,
                    )
                  : CupertinoDynamicColor.resolve(
                      CupertinoColors.systemGrey2,
                      context,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry(BuildContext context, LogEntry entry) {
    final Color background = CupertinoDynamicColor.resolve(
      CupertinoColors.systemBackground,
      context,
    );
    final Color secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: CupertinoColors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_showTimestamp)
                    Text(
                      _formatTimestamp(entry.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        color: secondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  if (_showTimestamp) const SizedBox(width: 8),
                  _buildLevelBadge(entry.level),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.tag,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ),
                  CupertinoButton(
                    padding: const EdgeInsets.all(4),
                    minSize: 28,
                    onPressed: () => _copyLogEntry(entry),
                    child: const Icon(
                      CupertinoIcons.doc_on_doc,
                      size: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.message,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLevelBadge(String level) {
    final Color color;
    switch (level) {
      case 'ERROR':
        color = CupertinoColors.systemRed;
        break;
      case 'WARN':
        color = CupertinoColors.systemOrange;
        break;
      case 'INFO':
        color = CupertinoColors.activeBlue;
        break;
      default:
        color = CupertinoColors.systemGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        level,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildFilterButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final Color borderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );
    final Color textColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              '$label：$value',
              style: TextStyle(fontSize: 13, color: textColor),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_down,
              size: 12,
              color: textColor.withOpacity(0.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final Color textColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemFill,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: textColor),
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 38,
      child: CupertinoButton.filled(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool loading = false,
  }) {
    final Color background = CupertinoDynamicColor.resolve(
      CupertinoColors.quaternarySystemFill,
      context,
    );
    final Color textColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    return SizedBox(
      height: 38,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: background,
        onPressed: loading ? null : onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CupertinoActivityIndicator(radius: 7)
            else
              Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              loading ? '生成中...' : label,
              style: TextStyle(color: textColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestructiveActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 38,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: CupertinoColors.systemRed.withOpacity(0.12),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: CupertinoColors.systemRed),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: CupertinoColors.systemRed),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
}

class _CupertinoLogQrSheet extends StatelessWidget {
  const _CupertinoLogQrSheet({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverToBoxAdapter(
          child: SafeArea(
            top: false,
            bottom: true,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 32),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: CupertinoColors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: QrImageView(
                      data: url,
                      version: QrVersions.auto,
                      size: 220,
                      backgroundColor: CupertinoColors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '日志链接将在 1 小时后失效，请尽快扫描或分享。',
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.secondaryLabel,
                        context,
                      ),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  CupertinoButton.filled(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: url));
                      AdaptiveSnackBar.show(
                        context,
                        message: '链接已复制',
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                    child: const SizedBox(
                      width: double.infinity,
                      child: Center(child: Text('复制链接')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
