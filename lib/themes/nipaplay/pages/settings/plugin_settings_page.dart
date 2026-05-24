import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/plugins/models/plugin_ui_action_result.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/themes/nipaplay/widgets/glass_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/plugin_market_dialog.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/providers/settings_provider.dart';

class PluginSettingsPage extends StatefulWidget {
  const PluginSettingsPage({super.key});

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  bool _isCheckingUpdates = false;
  final TextEditingController _proxyController = TextEditingController();
  String? _proxyUrlError;
  bool _proxyInitialized = false;
  bool _isProxySaving = false;

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

  static const String _pluginsIndexUrl =
      'https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main/plugins.json';

  Future<void> _applyProxyUrl() async {
    if (_isProxySaving) return;
    final value = _proxyController.text;
    final error = _validateProxyUrl(value);
    setState(() {
      _proxyUrlError = error;
    });
    if (error != null) return;

    if (value.trim().isEmpty) {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      settingsProvider.setGithubProxyUrl('');
      return;
    }

    setState(() {
      _isProxySaving = true;
    });

    final normalizedProxy =
        value.trim().endsWith('/') ? value.trim() : '${value.trim()}/';
    final testUrl = '$normalizedProxy$_pluginsIndexUrl';

    try {
      final response = await http
          .get(Uri.parse(testUrl))
          .timeout(const Duration(seconds: 10));
      if (!context.mounted) return;
      if (response.statusCode == 200) {
        final settingsProvider =
            Provider.of<SettingsProvider>(context, listen: false);
        settingsProvider.setGithubProxyUrl(value.trim());
        BlurSnackBar.show(
          context,
          context.l10n.localeName.startsWith('zh_Hant')
              ? '加速源驗證通過，已儲存'
              : '加速源验证通过，已保存',
        );
      } else {
        BlurSnackBar.show(
          context,
          context.l10n.localeName.startsWith('zh_Hant')
              ? '加速源請求失敗 (${response.statusCode})'
              : '加速源请求失败 (${response.statusCode})',
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      BlurSnackBar.show(
        context,
        context.l10n.localeName.startsWith('zh_Hant')
            ? '加速源連接失敗，請檢查地址'
            : '加速源连接失败，请检查地址',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProxySaving = false;
        });
      }
    }
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

  String _pluginEnableToast(BuildContext context, String name) {
    final l10n = context.l10n;
    if (l10n.localeName.startsWith('zh_Hant')) {
      return '已啟用插件：$name';
    }
    return '已启用插件：$name';
  }

  String _pluginDisableToast(BuildContext context, String name) {
    final l10n = context.l10n;
    if (l10n.localeName.startsWith('zh_Hant')) {
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

  String _pluginDeleteTooltip(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '刪除插件';
    }
    return '删除插件';
  }

  Future<void> _confirmDeletePlugin(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.l10n.localeName.startsWith('zh_Hant') ? '確認刪除' : '确认删除',
        ),
        content: Text(
          context.l10n.localeName.startsWith('zh_Hant')
              ? '確定要刪除插件「${plugin.manifest.name}」嗎？此操作不可撤銷。'
              : '确定要删除插件「${plugin.manifest.name}」吗？此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              context.l10n.localeName.startsWith('zh_Hant') ? '刪除' : '删除',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final success = await pluginService.deletePlugin(plugin.manifest.id);
    if (!context.mounted) return;
    if (success) {
      BlurSnackBar.show(
          context, _pluginDeleteToast(context, plugin.manifest.name));
    } else {
      BlurSnackBar.show(context, _pluginDeleteFailed(context));
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

  String _pluginActionNotAvailable(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '僅在插件啟用後可使用';
    }
    return '仅在插件启用后可用';
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

  String _pluginActionContentFallback(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '（無可顯示內容）';
    }
    return '（无可显示内容）';
  }

  String _pluginActionChooseHint(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '選擇要打開的插件功能';
    }
    return '选择要打开的插件功能';
  }

  String _importPluginButtonText(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '導入插件';
    }
    return '导入插件';
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

  String _importPluginCanceled(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '已取消導入插件';
    }
    return '已取消导入插件';
  }

  String _pluginMarketButtonText(BuildContext context) {
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

  String? _validateProxyUrl(String? url) {
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    final trimmed = url.trim();
    if (!trimmed.startsWith('https://') && !trimmed.startsWith('http://')) {
      return 'URL必须以 http:// 或 https:// 开头';
    }
    if (!trimmed.endsWith('/')) {
      return 'URL必须以 / 结尾';
    }
    try {
      final uri = Uri.parse(trimmed);
      if (!uri.hasScheme || !uri.hasAuthority) {
        return 'URL格式无效';
      }
    } catch (_) {
      return 'URL格式无效';
    }
    return null;
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
        if (!context.mounted) return;
        BlurSnackBar.show(context, _importPluginCanceled(context));
        return;
      }

      final path = result.files.single.path!;
      final importedId = await pluginService.importPluginScript(
        sourceFilePath: path,
      );
      if (!context.mounted) return;
      BlurSnackBar.show(
        context,
        _importPluginSuccess(context, importedId ?? path.split('/').last),
      );
    } catch (error) {
      if (!context.mounted) return;
      BlurSnackBar.show(context, _importPluginFailed(context, error));
    }
  }

  String _pluginSubtitle(BuildContext context, PluginDescriptor plugin) {
    final subtitle = StringBuffer()
      ..write('v${plugin.manifest.version} · ${plugin.manifest.author}');
    if (plugin.manifest.description.isNotEmpty) {
      subtitle
        ..write('\n')
        ..write(plugin.manifest.description);
    }
    if (plugin.manifest.github != null) {
      subtitle
        ..write('\nGitHub: ')
        ..write(plugin.manifest.github);
    }
    if (plugin.errorMessage != null && plugin.errorMessage!.isNotEmpty) {
      subtitle
        ..write('\n加载失败: ')
        ..write(plugin.errorMessage);
    }
    if (plugin.uiEntries.isNotEmpty) {
      subtitle
        ..write('\n')
        ..write(_pluginActionChooseHint(context))
        ..write('（')
        ..write(plugin.uiEntries.length)
        ..write('）');
    }
    return subtitle.toString();
  }

  Future<void> _showPluginActionPicker(
    BuildContext context,
    PluginDescriptor plugin,
  ) async {
    final entries = plugin.uiEntries;
    if (entries.isEmpty) {
      BlurSnackBar.show(context, _pluginActionNotAvailable(context));
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
      final selected = await GlassBottomSheet.show<PluginUiEntry>(
        context: context,
        title: _pluginActionTitle(context, plugin),
        height: MediaQuery.of(context).size.height * 0.56,
        child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (itemContext, index) {
            final entry = entries[index];
            return ListTile(
              title: Text(entry.title),
              subtitle:
                  entry.description == null ? null : Text(entry.description!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(itemContext).pop(entry),
            );
          },
        ),
      );
      if (!context.mounted || selected == null) return;
      await _invokePluginAction(context, plugin, selected);
      return;
    }

    await GlassBottomSheet.show<void>(
      context: context,
      title: _pluginActionTitle(context, plugin),
      height: MediaQuery.of(context).size.height * 0.56,
      child: Consumer<PluginService>(
        builder: (sheetContext, pluginService, child) {
          final updatedPlugin = pluginService.plugins.firstWhere(
              (p) => p.manifest.id == plugin.manifest.id,
              orElse: () => plugin);
          final currentEntries = updatedPlugin.uiEntries;
          final showBottomButtons = currentEntries.any((e) => e.isTextInput);

          final listView = ListView.builder(
            shrinkWrap: true,
            itemCount: currentEntries.length,
            itemBuilder: (itemContext, index) {
              final entry = currentEntries[index];
              if (entry.isSwitch) {
                final switchValue = pluginService.getSwitchSettingValue(
                    updatedPlugin.manifest.id, entry.id);
                return ListTile(
                  title: Text(entry.title),
                  subtitle: entry.description == null
                      ? null
                      : Text(entry.description!),
                  trailing: FluentSettingsSwitch(
                    value: switchValue,
                    onChanged: (_) async {
                      await pluginService.setSwitchSettingValue(
                          updatedPlugin.manifest.id, entry.id, !switchValue);
                      await _invokePluginAction(
                          sheetContext, updatedPlugin, entry,
                          showResult: false);
                    },
                  ),
                );
              }
              if (entry.isTextInput) {
                final currentValue = pluginService.getTextSettingValue(
                    updatedPlugin.manifest.id, entry.id);
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _PluginTextSettingField(
                        key: ValueKey(
                            '${updatedPlugin.manifest.id}_${entry.id}'),
                        initialValue: currentValue,
                        hintText: entry.textSetting?.hintText,
                        onChanged: (value) {
                          pluginService.setTextSettingValue(
                              updatedPlugin.manifest.id, entry.id, value);
                        },
                      ),
                    ],
                  ),
                );
              }
              return ListTile(
                title: Text(entry.title),
                subtitle:
                    entry.description == null ? null : Text(entry.description!),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  Navigator.of(itemContext).pop();
                  if (!context.mounted) return;
                  await _invokePluginAction(context, updatedPlugin, entry);
                },
              );
            },
          );

          if (!showBottomButtons) return listView;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: listView,
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: Text(
                        context.l10n.localeName.startsWith('zh_Hant')
                            ? '關閉'
                            : '关闭',
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
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
      BlurSnackBar.show(context, _pluginActionNotLoaded(context));
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
          BlurSnackBar.show(context, _pluginActionEmpty(context));
        }
        return;
      }
      if (showResult) {
        await _showPluginActionResult(context, result);
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      BlurSnackBar.show(context, _pluginActionError(context, error));
    }
  }

  Future<void> _showPluginActionResult(
    BuildContext context,
    PluginUiActionResult result,
  ) async {
    final content = result.content.trim().isEmpty
        ? _pluginActionContentFallback(context)
        : result.content;
    await GlassBottomSheet.show<void>(
      context: context,
      title: result.title,
      height: MediaQuery.of(context).size.height * 0.64,
      child: SelectableText(content),
    );
  }

  Widget _buildPluginToggleTrailing(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) {
    final actionEnabled = plugin.enabled && plugin.uiEntries.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!plugin.isBuiltin)
          _HoverScaleIconButton(
            tooltip: _pluginDeleteTooltip(context),
            icon: Icons.delete_outline,
            onPressed: () =>
                _confirmDeletePlugin(context, plugin, pluginService),
          ),
        _HoverScaleIconButton(
          tooltip: actionEnabled
              ? _pluginActionTitle(context, plugin)
              : _pluginActionNotAvailable(context),
          icon: Icons.handyman,
          onPressed: actionEnabled
              ? () => _showPluginActionPicker(context, plugin)
              : null,
        ),
        FluentSettingsSwitch(
          value: plugin.enabled,
          onChanged: (value) async {
            await pluginService.setPluginEnabled(plugin.manifest.id, value);
            if (!context.mounted) return;
            BlurSnackBar.show(
              context,
              value
                  ? _pluginEnableToast(context, plugin.manifest.name)
                  : _pluginDisableToast(context, plugin.manifest.name),
            );
          },
        ),
      ],
    );
  }

  Widget _buildUpdateBadge(String version) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '有更新 v$version',
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<PluginService>(
      builder: (context, pluginService, child) {
        if (!pluginService.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }

        final plugins = pluginService.plugins;
        if (plugins.isEmpty) {
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    _HoverScaleTextAction(
                      icon: Ionicons.cloud_upload_outline,
                      text: _importPluginButtonText(context),
                      onPressed: () => _importPlugin(context, pluginService),
                    ),
                    const SizedBox(width: 16),
                    _HoverScaleTextAction(
                      icon: Ionicons.storefront_outline,
                      text: _pluginMarketButtonText(context),
                      onPressed: () => _openPluginMarket(context),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (context) {
                  if (!_proxyInitialized) {
                    final settingsProvider =
                        Provider.of<SettingsProvider>(context, listen: false);
                    _proxyController.text = settingsProvider.githubProxyUrl;
                    _proxyInitialized = true;
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _githubProxyLabel(context),
                          style: TextStyle(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _proxyController,
                            cursorColor: AppAccentColors.current,
                            decoration: InputDecoration(
                              hintText: _githubProxyHint(context),
                              hintStyle: TextStyle(
                                  color: colorScheme.onSurface
                                      .withValues(alpha: 0.38)),
                              filled: true,
                              fillColor:
                                  colorScheme.onSurface.withValues(alpha: 0.1),
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(8)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: AppAccentColors.current, width: 2),
                                borderRadius:
                                    const BorderRadius.all(Radius.circular(8)),
                              ),
                              errorText: _proxyUrlError,
                            ),
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _isProxySaving ? null : _applyProxyUrl,
                          icon: _isProxySaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.check, size: 18),
                          label: Text(
                            context.l10n.localeName.startsWith('zh_Hant')
                                ? '儲存'
                                : '保存',
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppAccentColors.current,
                            side: BorderSide(color: AppAccentColors.current),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Text(
                  _pluginsEmpty(context),
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          );
        }

        final items = <Widget>[];
        for (var i = 0; i < plugins.length; i++) {
          final plugin = plugins[i];
          final updateVersion =
              pluginService.getAvailableUpdateVersion(plugin.manifest.id);

          items.add(
            ListTile(
              leading: Icon(
                Ionicons.extension_puzzle_outline,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      plugin.manifest.name,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (updateVersion != null) _buildUpdateBadge(updateVersion),
                ],
              ),
              subtitle: Text(
                _pluginSubtitle(context, plugin),
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              trailing: _buildPluginToggleTrailing(
                context,
                plugin,
                pluginService,
              ),
              onTap: () async {
                final target = !plugin.enabled;
                await pluginService.setPluginEnabled(
                    plugin.manifest.id, target);
                if (!context.mounted) return;
                BlurSnackBar.show(
                  context,
                  target
                      ? _pluginEnableToast(context, plugin.manifest.name)
                      : _pluginDisableToast(context, plugin.manifest.name),
                );
              },
            ),
          );

          if (i != plugins.length - 1) {
            items.add(
              Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1,
              ),
            );
          }
        }

        return ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  _HoverScaleTextAction(
                    icon: Ionicons.cloud_upload_outline,
                    text: _importPluginButtonText(context),
                    onPressed: () => _importPlugin(context, pluginService),
                  ),
                  const SizedBox(width: 16),
                  _HoverScaleTextAction(
                    icon: Ionicons.storefront_outline,
                    text: _pluginMarketButtonText(context),
                    onPressed: () => _openPluginMarket(context),
                  ),
                  if (_isCheckingUpdates)
                    const SizedBox(width: 8)
                  else
                    const SizedBox(),
                  if (_isCheckingUpdates)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const SizedBox(),
                ],
              ),
            ),
            Builder(
              builder: (context) {
                if (!_proxyInitialized) {
                  final settingsProvider =
                      Provider.of<SettingsProvider>(context, listen: false);
                  _proxyController.text = settingsProvider.githubProxyUrl;
                  _proxyInitialized = true;
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _githubProxyLabel(context),
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.78),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _proxyController,
                          cursorColor: AppAccentColors.current,
                          decoration: InputDecoration(
                            hintText: _githubProxyHint(context),
                            hintStyle: TextStyle(
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.38)),
                            filled: true,
                            fillColor:
                                colorScheme.onSurface.withValues(alpha: 0.1),
                            border: OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(8)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: AppAccentColors.current, width: 2),
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(8)),
                            ),
                            errorText: _proxyUrlError,
                          ),
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _isProxySaving ? null : _applyProxyUrl,
                        icon: _isProxySaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(
                          context.l10n.localeName.startsWith('zh_Hant')
                              ? '儲存'
                              : '保存',
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppAccentColors.current,
                          side: BorderSide(color: AppAccentColors.current),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Divider(
              color: colorScheme.onSurface.withValues(alpha: 0.12),
              height: 1,
            ),
            ...items,
          ],
        );
      },
    );
  }
}

class _HoverScaleTextAction extends StatefulWidget {
  const _HoverScaleTextAction({
    required this.text,
    required this.onPressed,
    this.icon,
  });

  final String text;
  final VoidCallback onPressed;
  final IconData? icon;

  @override
  State<_HoverScaleTextAction> createState() => _HoverScaleTextActionState();
}

class _HoverScaleTextActionState extends State<_HoverScaleTextAction> {
  static Color get _nipaAccentColor => AppAccentColors.current;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = _isHovered
        ? _nipaAccentColor
        : colorScheme.onSurface.withValues(alpha: 0.78);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isHovered ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null)
                  Icon(widget.icon, color: textColor, size: 20),
                if (widget.icon != null) const SizedBox(width: 8),
                Text(
                  widget.text,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HoverScaleIconButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _HoverScaleIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<_HoverScaleIconButton> createState() => _HoverScaleIconButtonState();
}

class _HoverScaleIconButtonState extends State<_HoverScaleIconButton> {
  static Color get _nipaAccentColor => AppAccentColors.current;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null;
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = !isEnabled
        ? colorScheme.onSurface.withValues(alpha: 0.35)
        : (_isHovered
            ? _nipaAccentColor
            : colorScheme.onSurface.withValues(alpha: 0.7));

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: isEnabled,
        label: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => isEnabled ? setState(() => _isHovered = true) : null,
          onExit: (_) => isEnabled ? setState(() => _isHovered = false) : null,
          cursor:
              isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedScale(
                scale: _isHovered && isEnabled ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Icon(widget.icon, size: 20, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PluginTextSettingField extends StatefulWidget {
  const _PluginTextSettingField({
    super.key,
    required this.initialValue,
    this.hintText,
    required this.onChanged,
  });

  final String initialValue;
  final String? hintText;
  final ValueChanged<String> onChanged;

  @override
  State<_PluginTextSettingField> createState() =>
      _PluginTextSettingFieldState();
}

class _PluginTextSettingFieldState extends State<_PluginTextSettingField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        hintText: widget.hintText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      onChanged: widget.onChanged,
    );
  }
}
