import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/services/remote_control_client_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoRemoteControllerSettingsPage extends StatefulWidget {
  const CupertinoRemoteControllerSettingsPage({super.key});

  @override
  State<CupertinoRemoteControllerSettingsPage> createState() =>
      _CupertinoRemoteControllerSettingsPageState();
}

class _CupertinoRemoteControllerSettingsPageState
    extends State<CupertinoRemoteControllerSettingsPage> {
  bool _isScanning = false;
  bool _isLoadingState = false;
  String? _matchedBaseUrl;
  String? _matchedHostname;
  Map<String, dynamic>? _remoteState;

  @override
  void initState() {
    super.initState();
    _loadSavedTarget();
  }

  Future<void> _loadSavedTarget() async {
    final baseUrl = await RemoteControlSettings.getMatchedBaseUrl();
    final hostname = await RemoteControlSettings.getMatchedHostname();
    if (!mounted) return;
    setState(() {
      _matchedBaseUrl = baseUrl;
      _matchedHostname = hostname;
    });
    if (baseUrl != null) {
      await _refreshRemoteState();
    } else {
      await _scanAndMatch();
    }
  }

  Future<void> _scanAndMatch() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
    });
    try {
      final matched = await RemoteControlClientService.autoMatchDevice();
      if (!mounted) return;
      if (matched == null) {
        AdaptiveSnackBar.show(context, message: '未发现可用被遥控端');
        return;
      }
      setState(() {
        _matchedBaseUrl = matched.baseUrl;
        _matchedHostname = matched.hostname;
      });
      await _refreshRemoteState();
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '已匹配 ${matched.hostname ?? matched.baseUrl}',
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(context, message: '扫描失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _refreshRemoteState() async {
    final baseUrl = _matchedBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty || _isLoadingState) return;
    setState(() {
      _isLoadingState = true;
    });
    try {
      final payload = await RemoteControlClientService.fetchState(baseUrl);
      if (!mounted) return;
      setState(() {
        _remoteState = payload;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingState = false;
        });
      }
    }
  }

  Future<void> _clearMatchedTarget() async {
    await RemoteControlSettings.clearMatchedTarget();
    if (!mounted) return;
    setState(() {
      _matchedBaseUrl = null;
      _matchedHostname = null;
      _remoteState = null;
    });
    AdaptiveSnackBar.show(context, message: '已清除匹配设备');
  }

  Future<void> _openRemotePanel() async {
    final baseUrl = _matchedBaseUrl;
    if (baseUrl == null || baseUrl.isEmpty) {
      await _scanAndMatch();
      if (_matchedBaseUrl == null) return;
    }
    if (!mounted) return;
    await CupertinoBottomSheet.show<void>(
      context: context,
      title: '遥控器',
      floatingTitle: true,
      heightRatio: 0.93,
      child: _RemoteControllerPanel(
        baseUrl: _matchedBaseUrl!,
        hostname: _matchedHostname,
      ),
    );
    await _refreshRemoteState();
  }

  @override
  Widget build(BuildContext context) {
    final secondaryText =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final label = _matchedHostname?.trim().isNotEmpty == true
        ? _matchedHostname!.trim()
        : (_matchedBaseUrl ?? '未匹配');
    final connected = _remoteState != null;
    final receiverEnabled = _remoteState?['receiverEnabled'] == true;

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('遥控器'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.secondarySystemGroupedBackground,
                  context,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '默认会自动扫描局域网并匹配被遥控端。遥控面板中的播放器参数由目标设备实时返回，显示什么就调什么。',
                    style: TextStyle(color: secondaryText, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '当前设备: $label',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    connected
                        ? (receiverEnabled ? '状态: 已连接' : '状态: 对方已关闭被遥控端')
                        : '状态: 未连接',
                    style: TextStyle(
                      color: connected && receiverEnabled
                          ? CupertinoColors.activeGreen
                          : secondaryText,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CupertinoButton.filled(
              onPressed: _isScanning ? null : _scanAndMatch,
              child: _isScanning
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Text('自动扫描并匹配'),
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              onPressed: _isLoadingState ? null : _refreshRemoteState,
              child: const Text('刷新状态'),
            ),
            const SizedBox(height: 8),
            CupertinoButton.filled(
              onPressed: _matchedBaseUrl == null ? null : _openRemotePanel,
              child: const Text('打开遥控器'),
            ),
            const SizedBox(height: 8),
            CupertinoButton(
              onPressed: _matchedBaseUrl == null ? null : _clearMatchedTarget,
              child: const Text('清除匹配设备'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoteControllerPanel extends StatefulWidget {
  const _RemoteControllerPanel({
    required this.baseUrl,
    required this.hostname,
  });

  final String baseUrl;
  final String? hostname;

  @override
  State<_RemoteControllerPanel> createState() => _RemoteControllerPanelState();
}

class _RemoteControllerPanelState extends State<_RemoteControllerPanel> {
  Map<String, dynamic>? _payload;
  bool _isLoading = false;
  bool _isSending = false;
  Timer? _pollTimer;
  final TextEditingController _danmakuController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      _refresh(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _danmakuController.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!mounted || _isLoading) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final payload =
          await RemoteControlClientService.fetchState(widget.baseUrl);
      if (!mounted || payload == null) return;
      setState(() {
        _payload = payload;
      });
    } catch (_) {
      // ignore poll failures
    } finally {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendCommand(
    String command, {
    Map<String, dynamic>? args,
    bool showError = true,
  }) async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
    });
    try {
      final response = await RemoteControlClientService.sendCommand(
        widget.baseUrl,
        command: command,
        args: args,
      );
      final success = response['success'] == true;
      if (success) {
        final payload = response['payload'];
        if (payload is Map<String, dynamic>) {
          setState(() {
            _payload = payload;
          });
        } else {
          await _refresh(silent: true);
        }
      } else if (showError && mounted) {
        AdaptiveSnackBar.show(
          context,
          message: response['message']?.toString() ?? '执行失败',
        );
      }
    } catch (e) {
      if (showError && mounted) {
        AdaptiveSnackBar.show(context, message: '执行失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _sendDanmaku() async {
    final text = _danmakuController.text.trim();
    if (text.isEmpty) return;
    await _sendCommand(
      'send_danmaku',
      args: <String, dynamic>{
        'comment': text,
      },
    );
    if (mounted) {
      _danmakuController.clear();
      AdaptiveSnackBar.show(context, message: '弹幕已发送');
    }
  }

  List<Map<String, dynamic>> get _menus {
    final raw = _payload?['menus'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> get _parameters {
    final raw = _payload?['parameters'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final payload = _payload;
    final snapshot = payload?['snapshot'] as Map<String, dynamic>?;
    final isPaused = snapshot?['isPaused'] == true;
    final title = snapshot?['animeTitle']?.toString();
    final episode = snapshot?['episodeTitle']?.toString();

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        return [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, topSpacing, 16, 8),
            sliver: SliverToBoxAdapter(
              child: _buildHeader(title, episode, isPaused),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildQuickActions(isPaused),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildDanmakuSender(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ..._buildParameterSections(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ];
      },
    );
  }

  Widget _buildHeader(String? animeTitle, String? episodeTitle, bool isPaused) {
    final secondaryText =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final hostLabel = widget.hostname?.trim().isNotEmpty == true
        ? widget.hostname!.trim()
        : widget.baseUrl;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('设备: $hostLabel'),
          const SizedBox(height: 4),
          Text(
            '${animeTitle ?? '未播放'}  ${episodeTitle ?? ''}',
            style: TextStyle(fontWeight: FontWeight.w600, color: secondaryText),
          ),
          const SizedBox(height: 4),
          Text(
            isPaused ? '状态: 暂停' : '状态: 播放中',
            style: TextStyle(color: secondaryText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(bool isPaused) {
    return Row(
      children: [
        Expanded(
          child: CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed:
                _isSending ? null : () => _sendCommand('play_previous_episode'),
            child: const Text('上一话'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed:
                _isSending ? null : () => _sendCommand('toggle_play_pause'),
            child: Text(isPaused ? '播放' : '暂停'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoButton.filled(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed:
                _isSending ? null : () => _sendCommand('play_next_episode'),
            child: const Text('下一话'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: _isSending ? null : () => _sendCommand('skip'),
            child: const Text('跳过'),
          ),
        ),
      ],
    );
  }

  Widget _buildDanmakuSender() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _danmakuController,
              placeholder: '发送弹幕',
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            onPressed: _isSending ? null : _sendDanmaku,
            child: const Text('发送'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildParameterSections() {
    final menus = _menus;
    final params = _parameters;
    if (menus.isEmpty || params.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('暂无可调参数'),
          ),
        ),
      ];
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final param in params) {
      final paneId = param['paneId']?.toString() ?? '';
      grouped.putIfAbsent(paneId, () => <Map<String, dynamic>>[]).add(param);
    }

    final slivers = <Widget>[];
    for (final menu in menus) {
      final paneId = menu['paneId']?.toString() ?? '';
      final title = menu['title']?.toString() ?? paneId;
      final paneParams = grouped[paneId] ?? const <Map<String, dynamic>>[];
      if (paneParams.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
      slivers.add(
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.secondarySystemGroupedBackground,
                context,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: paneParams
                  .map((param) => _buildParameterControl(param))
                  .toList(growable: false),
            ),
          ),
        ),
      );
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 8)));
    }
    return slivers;
  }

  Widget _buildParameterControl(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final type = param['type']?.toString() ?? 'readonly';
    final label = param['label']?.toString() ?? key;
    switch (type) {
      case 'bool':
        final value = param['value'] == true;
        return _parameterRow(
          label: label,
          trailing: CupertinoSwitch(
            value: value,
            onChanged: _isSending
                ? null
                : (next) => _sendCommand(
                      'set_parameter',
                      args: <String, dynamic>{'key': key, 'value': next},
                    ),
          ),
        );
      case 'int':
      case 'double':
        return _buildNumericControl(param, isInteger: type == 'int');
      case 'enum':
      case 'select':
        return _buildSelectControl(param);
      case 'string':
        return _buildStringControl(param);
      case 'string_list':
        return _buildStringListControl(param);
      case 'json':
      case 'readonly':
      default:
        final value = const JsonEncoder.withIndent('  ')
            .convert(param['value'])
            .toString();
        return _parameterRow(
          label: label,
          subtitle: value,
          trailing: CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (mounted) {
                AdaptiveSnackBar.show(context, message: '已复制');
              }
            },
            child: const Text('复制'),
          ),
        );
    }
  }

  Widget _buildNumericControl(
    Map<String, dynamic> param, {
    required bool isInteger,
  }) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final value = (param['value'] as num?)?.toDouble() ?? 0.0;
    final min = (param['min'] as num?)?.toDouble();
    final max = (param['max'] as num?)?.toDouble();
    final step = (param['step'] as num?)?.toDouble() ?? (isInteger ? 1 : 0.1);

    if (min != null && max != null && max > min) {
      final clamped = value.clamp(min, max);
      return Column(
        children: [
          _parameterRow(
            label: label,
            trailing: Text(
                isInteger ? '${clamped.round()}' : clamped.toStringAsFixed(2)),
          ),
          CupertinoSlider(
            value: clamped,
            min: min,
            max: max,
            divisions: isInteger ? (max - min).round() : null,
            onChanged: _isSending
                ? null
                : (next) async {
                    final output = isInteger
                        ? next.round()
                        : ((next / step).round() * step);
                    await _sendCommand(
                      'set_parameter',
                      args: <String, dynamic>{'key': key, 'value': output},
                      showError: false,
                    );
                  },
            onChangeEnd: _isSending
                ? null
                : (next) {
                    final output = isInteger
                        ? next.round()
                        : ((next / step).round() * step);
                    _sendCommand(
                      'set_parameter',
                      args: <String, dynamic>{'key': key, 'value': output},
                    );
                  },
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return _parameterRow(
      label: label,
      subtitle: isInteger ? '${value.round()}' : value.toStringAsFixed(2),
    );
  }

  Widget _buildSelectControl(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final value = param['value'];
    final options = (param['options'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];

    String currentLabel = '$value';
    for (final option in options) {
      if (option['value'] == value) {
        currentLabel = option['label']?.toString() ?? '$value';
        break;
      }
    }

    return _parameterRow(
      label: label,
      subtitle: currentLabel,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _isSending
            ? null
            : () async {
                final selected = await showCupertinoModalPopup<dynamic>(
                  context: context,
                  builder: (ctx) {
                    return CupertinoActionSheet(
                      title: Text(label),
                      actions: options
                          .map(
                            (option) => CupertinoActionSheetAction(
                              onPressed: () =>
                                  Navigator.of(ctx).pop(option['value']),
                              child: Text(
                                option['label']?.toString() ??
                                    option['value']?.toString() ??
                                    'unknown',
                              ),
                            ),
                          )
                          .toList(growable: false),
                      cancelButton: CupertinoActionSheetAction(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('取消'),
                      ),
                    );
                  },
                );
                if (selected == null) return;
                await _sendCommand(
                  'set_parameter',
                  args: <String, dynamic>{'key': key, 'value': selected},
                );
              },
        child: const Text('修改'),
      ),
    );
  }

  Widget _buildStringControl(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final value = param['value']?.toString() ?? '';
    return _parameterRow(
      label: label,
      subtitle: value,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _isSending
            ? null
            : () async {
                final edited = await _showTextInputDialog(
                  title: label,
                  initialValue: value,
                  maxLines: 1,
                );
                if (edited == null) return;
                await _sendCommand(
                  'set_parameter',
                  args: <String, dynamic>{'key': key, 'value': edited},
                );
              },
        child: const Text('编辑'),
      ),
    );
  }

  Widget _buildStringListControl(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final list = (param['value'] as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];
    return _parameterRow(
      label: label,
      subtitle: list.isEmpty ? '(空)' : list.join('、'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _isSending
            ? null
            : () async {
                final edited = await _showTextInputDialog(
                  title: '$label（每行一个）',
                  initialValue: list.join('\n'),
                  minLines: 3,
                  maxLines: 6,
                );
                if (edited == null) return;
                final words = edited
                    .split(RegExp(r'[\n,;，；]+'))
                    .map((item) => item.trim())
                    .where((item) => item.isNotEmpty)
                    .toList(growable: false);
                await _sendCommand(
                  'set_parameter',
                  args: <String, dynamic>{'key': key, 'value': words},
                );
              },
        child: const Text('编辑'),
      ),
    );
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String initialValue,
    int minLines = 1,
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: Text(title),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              isDefaultAction: true,
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _parameterRow({
    required String label,
    String? subtitle,
    Widget? subtitleWidget,
    Widget? trailing,
  }) {
    final secondaryText =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14)),
                if (subtitleWidget != null) ...[
                  const SizedBox(height: 4),
                  subtitleWidget,
                ] else if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: secondaryText, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }
}
