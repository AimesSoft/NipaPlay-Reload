import 'package:flutter/material.dart' show SelectableText;
import 'package:file_picker/file_picker.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/plugins/models/plugin_ui_action_result.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/themes/nipaplay/widgets/plugin_market_dialog.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:provider/provider.dart';

class CupertinoPluginSettingsPage extends StatefulWidget {
  const CupertinoPluginSettingsPage({super.key});

  @override
  State<CupertinoPluginSettingsPage> createState() =>
      _CupertinoPluginSettingsPageState();
}

class _CupertinoPluginSettingsPageState
    extends State<CupertinoPluginSettingsPage> {
  bool _isCheckingUpdates = false;
  final TextEditingController _proxyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkPluginUpdates();
  }

  @override
  void dispose() {
    _proxyController.dispose();
    super.dispose();
  }

  Future<void> _checkPluginUpdates() async {
    setState(() {
      _isCheckingUpdates = true;
    });
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final pluginService = Provider.of<PluginService>(context, listen: false);
    await pluginService.fetchRemotePlugins(
      proxyUrl: settingsProvider.githubProxyUrl,
    );
    setState(() {
      _isCheckingUpdates = false;
    });
  }

  Widget _buildUpdateBadge(String version) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGreen,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '有更新 v$version',
        style: const TextStyle(
          fontSize: 11,
          color: CupertinoColors.white,
        ),
      ),
    );
  }

  String _pluginEnableToast(BuildContext context, String name) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '已啟用插件：$name';
    }
    return '已启用插件：$name';
  }

  String _pluginDisableToast(BuildContext context, String name) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '已停用插件：$name';
    }
    return '已禁用插件：$name';
  }

  String _pluginDeleteToast(BuildContext context, String name) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '已刪除插件：$name';
    }
    return '已删除插件：$name';
  }

  String _pluginDeleteFailed(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '內建插件無法刪除';
    }
    return '内置插件无法删除';
  }

  Future<void> _confirmDeletePlugin(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(
          context.l10n.localeName.startsWith('zh_Hant') ? '確認刪除' : '确认删除',
        ),
        content: Text(
          context.l10n.localeName.startsWith('zh_Hant')
              ? '確定要刪除插件「${plugin.manifest.name}」嗎？此操作不可撤銷。'
              : '确定要删除插件「${plugin.manifest.name}」吗？此操作不可撤销。',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              context.l10n.localeName.startsWith('zh_Hant') ? '刪除' : '删除',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final success = await pluginService.deletePlugin(plugin.manifest.id);
    if (!context.mounted) return;
    if (success) {
      AdaptiveSnackBar.show(
        context,
        message: _pluginDeleteToast(context, plugin.manifest.name),
        type: AdaptiveSnackBarType.success,
      );
    } else {
      AdaptiveSnackBar.show(
        context,
        message: _pluginDeleteFailed(context),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String _pluginsEmpty(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '暫無可用插件';
    }
    return '暂无可用插件';
  }

  String _pluginActionTitle(BuildContext context, PluginDescriptor plugin) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '配置';
    }
    return '配置';
  }

  String _pluginActionNotLoaded(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '插件尚未就緒，請稍後重試';
    }
    return '插件尚未就绪，请稍后重试';
  }

  String _pluginActionEmpty(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '插件未返回內容';
    }
    return '插件未返回内容';
  }

  String _pluginActionError(BuildContext context, Object error) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '插件操作失敗：$error';
    }
    return '插件操作失败：$error';
  }

  String _pluginActionChooseHint(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '選擇要打開的插件功能';
    }
    return '选择要打开的插件功能';
  }

  String _pluginActionContentFallback(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '（無可顯示內容）';
    }
    return '（无可显示内容）';
  }

  String _importPluginTitle(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '導入插件';
    }
    return '导入插件';
  }

  String _importPluginHint(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '從本機選擇 .js 文件';
    }
    return '从本机选择 .js 文件';
  }

  String _importPluginSuccess(BuildContext context, String pluginId) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '插件導入成功：$pluginId';
    }
    return '插件导入成功：$pluginId';
  }

  String _importPluginFailed(BuildContext context, Object error) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '導入插件失敗：$error';
    }
    return '导入插件失败：$error';
  }

  String _pluginMarketTitle(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '插件市場';
    }
    return '插件市场';
  }

  String _githubProxyLabel(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return 'GitHub 加速';
    }
    return 'Github 加速';
  }

  String _githubProxyHint(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '請輸入加速源的地址，留空不啟用';
    }
    return '请输入加速源的地址，留空不启用';
  }

  void _openPluginMarket(BuildContext context) {
    PluginMarketDialog.show(context);
  }

  Future<void> _importPlugin(
    BuildContext context,
    PluginService pluginService,
  ) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['js'],
      );
      if (result == null ||
          result.files.isEmpty ||
          result.files.single.path == null) {
        return;
      }

      final path = result.files.single.path!;
      final importedId = await pluginService.importPluginScript(
        sourceFilePath: path,
      );
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message:
            _importPluginSuccess(context, importedId ?? path.split('/').last),
        type: AdaptiveSnackBarType.success,
      );
    } catch (error) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _importPluginFailed(context, error),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String _pluginSubtitle(BuildContext context, PluginDescriptor plugin) {
    final buffer = StringBuffer()
      ..write('v${plugin.manifest.version} · ${plugin.manifest.author}');
    if (plugin.manifest.description.isNotEmpty) {
      buffer
        ..write('\n')
        ..write(plugin.manifest.description);
    }
    if (plugin.manifest.github != null && plugin.manifest.github!.isNotEmpty) {
      buffer
        ..write('\nGitHub: ')
        ..write(plugin.manifest.github);
    }
    if (plugin.errorMessage != null && plugin.errorMessage!.isNotEmpty) {
      buffer
        ..write('\n加载失败: ')
        ..write(plugin.errorMessage);
    }
    if (plugin.uiEntries.isNotEmpty) {
      buffer
        ..write('\n')
        ..write(_pluginActionChooseHint(context))
        ..write('（')
        ..write(plugin.uiEntries.length)
        ..write('）');
    }
    return buffer.toString();
  }

  Future<void> _showPluginActionPicker(
    BuildContext context,
    PluginDescriptor plugin,
  ) async {
    final entries = plugin.uiEntries;
    if (entries.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: _pluginActionNotLoaded(context),
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }
    if (entries.length == 1 && entries.first.isAction) {
      await _invokePluginAction(context, plugin, entries.first);
      return;
    }

    final hasSwitches = entries.any((e) => e.isSwitch);
    final hasTextInputs = entries.any((e) => e.isTextInput);
    final hasInteractiveEntries = hasSwitches || hasTextInputs;

    if (!hasInteractiveEntries) {
      final selected =
          await showCupertinoModalPopupWithBottomBar<PluginUiEntry>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(_pluginActionTitle(context, plugin)),
          actions: entries
              .map(
                (entry) => CupertinoActionSheetAction(
                  onPressed: () => Navigator.of(sheetContext).pop(entry),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.title),
                      if (entry.description != null &&
                          entry.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          entry.description!,
                          style: const TextStyle(
                            fontSize: 13,
                            color: CupertinoColors.systemGrey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              )
              .toList(),
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: Text(context.l10n.cancel),
          ),
        ),
      );
      if (!context.mounted || selected == null) return;
      await _invokePluginAction(context, plugin, selected);
      return;
    }

    // 交互型入口（开关 / 文本框 / 动作）
    await CupertinoBottomSheet.show<void>(
      context: context,
      title: _pluginActionTitle(context, plugin),
      heightRatio: 0.56,
      child: Consumer<PluginService>(
        builder: (sheetContext, pluginService, _) {
          final updatedPlugin = pluginService.plugins.firstWhere(
            (p) => p.manifest.id == plugin.manifest.id,
            orElse: () => plugin,
          );
          final currentEntries = updatedPlugin.uiEntries;
          final showBottomButtons = currentEntries.any((e) => e.isTextInput);

          return SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: CupertinoBottomSheetContentLayout(
                    sliversBuilder: (contentContext, topSpacing) => [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(0, topSpacing, 0, 24),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final entry = currentEntries[index];
                              if (entry.isSwitch) {
                                return CupertinoListTile(
                                  title: Text(entry.title),
                                  subtitle: entry.description == null
                                      ? null
                                      : Text(entry.description!),
                                  trailing: CupertinoSwitch(
                                    value: entry.enabled!,
                                    onChanged: (_) async {
                                      await _invokePluginAction(
                                          sheetContext, updatedPlugin, entry,
                                          showResult: false);
                                    },
                                  ),
                                );
                              }
                              if (entry.isTextInput) {
                                final currentValue =
                                    pluginService.getTextSettingValue(
                                        updatedPlugin.manifest.id, entry.id);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (entry.description != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          entry.description!,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: CupertinoColors.systemGrey,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      CupertinoTextField(
                                        controller: TextEditingController(
                                            text: currentValue),
                                        placeholder:
                                            entry.textSetting?.hintText,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 10),
                                        onChanged: (value) {
                                          pluginService.setTextSettingValue(
                                              updatedPlugin.manifest.id,
                                              entry.id,
                                              value);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return CupertinoListTile(
                                title: Text(entry.title),
                                subtitle: entry.description == null
                                    ? null
                                    : Text(entry.description!),
                                trailing: const CupertinoListTileChevron(),
                                onTap: () async {
                                  Navigator.of(contentContext).pop();
                                  if (!context.mounted) return;
                                  await _invokePluginAction(
                                      context, updatedPlugin, entry);
                                },
                              );
                            },
                            childCount: currentEntries.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (showBottomButtons)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(
                            context.l10n.localeName.startsWith('zh_Hant')
                                ? '關閉'
                                : '关闭',
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(
                            context.l10n.localeName.startsWith('zh_Hant')
                                ? '儲存並關閉'
                                : '保存并关闭',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _invokePluginAction(
    BuildContext context,
    PluginDescriptor plugin,
    PluginUiEntry entry, {
    bool showResult = true,
  }) async {
    final pluginService = context.read<PluginService>();
    if (!plugin.enabled || !plugin.loaded) {
      AdaptiveSnackBar.show(
        context,
        message: _pluginActionNotLoaded(context),
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }

    try {
      final result = await pluginService.invokePluginUiAction(
        plugin.manifest.id,
        entry.id,
      );
      if (!context.mounted) {
        return;
      }
      if (result == null) {
        if (showResult) {
          AdaptiveSnackBar.show(
            context,
            message: _pluginActionEmpty(context),
            type: AdaptiveSnackBarType.warning,
          );
        }
        return;
      }
      if (showResult) {
        await _showPluginActionResult(context, result);
      }
    } catch (error) {
      if (!context.mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _pluginActionError(context, error),
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  Future<void> _showPluginActionResult(
    BuildContext context,
    PluginUiActionResult result,
  ) async {
    final content = result.content.trim().isEmpty
        ? _pluginActionContentFallback(context)
        : result.content;
    await CupertinoBottomSheet.show<void>(
      context: context,
      title: result.title,
      heightRatio: 0.72,
      child: SafeArea(
        top: false,
        child: CupertinoBottomSheetContentLayout(
          sliversBuilder: (contentContext, contentTopSpacing) => [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, contentTopSpacing, 16, 24),
              sliver: SliverToBoxAdapter(
                child: SelectableText(
                  content,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrailingActions(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) {
    final actionEnabled = plugin.enabled && plugin.uiEntries.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!plugin.isBuiltin)
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            minimumSize: const Size(0, 0),
            onPressed: () =>
                _confirmDeletePlugin(context, plugin, pluginService),
            child: const Icon(
              CupertinoIcons.trash,
              size: 19,
              color: CupertinoColors.destructiveRed,
            ),
          ),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          minimumSize: const Size(0, 0),
          onPressed: actionEnabled
              ? () => _showPluginActionPicker(context, plugin)
              : null,
          child: Icon(
            CupertinoIcons.wrench,
            size: 19,
            color: actionEnabled
                ? CupertinoTheme.of(context).primaryColor
                : CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey3,
                    context,
                  ),
          ),
        ),
        const SizedBox(width: 2),
        AdaptiveSwitch(
          value: plugin.enabled,
          onChanged: (value) async {
            await pluginService.setPluginEnabled(
              plugin.manifest.id,
              value,
            );
            if (!context.mounted) return;
            AdaptiveSnackBar.show(
              context,
              message: value
                  ? _pluginEnableToast(context, plugin.manifest.name)
                  : _pluginDisableToast(context, plugin.manifest.name),
              type: AdaptiveSnackBarType.success,
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: context.l10n.localeName.startsWith('zh_Hant') ? '插件' : '插件',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Consumer<PluginService>(
            builder: (context, pluginService, child) {
              if (!pluginService.isLoaded) {
                return const Center(child: CupertinoActivityIndicator());
              }

              final plugins = pluginService.plugins;
              if (plugins.isEmpty) {
                return ListView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                  children: [
                    CupertinoSettingsGroupCard(
                      margin: EdgeInsets.zero,
                      backgroundColor:
                          resolveSettingsSectionBackground(context),
                      addDividers: true,
                      children: [
                        CupertinoSettingsTile(
                          leading: Icon(
                            CupertinoIcons.square_arrow_down,
                            color: resolveSettingsIconColor(context),
                          ),
                          title: Text(_importPluginTitle(context)),
                          subtitle: Text(_importPluginHint(context)),
                          showChevron: true,
                          onTap: () => _importPlugin(context, pluginService),
                          backgroundColor:
                              resolveSettingsTileBackground(context),
                        ),
                        CupertinoSettingsTile(
                          leading: Icon(
                            CupertinoIcons.bag,
                            color: resolveSettingsIconColor(context),
                          ),
                          title: Row(
                            children: [
                              Text(_pluginMarketTitle(context)),
                              if (_isCheckingUpdates)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: CupertinoActivityIndicator(
                                    radius: 10,
                                  ),
                                ),
                            ],
                          ),
                          showChevron: true,
                          onTap: () => _openPluginMarket(context),
                          backgroundColor:
                              resolveSettingsTileBackground(context),
                        ),
                      ],
                    ),
                    Consumer<SettingsProvider>(
                      builder: (context, settingsProvider, child) {
                        if (_proxyController.text !=
                            settingsProvider.githubProxyUrl) {
                          _proxyController.text =
                              settingsProvider.githubProxyUrl;
                          _proxyController.selection =
                              TextSelection.fromPosition(
                            TextPosition(offset: _proxyController.text.length),
                          );
                        }
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                _githubProxyLabel(context),
                                style: TextStyle(
                                  color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.label,
                                    context,
                                  ).withValues(alpha: 0.78),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CupertinoTextField(
                                  controller: _proxyController,
                                  placeholder: _githubProxyHint(context),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: CupertinoDynamicColor.resolve(
                                      CupertinoColors.systemGrey5,
                                      context,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  onSubmitted: (value) {
                                    settingsProvider.setGithubProxyUrl(value);
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    CupertinoSettingsGroupCard(
                      margin: const EdgeInsets.only(top: 12),
                      backgroundColor:
                          resolveSettingsSectionBackground(context),
                      addDividers: true,
                      children: [
                        CupertinoSettingsTile(
                          title: Text(_pluginsEmpty(context)),
                          backgroundColor:
                              resolveSettingsTileBackground(context),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
                children: [
                  CupertinoSettingsGroupCard(
                    margin: EdgeInsets.zero,
                    backgroundColor: resolveSettingsSectionBackground(context),
                    addDividers: true,
                    children: [
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.square_arrow_down,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Text(_importPluginTitle(context)),
                        subtitle: Text(_importPluginHint(context)),
                        showChevron: true,
                        onTap: () => _importPlugin(context, pluginService),
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                      CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.bag,
                          color: resolveSettingsIconColor(context),
                        ),
                        title: Row(
                          children: [
                            Text(_pluginMarketTitle(context)),
                            if (_isCheckingUpdates)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: CupertinoActivityIndicator(
                                  radius: 10,
                                ),
                              ),
                          ],
                        ),
                        showChevron: true,
                        onTap: () => _openPluginMarket(context),
                        backgroundColor: resolveSettingsTileBackground(context),
                      ),
                    ],
                  ),
                  Consumer<SettingsProvider>(
                    builder: (context, settingsProvider, child) {
                      if (_proxyController.text !=
                          settingsProvider.githubProxyUrl) {
                        _proxyController.text = settingsProvider.githubProxyUrl;
                        _proxyController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _proxyController.text.length),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _githubProxyLabel(context),
                              style: TextStyle(
                                color: CupertinoDynamicColor.resolve(
                                  CupertinoColors.label,
                                  context,
                                ).withValues(alpha: 0.78),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CupertinoTextField(
                                controller: _proxyController,
                                placeholder: _githubProxyHint(context),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemGrey5,
                                    context,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                onSubmitted: (value) {
                                  settingsProvider.setGithubProxyUrl(value);
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  CupertinoSettingsGroupCard(
                    margin: const EdgeInsets.only(top: 12),
                    backgroundColor: resolveSettingsSectionBackground(context),
                    addDividers: true,
                    children: [
                      for (final plugin in plugins)
                        CupertinoSettingsTile(
                          leading: Icon(
                            CupertinoIcons.cube_box,
                            color: resolveSettingsIconColor(context),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(plugin.manifest.name),
                              ),
                              if (pluginService.getAvailableUpdateVersion(
                                      plugin.manifest.id) !=
                                  null)
                                _buildUpdateBadge(
                                    pluginService.getAvailableUpdateVersion(
                                        plugin.manifest.id)!),
                            ],
                          ),
                          subtitle: Text(
                            _pluginSubtitle(context, plugin),
                          ),
                          trailing: _buildTrailingActions(
                            context,
                            plugin,
                            pluginService,
                          ),
                          onTap: () async {
                            final target = !plugin.enabled;
                            await pluginService.setPluginEnabled(
                              plugin.manifest.id,
                              target,
                            );
                            if (!context.mounted) return;
                            AdaptiveSnackBar.show(
                              context,
                              message: target
                                  ? _pluginEnableToast(
                                      context,
                                      plugin.manifest.name,
                                    )
                                  : _pluginDisableToast(
                                      context,
                                      plugin.manifest.name,
                                    ),
                              type: AdaptiveSnackBarType.success,
                            );
                          },
                          backgroundColor:
                              resolveSettingsTileBackground(context),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
