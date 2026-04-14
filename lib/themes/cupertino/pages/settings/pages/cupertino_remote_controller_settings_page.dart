import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nipaplay/services/remote_control_client_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

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
    if (_matchedBaseUrl == null || _matchedBaseUrl!.isEmpty) {
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
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);
    final tileBackground = resolveSettingsTileBackground(context);
    final topPadding = MediaQuery.of(context).padding.top + 64;

    final label = _matchedHostname?.trim().isNotEmpty == true
        ? _matchedHostname!.trim()
        : (_matchedBaseUrl ?? '未匹配');
    final connected = _remoteState != null;
    final receiverEnabled = _remoteState?['receiverEnabled'] == true;
    final statusText =
        connected ? (receiverEnabled ? '已连接' : '对方已关闭被遥控端') : '未连接';

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '远程访问',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            children: [
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: [
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.dot_radiowaves_left_right,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('当前匹配设备'),
                    subtitle: Text(label),
                    backgroundColor: tileBackground,
                  ),
                  CupertinoSettingsTile(
                    leading: Icon(
                      connected && receiverEnabled
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.exclamationmark_triangle,
                      color: connected && receiverEnabled
                          ? CupertinoColors.activeGreen
                          : resolveSettingsIconColor(context),
                    ),
                    title: const Text('连接状态'),
                    subtitle: Text(statusText),
                    backgroundColor: tileBackground,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: [
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.search,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('自动扫描并匹配'),
                    subtitle: const Text('默认局域网自动发现设备'),
                    trailing: _isScanning
                        ? const CupertinoActivityIndicator(radius: 8)
                        : null,
                    backgroundColor: tileBackground,
                    onTap: _isScanning ? null : _scanAndMatch,
                  ),
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.refresh,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('刷新状态'),
                    subtitle: const Text('同步目标设备实时播放状态'),
                    trailing: _isLoadingState
                        ? const CupertinoActivityIndicator(radius: 8)
                        : null,
                    backgroundColor: tileBackground,
                    onTap: _isLoadingState ? null : _refreshRemoteState,
                  ),
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.tv,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('打开遥控器'),
                    subtitle: const Text('打开上拉遥控面板'),
                    showChevron: true,
                    backgroundColor: tileBackground,
                    onTap: _openRemotePanel,
                  ),
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.trash,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('清除匹配设备'),
                    subtitle: const Text('下次将重新自动扫描'),
                    backgroundColor: tileBackground,
                    onTap: _matchedBaseUrl == null ? null : _clearMatchedTarget,
                  ),
                ],
              ),
            ],
          ),
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
      // ignore
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
      if (!success && showError && mounted) {
        AdaptiveSnackBar.show(
          context,
          message: response['message']?.toString() ?? '执行失败',
        );
      }
      await _refresh(silent: true);
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
      args: <String, dynamic>{'comment': text},
    );
    if (!mounted) return;
    _danmakuController.clear();
    AdaptiveSnackBar.show(context, message: '弹幕已发送');
  }

  List<Map<String, dynamic>> get _menus {
    final raw = _payload?['menus'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _openMenuPane(Map<String, dynamic> menu) async {
    final paneId = menu['paneId']?.toString() ?? '';
    final title = menu['title']?.toString() ?? paneId;
    if (paneId.isEmpty) return;
    await CupertinoBottomSheet.show<void>(
      context: context,
      title: title,
      floatingTitle: true,
      heightRatio: 0.92,
      child: _RemoteMenuPaneSheet(
        baseUrl: widget.baseUrl,
        paneId: paneId,
        title: title,
      ),
    );
    await _refresh(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _payload?['snapshot'] as Map<String, dynamic>?;
    final isPaused = snapshot?['isPaused'] == true;
    final title = snapshot?['animeTitle']?.toString();
    final episode = snapshot?['episodeTitle']?.toString();
    final hostLabel = widget.hostname?.trim().isNotEmpty == true
        ? widget.hostname!.trim()
        : widget.baseUrl;

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        return [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, topSpacing, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Container(
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
                      '${title ?? '未播放'}  ${episode ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPaused ? '状态: 暂停' : '状态: 播放中',
                      style: TextStyle(
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.secondaryLabel,
                          context,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
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
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildMenuList(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ];
      },
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

  Widget _buildMenuList() {
    final menus = _menus;
    if (menus.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text('暂无菜单项'),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.secondarySystemGroupedBackground,
          context,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < menus.length; i++) ...[
            CupertinoListTile(
              title: Text(menus[i]['title']?.toString() ?? '菜单'),
              subtitle: const Text('点击展开'),
              trailing: const Icon(CupertinoIcons.chevron_forward, size: 16),
              onTap: () => _openMenuPane(menus[i]),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            if (i != menus.length - 1)
              Container(
                height: 0.5,
                color: CupertinoDynamicColor.resolve(
                  CupertinoColors.separator,
                  context,
                ),
                margin: const EdgeInsets.only(left: 14),
              ),
          ],
        ],
      ),
    );
  }
}

class _RemoteMenuPaneSheet extends StatefulWidget {
  const _RemoteMenuPaneSheet({
    required this.baseUrl,
    required this.paneId,
    required this.title,
  });

  final String baseUrl;
  final String paneId;
  final String title;

  @override
  State<_RemoteMenuPaneSheet> createState() => _RemoteMenuPaneSheetState();
}

class _RemoteMenuPaneSheetState extends State<_RemoteMenuPaneSheet> {
  bool _isLoading = false;
  bool _isSending = false;
  List<Map<String, dynamic>> _params = const [];
  final Map<String, double> _draftNumeric = {};
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadPane();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      _loadPane(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPane({bool silent = false}) async {
    if (!mounted || _isLoading) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final payload = await RemoteControlClientService.fetchState(
        widget.baseUrl,
        paneId: widget.paneId,
        includeParameters: true,
      );
      if (!mounted || payload == null) return;
      final raw = payload['parameters'];
      if (raw is! List) return;
      final parsed = raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => item['paneId']?.toString() == widget.paneId)
          .toList(growable: false);
      setState(() {
        _params = parsed;
      });
    } finally {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setParameter(String key, dynamic value) async {
    if (_isSending) return;
    setState(() {
      _isSending = true;
    });
    try {
      final response = await RemoteControlClientService.sendCommand(
        widget.baseUrl,
        command: 'set_parameter',
        args: <String, dynamic>{'key': key, 'value': value},
      );
      if (response['success'] != true && mounted) {
        AdaptiveSnackBar.show(
          context,
          message: response['message']?.toString() ?? '设置失败',
        );
      }
    } catch (e) {
      if (mounted) {
        AdaptiveSnackBar.show(context, message: '设置失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
        await _loadPane(silent: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        if (_isLoading && _params.isEmpty) {
          return [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, topSpacing + 24, 20, 20),
              sliver: const SliverToBoxAdapter(
                child: Center(child: CupertinoActivityIndicator()),
              ),
            ),
          ];
        }

        if (_params.isEmpty) {
          return [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, topSpacing + 24, 20, 20),
              sliver: const SliverToBoxAdapter(
                child: Text('该菜单暂无可调参数'),
              ),
            ),
          ];
        }

        return [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, topSpacing, 16, 16),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.secondarySystemGroupedBackground,
                    context,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: _params
                      .map((param) => _buildParamControl(param))
                      .toList(growable: false),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ];
      },
    );
  }

  Widget _buildParamControl(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final type = param['type']?.toString() ?? 'readonly';
    final label = param['label']?.toString() ?? key;

    switch (type) {
      case 'bool':
        final value = param['value'] == true;
        return _row(
          label: label,
          trailing: CupertinoSwitch(
            value: value,
            onChanged: _isSending ? null : (next) => _setParameter(key, next),
          ),
        );
      case 'int':
      case 'double':
        return _buildNumericParam(param, isInteger: type == 'int');
      case 'enum':
      case 'select':
        return _buildSelectParam(param);
      case 'string':
        return _buildStringParam(param);
      case 'string_list':
        return _buildStringListParam(param);
      case 'json':
      case 'readonly':
      default:
        return _buildReadonlyParam(label, param['value']);
    }
  }

  Widget _buildNumericParam(
    Map<String, dynamic> param, {
    required bool isInteger,
  }) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final min = (param['min'] as num?)?.toDouble();
    final max = (param['max'] as num?)?.toDouble();
    final step = (param['step'] as num?)?.toDouble() ?? (isInteger ? 1 : 0.1);
    final raw = (param['value'] as num?)?.toDouble() ?? 0.0;
    final value = _draftNumeric[key] ?? raw;

    if (min != null && max != null && max > min) {
      final clamped = value.clamp(min, max);
      return Column(
        children: [
          _row(
            label: label,
            subtitle:
                isInteger ? '${clamped.round()}' : clamped.toStringAsFixed(2),
          ),
          CupertinoSlider(
            value: clamped,
            min: min,
            max: max,
            divisions: isInteger ? (max - min).round() : null,
            onChanged: _isSending
                ? null
                : (next) {
                    setState(() {
                      _draftNumeric[key] = next;
                    });
                  },
            onChangeEnd: _isSending
                ? null
                : (next) async {
                    final output = isInteger
                        ? next.round()
                        : ((next / step).round() * step);
                    setState(() {
                      _draftNumeric.remove(key);
                    });
                    await _setParameter(key, output);
                  },
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    return _row(
      label: label,
      subtitle: isInteger ? '${value.round()}' : value.toStringAsFixed(2),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _isSending
            ? null
            : () async {
                final edited = await _showTextEditDialog(
                  title: label,
                  initialValue:
                      isInteger ? '${value.round()}' : value.toStringAsFixed(2),
                );
                if (edited == null) return;
                final parsed = isInteger
                    ? int.tryParse(edited.trim())
                    : double.tryParse(edited.trim());
                if (parsed == null) return;
                await _setParameter(key, parsed);
              },
        child: const Text('编辑'),
      ),
    );
  }

  Widget _buildSelectParam(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final value = param['value'];
    final options = (param['options'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];

    String currentLabel = value?.toString() ?? '未设置';
    for (final option in options) {
      if (option['value'] == value) {
        currentLabel = option['label']?.toString() ?? currentLabel;
        break;
      }
    }

    return _row(
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
                await _setParameter(key, selected);
              },
        child: const Text('修改'),
      ),
    );
  }

  Widget _buildStringParam(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final value = param['value']?.toString() ?? '';
    return _row(
      label: label,
      subtitle: value,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _isSending
            ? null
            : () async {
                final edited = await _showTextEditDialog(
                  title: label,
                  initialValue: value,
                );
                if (edited == null) return;
                await _setParameter(key, edited);
              },
        child: const Text('编辑'),
      ),
    );
  }

  Widget _buildStringListParam(Map<String, dynamic> param) {
    final key = param['key']?.toString() ?? '';
    final label = param['label']?.toString() ?? key;
    final list = (param['value'] as List?)
            ?.map((item) => item.toString())
            .toList(growable: false) ??
        const <String>[];

    return _row(
      label: label,
      subtitle: list.isEmpty ? '(空)' : list.join('、'),
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        onPressed: _isSending
            ? null
            : () async {
                final edited = await _showTextEditDialog(
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
                await _setParameter(key, words);
              },
        child: const Text('编辑'),
      ),
    );
  }

  Widget _buildReadonlyParam(String label, dynamic rawValue) {
    final decoded = _decodePotentialJson(rawValue);
    final textValue = _stringifyValue(decoded);
    return _row(
      label: label,
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StructuredValueView(value: decoded),
          const SizedBox(height: 4),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: textValue));
              if (!mounted) return;
              AdaptiveSnackBar.show(context, message: '已复制');
            },
            child: const Text('复制'),
          ),
        ],
      ),
    );
  }

  dynamic _decodePotentialJson(dynamic value) {
    if (value is String) {
      final trimmed = value.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          return json.decode(trimmed);
        } catch (_) {
          return value;
        }
      }
    }
    return value;
  }

  String _stringifyValue(dynamic value) {
    if (value is Map || value is List) {
      return const JsonEncoder.withIndent('  ').convert(value);
    }
    return value?.toString() ?? '';
  }

  Future<String?> _showTextEditDialog({
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
              isDefaultAction: true,
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _row({
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

class _StructuredValueView extends StatelessWidget {
  const _StructuredValueView({
    required this.value,
    this.depth = 0,
  });

  final dynamic value;
  final int depth;

  static const int _maxListItems = 30;

  @override
  Widget build(BuildContext context) {
    final secondaryText =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final leftPadding = (depth * 10).toDouble();

    if (value is Map) {
      final map = Map<String, dynamic>.from(value as Map);
      if (map.isEmpty) {
        return Padding(
          padding: EdgeInsets.only(left: leftPadding),
          child: Text('(空对象)', style: TextStyle(color: secondaryText)),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: map.entries.map((entry) {
          return Padding(
            padding: EdgeInsets.only(left: leftPadding, top: 2, bottom: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key}:',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                _StructuredValueView(value: entry.value, depth: depth + 1),
              ],
            ),
          );
        }).toList(growable: false),
      );
    }

    if (value is List) {
      final list = List<dynamic>.from(value);
      if (list.isEmpty) {
        return Padding(
          padding: EdgeInsets.only(left: leftPadding),
          child: Text('(空列表)', style: TextStyle(color: secondaryText)),
        );
      }
      final display = list.length > _maxListItems
          ? list.take(_maxListItems).toList(growable: false)
          : list;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...display.asMap().entries.map((entry) {
            return Padding(
              padding: EdgeInsets.only(left: leftPadding, top: 2, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '[${entry.key}]',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  _StructuredValueView(value: entry.value, depth: depth + 1),
                ],
              ),
            );
          }),
          if (list.length > _maxListItems)
            Padding(
              padding: EdgeInsets.only(left: leftPadding),
              child: Text(
                '... 其余 ${list.length - _maxListItems} 项未展开',
                style: TextStyle(color: secondaryText, fontSize: 12),
              ),
            ),
        ],
      );
    }

    final text = value?.toString() ?? 'null';
    return Padding(
      padding: EdgeInsets.only(left: leftPadding),
      child: Text(
        text,
        style: TextStyle(color: secondaryText, fontSize: 12),
      ),
    );
  }
}
