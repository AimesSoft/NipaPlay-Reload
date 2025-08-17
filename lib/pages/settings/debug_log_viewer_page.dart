import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/services/log_share_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// 调试日志查看器页面
/// 提供日志查看、搜索、过滤和导出功能
class DebugLogViewerPage extends StatefulWidget {
  const DebugLogViewerPage({super.key});

  @override
  State<DebugLogViewerPage> createState() => _DebugLogViewerPageState();
}

class _DebugLogViewerPageState extends State<DebugLogViewerPage> with TickerProviderStateMixin {
  late ScrollController _scrollController;
  late TextEditingController _searchController;
  late GlobalKey<State> _levelDropdownKey;
  late GlobalKey<State> _tagDropdownKey;

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
    _scrollController = ScrollController();
    _searchController = TextEditingController();
    _levelDropdownKey = GlobalKey();
    _tagDropdownKey = GlobalKey();
    _searchController.addListener(_onSearchChanged);
    
    // 获取可用的标签
    _updateAvailableTags();
    
    // 加载保存的设置
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  // 加载保存的设置
  Future<void> _loadSettings() async {
    final showTimestamp = await SettingsStorage.loadBool('debug_log_show_timestamp', defaultValue: true);
    final autoScroll = await SettingsStorage.loadBool('debug_log_auto_scroll', defaultValue: false);
    
    if (mounted) {
      setState(() {
        _showTimestamp = showTimestamp;
        _autoScroll = autoScroll;
      });
    }
  }

  void _updateAvailableTags() {
    final logService = DebugLogService();
    final tags = logService.logEntries
        .map((entry) => entry.tag)
        .toSet()
        .toList();
    tags.sort();
    
    setState(() {
      _availableTags = ['全部', ...tags];
      if (!_availableTags.contains(_selectedTag)) {
        _selectedTag = '全部';
      }
    });
  }

  List<LogEntry> _getFilteredLogs() {
    final logService = DebugLogService();
    var logs = logService.logEntries;

    // 按级别过滤
    if (_selectedLevel != '全部') {
      logs = logs.where((log) => log.level == _selectedLevel).toList();
    }

    // 按标签过滤
    if (_selectedTag != '全部') {
      logs = logs.where((log) => log.tag == _selectedTag).toList();
    }

    // 按搜索关键词过滤
    if (_searchQuery.isNotEmpty) {
      logs = logs.where((log) => 
          log.message.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    return logs;
  }

  Color _getLevelColor(String level) {
    switch (level) {
      case 'ERROR':
        return Colors.red;
      case 'WARN':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      case 'DEBUG':
      default:
        return Colors.grey;
    }
  }

  /// 构建日志条目内容，支持不同设备的布局
  Widget _buildLogEntryContent(LogEntry entry) {
    // 检查是否为手机设备
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.width < screenSize.height ? screenSize.width : screenSize.height;
    final bool isRealPhone = globals.isPhone && shortestSide < 600;

    if (isRealPhone) {
      // 手机设备：垂直布局，时间-info-标签分三排显示在左侧
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：时间戳
          if (_showTimestamp)
            Text(
              '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
              '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
              '${entry.timestamp.second.toString().padLeft(2, '0')}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          
          if (_showTimestamp) const SizedBox(height: 4),
          
          // 第二行：级别标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getLevelColor(entry.level),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.level,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(height: 4),
          
          // 第三行：标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.tag,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // 第四行：消息内容
          Text(
            entry.message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
    } else {
      // 非手机设备：保持原有的水平布局
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间戳
          if (_showTimestamp)
            SizedBox(
              width: 80,
              child: Text(
                '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
                '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
                '${entry.timestamp.second.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          
          if (_showTimestamp) const SizedBox(width: 8),
          
          // 级别标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getLevelColor(entry.level),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.level,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 标签
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.tag,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 消息内容
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _clearLogs() {
    BlurDialog.show(
      context: context,
      title: '确认清空',
      content: '确定要清空所有日志吗？此操作无法撤销。',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            DebugLogService().clearLogs();
            BlurSnackBar.show(context, '日志已清空');
          },
          child: const Text('确认', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }

  void _exportLogs() {
    final logService = DebugLogService();
    final exportText = logService.exportLogs();
    
    Clipboard.setData(ClipboardData(text: exportText));
    BlurSnackBar.show(context, '日志已复制到剪贴板');
  }

  Future<void> _exportLogsToFile() async {
    try {
      final logService = DebugLogService();
      final exportText = logService.exportLogs();
      
      // 生成文件名：NipaPlay_YYYY-MM-DD_HH-mm-ss.txt
      final now = DateTime.now();
      final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
      final fileName = 'NipaPlay_${formatter.format(now)}.txt';
      
      // 使用file_selector弹出保存对话框
      final savePath = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '文本文件',
            extensions: ['txt'],
          ),
        ],
      );
      
      if (savePath != null) {
        // 写入文件
        final file = File(savePath.path);
        await file.writeAsString(exportText, encoding: utf8);
        
        if (mounted) {
          BlurSnackBar.show(context, '日志已导出到: ${savePath.path}');
        }
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '导出失败: $e');
      }
    }
  }

  void _copyLogEntry(LogEntry entry) {
    Clipboard.setData(ClipboardData(text: entry.toFormattedString()));
    BlurSnackBar.show(context, '日志条目已复制');
  }

  void _showLogStatistics() {
    final logService = DebugLogService();
    final stats = logService.getLogStatistics();
    
    final contentBuffer = StringBuffer();
    contentBuffer.writeln('总计: ${stats['total'] ?? 0} 条\n');
    
    final levelStats = stats.entries
        .where((entry) => entry.key.startsWith('level_'))
        .map((entry) => '${entry.key.substring(6)}: ${entry.value} 条')
        .join('\n');
    
    contentBuffer.write(levelStats);
    
    BlurDialog.show(
      context: context,
      title: '日志统计',
      content: contentBuffer.toString(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  // 显示更多选项对话框
  void _showMoreOptions(BuildContext context) {
    final navigatorState = Navigator.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: GlassmorphicContainer(
          width: double.infinity,
          height: double.infinity,
          borderRadius: 20,
          blur: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 20 : 0,
          alignment: Alignment.center,
          border: 1,
          linearGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.3),
              Colors.white.withOpacity(0.25),
            ],
          ),
          borderGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withOpacity(0.5),
              Colors.white.withOpacity(0.5),
            ],
          ),
          child: Column(
            children: [
              // 拖拽条
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // 标题
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '终端输出选项',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              
              // 选项列表
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 显示时间戳开关
                      _buildOptionItem(
                        icon: Icons.access_time,
                        title: '显示时间戳',
                        isSwitch: true,
                        switchValue: _showTimestamp,
                        onSwitchChanged: (value) {
                          setState(() {
                            _showTimestamp = value;
                          });
                          SettingsStorage.saveBool('debug_log_show_timestamp', value);
                          Navigator.pop(context);
                        },
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // 自动滚动开关
                      _buildOptionItem(
                        icon: Icons.auto_awesome,
                        title: '自动滚动',
                        isSwitch: true,
                        switchValue: _autoScroll,
                        onSwitchChanged: (value) {
                          setState(() {
                            _autoScroll = value;
                          });
                          SettingsStorage.saveBool('debug_log_auto_scroll', value);
                          Navigator.pop(context);
                        },
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // 分隔线
                      Divider(color: Colors.white.withOpacity(0.3)),
                      
                      const SizedBox(height: 12),
                      
                      // 统计信息
                      _buildOptionItem(
                        icon: Icons.bar_chart,
                        title: '统计信息',
                        onTap: () {
                          Navigator.pop(context);
                          _showLogStatistics();
                        },
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // 导出全部
                      _buildOptionItem(
                        icon: Icons.copy_all,
                        title: Platform.isWindows || Platform.isMacOS || Platform.isLinux 
                            ? '导出到文件' 
                            : '导出全部',
                        onTap: () {
                          Navigator.pop(context);
                          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
                            _exportLogsToFile();
                          } else {
                            _exportLogs();
                          }
                        },
                      ),
                      
                      // PC端额外显示复制到剪贴板选项
                      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) ...[
                        const SizedBox(height: 12),
                        _buildOptionItem(
                          icon: Icons.content_copy,
                          title: '复制到剪贴板',
                          onTap: () {
                            Navigator.pop(context);
                            _exportLogs();
                          },
                        ),
                      ],
                      
                      const SizedBox(height: 12),
                      
                      // 分享二维码选项
                      _buildOptionItem(
                        icon: Icons.qr_code,
                        title: '分享二维码',
                        onTap: () {
                          Navigator.pop(context);
                          Future.microtask(() {
                            if (mounted) {
                              _showQRCode();
                            }
                          });
                        },
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // 清空日志
                      _buildOptionItem(
                        icon: Icons.clear_all,
                        title: '清空日志',
                        iconColor: Colors.red,
                        textColor: Colors.red,
                        onTap: () {
                          Navigator.pop(context);
                          _clearLogs();
                        },
                      ),
                      
                      // 添加底部边距，确保最后一项可以完全显示
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    Color? iconColor,
    Color? textColor,
    bool isSwitch = false,
    bool? switchValue,
    Function(bool)? onSwitchChanged,
    VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.2),
            Colors.white.withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isSwitch ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: iconColor ?? Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textColor ?? Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (isSwitch)
                  Switch(
                    value: switchValue ?? false,
                    onChanged: onSwitchChanged,
                    activeColor: Colors.white,
                    inactiveThumbColor: Colors.white70,
                  )
                else
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 显示二维码对话框
  Future<void> _showQRCode() async {
    if (!mounted) return;
    debugPrint('[QRCode] 开始生成二维码...');

    try {
      debugPrint('[QRCode] 开始上传日志');
      // 上传日志并获取URL
      final url = await LogShareService.uploadLogs();
      debugPrint('[QRCode] 获取到URL: $url');
      
      if (!mounted) return;

      debugPrint('[QRCode] 显示二维码对话框');
      await BlurDialog.show(
        context: context,
        title: '扫描二维码查看日志',
        contentWidget: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: url,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '日志将在1小时后自动删除',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              if (mounted) {
                BlurSnackBar.show(context, '链接已复制到剪贴板');
              }
            },
            child: const Text('复制链接'),
          ),
        ],
      );
      debugPrint('[QRCode] 二维码对话框显示完成');
    } catch (e) {
      debugPrint('[QRCode] 发生错误: $e');
      if (!mounted) return;
      
      BlurSnackBar.show(context, '生成二维码失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: DebugLogService(),
      child: Column(
        children: [
          // 工具栏
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 搜索框
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: '搜索日志内容...',
                    hintStyle: TextStyle(color: Colors.white54),
                    prefixIcon: Icon(Icons.search, color: Colors.white54),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                
                // 过滤器和控制按钮
                Row(
                  children: [
                    // 级别过滤
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '级别: ',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          Consumer<DebugLogService>(
                            builder: (context, logService, child) {
                              return BlurDropdown<String>(
                                dropdownKey: _levelDropdownKey,
                                items: _logLevels.map((level) => DropdownMenuItemData(
                                  title: level,
                                  value: level,
                                  isSelected: _selectedLevel == level,
                                )).toList(),
                                onItemSelected: (level) {
                                  setState(() {
                                    _selectedLevel = level;
                                  });
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // 标签过滤
                    Expanded(
                      child: Row(
                        children: [
                          const Text(
                            '标签: ',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          Consumer<DebugLogService>(
                            builder: (context, logService, child) {
                              // 更新可用标签
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _updateAvailableTags();
                              });
                              
                              return BlurDropdown<String>(
                                dropdownKey: _tagDropdownKey,
                                items: _availableTags.map((tag) => DropdownMenuItemData(
                                  title: tag,
                                  value: tag,
                                  isSelected: _selectedTag == tag,
                                )).toList(),
                                onItemSelected: (tag) {
                                  setState(() {
                                    _selectedTag = tag;
                                  });
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(width: 16),
                    
                    // 选项按钮
                    IconButton(
                      onPressed: () => _showMoreOptions(context),
                      icon: const Icon(Ionicons.ellipsis_vertical, color: Colors.white),
                      //tooltip: '更多选项',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 日志状态栏 - 使用Consumer监听状态
          Consumer<DebugLogService>(
            builder: (context, logService, child) {
              final filteredLogs = _getFilteredLogs();
              
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.black26,
                child: Row(
                  children: [
                    Icon(
                      logService.isCollecting ? Icons.fiber_manual_record : Icons.stop,
                      color: logService.isCollecting ? Colors.green : Colors.red,
                      size: 12,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      logService.isCollecting ? '正在收集日志' : '日志收集已停止',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '显示 ${filteredLogs.length}/${logService.logCount} 条',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),

          // 日志列表 - 使用Consumer监听内容变化
          Expanded(
            child: Consumer<DebugLogService>(
              builder: (context, logService, child) {
                final filteredLogs = _getFilteredLogs();
                
                // 自动滚动到底部
                if (_autoScroll && filteredLogs.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToBottom();
                  });
                }
                
                return filteredLogs.isEmpty
                    ? const Center(
                        child: Text(
                          '暂无日志',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: filteredLogs.length,
                        itemBuilder: (context, index) {
                          final entry = filteredLogs[index];
                          
                          return InkWell(
                            onTap: () => _copyLogEntry(entry),
                            onLongPress: () {
                              // 显示详细信息
                              final detailsContent = '时间: ${entry.timestamp}\n'
                                  '级别: ${entry.level}\n'
                                  '标签: ${entry.tag}\n'
                                  '内容: ${entry.message}';
                              
                              BlurDialog.show(
                                context: context,
                                title: '日志详细信息',
                                content: detailsContent,
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('关闭', style: TextStyle(color: Colors.white)),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      _copyLogEntry(entry);
                                    },
                                    child: const Text('复制', style: TextStyle(color: Colors.white)),
                                  ),
                                ],
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Colors.white.withOpacity(0.1),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: _buildLogEntryContent(entry),
                            ),
                          );
                        },
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
} 