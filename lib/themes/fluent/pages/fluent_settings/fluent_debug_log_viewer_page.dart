import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:provider/provider.dart';

class FluentDebugLogViewerPage extends StatefulWidget {
  const FluentDebugLogViewerPage({super.key});

  @override
  State<FluentDebugLogViewerPage> createState() => _FluentDebugLogViewerPageState();
}

class _FluentDebugLogViewerPageState extends State<FluentDebugLogViewerPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _showTimestamp = true;
  bool _autoScroll = false;
  String _selectedLevel = '全部';
  String _selectedTag = '全部';
  String _searchQuery = '';
  List<String> _availableTags = ['全部'];
  final List<String> _logLevels = ['全部', 'DEBUG', 'INFO', 'WARN', 'ERROR'];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _updateAvailableTags();
    _loadSettings();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  Future<void> _loadSettings() async {
    final showTimestamp =
        await SettingsStorage.loadBool('debug_log_show_timestamp', defaultValue: true);
    final autoScroll =
        await SettingsStorage.loadBool('debug_log_auto_scroll', defaultValue: false);
    if (!mounted) return;
    setState(() {
      _showTimestamp = showTimestamp;
      _autoScroll = autoScroll;
    });
  }

  void _updateAvailableTags() {
    final logService = DebugLogService();
    final tags = logService.logEntries.map((entry) => entry.tag).toSet().toList()..sort();
    if (!mounted) return;
    setState(() {
      _availableTags = ['全部', ...tags];
      if (!_availableTags.contains(_selectedTag)) {
        _selectedTag = '全部';
      }
    });
  }

  List<LogEntry> _filteredLogs() {
    final logService = DebugLogService();
    var logs = logService.logEntries;

    if (_selectedLevel != '全部') {
      logs = logs.where((entry) => entry.level == _selectedLevel).toList();
    }
    if (_selectedTag != '全部') {
      logs = logs.where((entry) => entry.tag == _selectedTag).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      logs = logs.where((entry) => entry.message.toLowerCase().contains(query)).toList();
    }
    return logs;
  }

  Color _levelColor(String level) {
    switch (level) {
      case 'ERROR':
        return const Color(0xFFD13438);
      case 'WARN':
        return const Color(0xFFFDD835);
      case 'INFO':
        return const Color(0xFF00BCF2);
      case 'DEBUG':
      default:
        return const Color(0xFF8A8A8A);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _copyLogEntry(LogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
    if (!mounted) return;
    _showInfoBar('日志已复制');
  }

  Future<void> _copyAllLogs() async {
    final logs = DebugLogService().logEntries;
    if (logs.isEmpty) {
      _showInfoBar('没有可复制的日志', severity: InfoBarSeverity.warning);
      return;
    }
    final buffer = StringBuffer();
    for (final entry in logs) {
      buffer.writeln(entry.toFormattedString());
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    _showInfoBar('所有日志已复制');
  }

  void _clearLogs() {
    DebugLogService().clearLogs();
    _showInfoBar('日志已清空');
  }

  void _toggleCollection(DebugLogService logService) {
    if (logService.isCollecting) {
      logService.stopCollecting();
      _showInfoBar('日志收集已停止', severity: InfoBarSeverity.warning);
    } else {
      logService.startCollecting();
      _showInfoBar('日志收集已启动', severity: InfoBarSeverity.success);
    }
  }

  void _showInfoBar(String message, {InfoBarSeverity severity = InfoBarSeverity.info}) {
    if (!mounted) return;
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: Text(_infoTitle(severity)),
          content: Text(message),
          severity: severity,
          action: IconButton(
            icon: const Icon(FluentIcons.clear),
            onPressed: close,
          ),
        );
      },
    );
  }

  String _infoTitle(InfoBarSeverity severity) {
    switch (severity) {
      case InfoBarSeverity.success:
        return '成功';
      case InfoBarSeverity.warning:
        return '警告';
      case InfoBarSeverity.error:
        return '错误';
      case InfoBarSeverity.info:
      default:
        return '提示';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: DebugLogService(),
      child: NavigationView(
        appBar: const NavigationAppBar(
          automaticallyImplyLeading: true,
          title: Text('终端输出'),
        ),
        content: ScaffoldPage(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildToolbar(context),
              const SizedBox(height: 8),
              _buildStatusBar(),
              const SizedBox(height: 12),
              Expanded(
                child: _buildLogList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextBox(
          controller: _searchController,
          placeholder: '搜索日志内容...',
          prefix: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(FluentIcons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 200,
              child: InfoLabel(
                label: '级别过滤',
                child: ComboBox<String>(
                  value: _selectedLevel,
                  items: _logLevels
                      .map(
                        (level) => ComboBoxItem<String>(
                          value: level,
                          child: Text(level),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedLevel = value);
                  },
                ),
              ),
            ),
            SizedBox(
              width: 200,
              child: InfoLabel(
                label: '标签过滤',
                child: ComboBox<String>(
                  value: _selectedTag,
                  items: _availableTags
                      .map(
                        (tag) => ComboBoxItem<String>(
                          value: tag,
                          child: Text(tag),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedTag = value);
                  },
                ),
              ),
            ),
            InfoLabel(
              label: '显示时间戳',
              child: ToggleSwitch(
                checked: _showTimestamp,
                onChanged: (value) {
                  setState(() => _showTimestamp = value);
                  SettingsStorage.saveBool('debug_log_show_timestamp', value);
                },
              ),
            ),
            InfoLabel(
              label: '自动滚动',
              child: ToggleSwitch(
                checked: _autoScroll,
                onChanged: (value) {
                  setState(() => _autoScroll = value);
                  SettingsStorage.saveBool('debug_log_auto_scroll', value);
                },
              ),
            ),
            Consumer<DebugLogService>(
              builder: (context, logService, child) {
                return CommandBar(
                  mainAxisAlignment: MainAxisAlignment.start,
                  primaryItems: [
                    CommandBarButton(
                      icon: Icon(logService.isCollecting ? FluentIcons.pause : FluentIcons.play),
                      label: Text(logService.isCollecting ? '停止收集' : '开始收集'),
                      onPressed: () => _toggleCollection(logService),
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.clear),
                      label: const Text('清空日志'),
                      onPressed: _clearLogs,
                    ),
                    CommandBarButton(
                      icon: const Icon(FluentIcons.copy),
                      label: const Text('复制全部'),
                      onPressed: _copyAllLogs,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBar() {
    return Consumer<DebugLogService>(
      builder: (context, logService, child) {
        final filteredLogs = _filteredLogs();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateAvailableTags();
          if (_autoScroll && filteredLogs.isNotEmpty) {
            _scrollToBottom();
          }
        });
        return Container(
          decoration: BoxDecoration(
            color: FluentTheme.of(context).cardColor.withOpacity(0.7),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                logService.isCollecting ? FluentIcons.record2 : FluentIcons.stop,
                color: logService.isCollecting ? Colors.green : Colors.red,
                size: 14,
              ),
              const SizedBox(width: 8),
              Text(
                logService.isCollecting ? '正在收集日志' : '日志收集已停止',
                style: const TextStyle(fontSize: 12),
              ),
              const Spacer(),
              Text(
                '显示 ${filteredLogs.length}/${logService.logCount} 条',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogList() {
    return Consumer<DebugLogService>(
      builder: (context, logService, child) {
        final logs = _filteredLogs();
        if (logs.isEmpty) {
          return const Center(
            child: Text('暂无日志', style: TextStyle(fontSize: 16)),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          itemCount: logs.length,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) {
            final entry = logs[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: GestureDetector(
                onTap: () => _copyLogEntry(entry),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FluentTheme.of(context).micaBackgroundColor.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildLogEntry(entry),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLogEntry(LogEntry entry) {
    final timestamp = '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (_showTimestamp)
              Text(
                timestamp,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8A8A8A),
                ),
              ),
            if (_showTimestamp) const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _levelColor(entry.level),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.level,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.tag,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const Spacer(),
            const Text(
              '点击复制',
              style: TextStyle(fontSize: 10, color: Color(0xFF8A8A8A)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          entry.message,
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}
