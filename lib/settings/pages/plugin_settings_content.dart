import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/plugins/models/plugin_ui_action_result.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_navigation.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_modal_popup.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/glass_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/plugin_market_dialog.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:provider/provider.dart';

class PluginSettingsContent extends StatefulWidget {
  const PluginSettingsContent({super.key});

  @override
  State<PluginSettingsContent> createState() => _PluginSettingsContentState();
}

class _PluginSettingsContentState extends State<PluginSettingsContent> {
  static const String _pluginsIndexUrl =
      'https://raw.githubusercontent.com/AimesSoft/Nipaplay-plugins/refs/heads/main/plugins.json';

  final TextEditingController _proxyController = TextEditingController();
  String? _proxyUrlError;
  bool _proxyInitialized = false;
  bool _isProxySaving = false;
  bool _isCheckingUpdates = false;

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

  @override
  Widget build(BuildContext context) {
    return Consumer<PluginService>(
      builder: (context, pluginService, child) {
        if (!pluginService.isLoaded) {
          return AdaptiveSettingsPage(
            children: const [
              Center(child: CircularProgressIndicator()),
            ],
          );
        }

        final plugins = pluginService.plugins;

        return AdaptiveSettingsPage(
          children: [
            AdaptiveSettingsSection(
              children: [
                AdaptiveSettingsTile<void>.card(
                  title: _importPluginTitle(context),
                  subtitle: _importPluginHint(context),
                  icon: Ionicons.cloud_upload_outline,
                  phoneIcon: cupertino.CupertinoIcons.square_arrow_down,
                  onTap: () => _importPlugin(context, pluginService),
                ),
                AdaptiveSettingsTile<void>.card(
                  title: _pluginMarketTitle(context),
                  subtitle: _pluginMarketSubtitle(context),
                  icon: Ionicons.storefront_outline,
                  phoneIcon: cupertino.CupertinoIcons.bag,
                  onTap: () => _openPluginMarket(context),
                ),
                AdaptiveSettingsTile<void>.card(
                  title: _githubProxyLabel(context),
                  subtitle: _proxySubtitle(context),
                  icon: Ionicons.flash_outline,
                  phoneIcon: cupertino.CupertinoIcons.bolt_horizontal,
                  enabled: !_isProxySaving,
                  onTap: () => _editProxyUrl(context),
                ),
                AdaptiveSettingsTile<void>.card(
                  title: _checkingUpdatesTitle(context),
                  subtitle: _checkingUpdatesSubtitle(context),
                  icon: Ionicons.refresh_outline,
                  phoneIcon: cupertino.CupertinoIcons.refresh,
                  enabled: !_isCheckingUpdates,
                  onTap: _checkPluginUpdates,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (plugins.isEmpty)
              AdaptiveSettingsSection(
                children: [
                  AdaptiveSettingsTile<void>.card(
                    title: _pluginsEmpty(context),
                    subtitle: _pluginsEmptyHint(context),
                    icon: Ionicons.extension_puzzle_outline,
                    phoneIcon: cupertino.CupertinoIcons.cube_box,
                    enabled: false,
                    onTap: () {},
                  ),
                ],
              )
            else
              ..._buildPluginSections(context, plugins, pluginService),
          ],
        );
      },
    );
  }

  List<Widget> _buildPluginSections(
    BuildContext context,
    List<PluginDescriptor> plugins,
    PluginService pluginService,
  ) {
    final sections = <Widget>[];
    for (var index = 0; index < plugins.length; index++) {
      if (index > 0) {
        sections.add(const SizedBox(height: 12));
      }
      sections.add(
        _buildPluginSection(
          context,
          plugins[index],
          pluginService,
        ),
      );
    }
    return sections;
  }

  Widget _buildPluginSection(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) {
    return AdaptiveSettingsSection(
      key: ValueKey('plugin_settings_${plugin.manifest.id}'),
      children: [
        _buildPluginToggle(context, plugin, pluginService),
        if (plugin.uiEntries.isNotEmpty)
          _buildPluginActionTile(context, plugin),
        if (!plugin.isBuiltin)
          _buildPluginDeleteTile(context, plugin, pluginService),
      ],
    );
  }

  Widget _buildPluginToggle(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) {
    final updateVersion =
        pluginService.getAvailableUpdateVersion(plugin.manifest.id);
    return AdaptiveSettingsTile<bool>.toggle(
      title: plugin.manifest.name,
      subtitle: _pluginSubtitle(context, plugin, updateVersion),
      icon: Ionicons.extension_puzzle_outline,
      phoneIcon: cupertino.CupertinoIcons.cube_box,
      value: plugin.enabled,
      onChanged: (value) => _setPluginEnabled(
        context,
        plugin,
        pluginService,
        value,
      ),
    );
  }

  Widget _buildPluginActionTile(
    BuildContext context,
    PluginDescriptor plugin,
  ) {
    final actionEnabled = plugin.enabled && plugin.loaded;
    return AdaptiveSettingsTile<void>.card(
      title: _pluginActionTitle(context, plugin),
      subtitle: actionEnabled
          ? _pluginActionChooseHint(context)
          : _pluginActionNotAvailable(context),
      icon: Ionicons.construct_outline,
      phoneIcon: cupertino.CupertinoIcons.wrench,
      enabled: actionEnabled,
      onTap: () => _showPluginActionPicker(context, plugin),
    );
  }

  Widget _buildPluginDeleteTile(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) {
    return AdaptiveSettingsTile<void>.card(
      title: _pluginDeleteTitle(context, plugin),
      subtitle: _pluginDeleteSubtitle(context),
      icon: Ionicons.trash_outline,
      phoneIcon: cupertino.CupertinoIcons.trash,
      isDestructive: true,
      onTap: () => _confirmDeletePlugin(context, plugin, pluginService),
    );
  }

  Future<void> _checkPluginUpdates() async {
    if (!mounted || _isCheckingUpdates) return;
    setState(() {
      _isCheckingUpdates = true;
    });

    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    final pluginService = Provider.of<PluginService>(context, listen: false);
    await pluginService.fetchRemotePlugins(
      proxyUrl: settingsProvider.githubProxyUrl,
    );

    if (!mounted) return;
    setState(() {
      _isCheckingUpdates = false;
    });
  }

  Future<void> _setPluginEnabled(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
    bool value,
  ) async {
    await pluginService.setPluginEnabled(plugin.manifest.id, value);
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: value
          ? _pluginEnableToast(context, plugin.manifest.name)
          : _pluginDisableToast(context, plugin.manifest.name),
      type: AdaptiveSnackBarType.success,
    );
  }

  Future<void> _confirmDeletePlugin(
    BuildContext context,
    PluginDescriptor plugin,
    PluginService pluginService,
  ) async {
    final confirmed = AdaptiveSettingsScope.isPhoneLayout(context)
        ? await _confirmDeletePluginCupertino(context, plugin)
        : await _confirmDeletePluginMaterial(context, plugin);

    if (confirmed != true || !context.mounted) return;

    final success = await pluginService.deletePlugin(plugin.manifest.id);
    if (!context.mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: success
          ? _pluginDeleteToast(context, plugin.manifest.name)
          : _pluginDeleteFailed(context),
      type: success ? AdaptiveSnackBarType.success : AdaptiveSnackBarType.error,
    );
  }

  Future<bool?> _confirmDeletePluginMaterial(
    BuildContext context,
    PluginDescriptor plugin,
  ) {
    return BlurDialog.show<bool>(
      context: context,
      title: _confirmDeleteTitle(context),
      content: _confirmDeleteMessage(context, plugin.manifest.name),
      actions: [
        HoverScaleTextButton(
          text: context.l10n.cancel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            _deleteText(context),
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmDeletePluginCupertino(
    BuildContext context,
    PluginDescriptor plugin,
  ) {
    return cupertino.showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => cupertino.CupertinoAlertDialog(
        title: Text(_confirmDeleteTitle(context)),
        content: Text(_confirmDeleteMessage(context, plugin.manifest.name)),
        actions: [
          cupertino.CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.cancel),
          ),
          cupertino.CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(_deleteText(context)),
          ),
        ],
      ),
    );
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
        AdaptiveSnackBar.show(
          context,
          message: _importPluginCanceled(context),
          type: AdaptiveSnackBarType.info,
        );
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

  void _openPluginMarket(BuildContext context) {
    FocusScope.of(context).unfocus();
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      AdaptiveSettingsNavigation.openChildPage<void>(
        context,
        title: '插件市场',
        child: const PluginMarketDialog(embedded: true),
      );
      return;
    }
    PluginMarketDialog.show(context);
  }

  Future<void> _editProxyUrl(BuildContext context) async {
    _ensureProxyInitialized(context);
    final controller = TextEditingController(text: _proxyController.text);
    String? result;
    try {
      if (AdaptiveSettingsScope.isPhoneLayout(context)) {
        result = await _showProxyDialogCupertino(context, controller);
      } else {
        result = await _showProxyDialogMaterial(context, controller);
      }
    } finally {
      controller.dispose();
    }

    if (result == null || !context.mounted) return;
    await _applyProxyUrl(result);
  }

  Future<String?> _showProxyDialogMaterial(
    BuildContext context,
    TextEditingController controller,
  ) {
    return BlurDialog.show<String>(
      context: context,
      title: _githubProxyLabel(context),
      contentWidget: TextField(
        controller: controller,
        autofocus: true,
        cursorColor: AppAccentColors.current,
        decoration: InputDecoration(
          hintText: _githubProxyHint(context),
          errorText: _proxyUrlError,
        ),
      ),
      actions: [
        HoverScaleTextButton(
          child: Text(
            context.l10n.cancel,
            style: const TextStyle(color: Colors.white70),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          child: Text(
            _saveText(context),
            style: const TextStyle(color: Colors.lightBlueAccent),
          ),
          onPressed: () => Navigator.of(context).pop(controller.text),
        ),
      ],
    );
  }

  Future<String?> _showProxyDialogCupertino(
    BuildContext context,
    TextEditingController controller,
  ) {
    return cupertino.showCupertinoDialog<String>(
      context: context,
      builder: (dialogContext) => cupertino.CupertinoAlertDialog(
        title: Text(_githubProxyLabel(context)),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: cupertino.CupertinoTextField(
            controller: controller,
            autofocus: true,
            placeholder: _githubProxyHint(context),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          cupertino.CupertinoDialogAction(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.l10n.cancel),
          ),
          cupertino.CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(_saveText(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _applyProxyUrl(String value) async {
    if (_isProxySaving) return;
    final error = _validateProxyUrl(context, value);
    setState(() {
      _proxyUrlError = error;
    });
    if (error != null) {
      AdaptiveSnackBar.show(
        context,
        message: error,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      final settingsProvider =
          Provider.of<SettingsProvider>(context, listen: false);
      settingsProvider.setGithubProxyUrl('');
      setState(() {
        _proxyController.text = '';
      });
      AdaptiveSnackBar.show(
        context,
        message: _proxyDisabledToast(context),
        type: AdaptiveSnackBarType.success,
      );
      return;
    }

    setState(() {
      _isProxySaving = true;
    });

    final normalizedProxy = trimmed.endsWith('/') ? trimmed : '$trimmed/';
    final testUrl = '$normalizedProxy$_pluginsIndexUrl';

    try {
      final response = await http
          .get(Uri.parse(testUrl))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final settingsProvider =
            Provider.of<SettingsProvider>(context, listen: false);
        settingsProvider.setGithubProxyUrl(trimmed);
        setState(() {
          _proxyController.text = trimmed;
          _proxyUrlError = null;
        });
        AdaptiveSnackBar.show(
          context,
          message: _proxySavedToast(context),
          type: AdaptiveSnackBarType.success,
        );
      } else {
        AdaptiveSnackBar.show(
          context,
          message: _proxyRequestFailedToast(context, response.statusCode),
          type: AdaptiveSnackBarType.error,
        );
      }
    } catch (_) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: _proxyConnectFailedToast(context),
        type: AdaptiveSnackBarType.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProxySaving = false;
        });
      }
    }
  }

  Future<void> _showPluginActionPicker(
    BuildContext context,
    PluginDescriptor plugin,
  ) async {
    final entries = plugin.uiEntries;
    if (entries.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: _pluginActionNotAvailable(context),
        type: AdaptiveSnackBarType.warning,
      );
      return;
    }
    if (entries.length == 1 && entries.first.isAction) {
      await _invokePluginAction(context, plugin, entries.first);
      return;
    }

    final hasSwitches = entries.any((entry) => entry.isSwitch);
    final hasTextInputs = entries.any((entry) => entry.isTextInput);
    final hasInteractiveEntries = hasSwitches || hasTextInputs;

    if (!hasInteractiveEntries) {
      final selected = AdaptiveSettingsScope.isPhoneLayout(context)
          ? await _selectPluginActionCupertino(context, plugin, entries)
          : await _selectPluginActionMaterial(context, plugin, entries);
      if (!context.mounted || selected == null) return;
      await _invokePluginAction(context, plugin, selected);
      return;
    }

    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      await _showInteractivePluginActionsCupertino(context, plugin);
    } else {
      await _showInteractivePluginActionsMaterial(context, plugin);
    }
  }

  Future<PluginUiEntry?> _selectPluginActionMaterial(
    BuildContext context,
    PluginDescriptor plugin,
    List<PluginUiEntry> entries,
  ) {
    return GlassBottomSheet.show<PluginUiEntry>(
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
  }

  Future<PluginUiEntry?> _selectPluginActionCupertino(
    BuildContext context,
    PluginDescriptor plugin,
    List<PluginUiEntry> entries,
  ) {
    return showCupertinoModalPopupWithBottomBar<PluginUiEntry>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: Text(_pluginActionTitle(context, plugin)),
        actions: entries
            .map(
              (entry) => cupertino.CupertinoActionSheetAction(
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
                          color: cupertino.CupertinoColors.systemGrey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
            .toList(),
        cancelButton: cupertino.CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: Text(context.l10n.cancel),
        ),
      ),
    );
  }

  Future<void> _showInteractivePluginActionsMaterial(
    BuildContext context,
    PluginDescriptor plugin,
  ) {
    return GlassBottomSheet.show<void>(
      context: context,
      title: _pluginActionTitle(context, plugin),
      height: MediaQuery.of(context).size.height * 0.56,
      child: Consumer<PluginService>(
        builder: (sheetContext, pluginService, child) {
          final updatedPlugin = pluginService.plugins.firstWhere(
            (item) => item.manifest.id == plugin.manifest.id,
            orElse: () => plugin,
          );
          final currentEntries = updatedPlugin.uiEntries;
          final showBottomButtons =
              currentEntries.any((entry) => entry.isTextInput);

          final listView = ListView.builder(
            shrinkWrap: true,
            itemCount: currentEntries.length,
            itemBuilder: (itemContext, index) {
              final entry = currentEntries[index];
              if (entry.isSwitch) {
                final switchValue = pluginService.getSwitchSettingValue(
                  updatedPlugin.manifest.id,
                  entry.id,
                );
                return ListTile(
                  title: Text(entry.title),
                  subtitle: entry.description == null
                      ? null
                      : Text(entry.description!),
                  trailing: AdaptiveSettingsSwitch(
                    value: switchValue,
                    onChanged: (_) => pluginService.setSwitchSettingValue(
                      updatedPlugin.manifest.id,
                      entry.id,
                      !switchValue,
                    ),
                  ),
                  onTap: () => pluginService.setSwitchSettingValue(
                    updatedPlugin.manifest.id,
                    entry.id,
                    !switchValue,
                  ),
                );
              }
              if (entry.isTextInput) {
                final currentValue = pluginService.getTextSettingValue(
                  updatedPlugin.manifest.id,
                  entry.id,
                );
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _PluginTextSettingField(
                    key: ValueKey('${updatedPlugin.manifest.id}_${entry.id}'),
                    title: entry.title,
                    description: entry.description,
                    initialValue: currentValue,
                    hintText: entry.textSetting?.hintText,
                    onChanged: (value) {
                      pluginService.setTextSettingValue(
                        updatedPlugin.manifest.id,
                        entry.id,
                        value,
                      );
                    },
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
              Expanded(child: listView),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AdaptiveSettingsActionButton(
                      label: context.l10n.close,
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                    const SizedBox(width: 8),
                    AdaptiveSettingsActionButton(
                      label: _saveAndCloseText(context),
                      primary: true,
                      onPressed: () => Navigator.of(sheetContext).pop(),
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

  Future<void> _showInteractivePluginActionsCupertino(
    BuildContext context,
    PluginDescriptor plugin,
  ) {
    return CupertinoBottomSheet.show<void>(
      context: context,
      title: _pluginActionTitle(context, plugin),
      heightRatio: 0.56,
      child: Consumer<PluginService>(
        builder: (sheetContext, pluginService, child) {
          final updatedPlugin = pluginService.plugins.firstWhere(
            (item) => item.manifest.id == plugin.manifest.id,
            orElse: () => plugin,
          );
          final currentEntries = updatedPlugin.uiEntries;
          final showBottomButtons =
              currentEntries.any((entry) => entry.isTextInput);

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
                            (itemContext, index) {
                              final entry = currentEntries[index];
                              if (entry.isSwitch) {
                                final switchValue =
                                    pluginService.getSwitchSettingValue(
                                  updatedPlugin.manifest.id,
                                  entry.id,
                                );
                                return cupertino.CupertinoListTile(
                                  title: Text(entry.title),
                                  subtitle: entry.description == null
                                      ? null
                                      : Text(entry.description!),
                                  trailing: AdaptiveSettingsSwitch(
                                    value: switchValue,
                                    onChanged: (_) {
                                      pluginService.setSwitchSettingValue(
                                        updatedPlugin.manifest.id,
                                        entry.id,
                                        !switchValue,
                                      );
                                    },
                                  ),
                                );
                              }
                              if (entry.isTextInput) {
                                final currentValue =
                                    pluginService.getTextSettingValue(
                                  updatedPlugin.manifest.id,
                                  entry.id,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child: _PluginTextSettingField(
                                    key: ValueKey(
                                      '${updatedPlugin.manifest.id}_${entry.id}',
                                    ),
                                    title: entry.title,
                                    description: entry.description,
                                    initialValue: currentValue,
                                    hintText: entry.textSetting?.hintText,
                                    useCupertino: true,
                                    onChanged: (value) {
                                      pluginService.setTextSettingValue(
                                        updatedPlugin.manifest.id,
                                        entry.id,
                                        value,
                                      );
                                    },
                                  ),
                                );
                              }
                              return cupertino.CupertinoListTile(
                                title: Text(entry.title),
                                subtitle: entry.description == null
                                    ? null
                                    : Text(entry.description!),
                                trailing:
                                    const cupertino.CupertinoListTileChevron(),
                                onTap: () async {
                                  Navigator.of(contentContext).pop();
                                  if (!context.mounted) return;
                                  await _invokePluginAction(
                                    context,
                                    updatedPlugin,
                                    entry,
                                  );
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
                        cupertino.CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(context.l10n.close),
                        ),
                        const SizedBox(width: 8),
                        cupertino.CupertinoButton.filled(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          child: Text(_saveAndCloseText(context)),
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
      if (!context.mounted) return;
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
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
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
                    style: cupertino.CupertinoTheme.of(context)
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
      return;
    }

    await GlassBottomSheet.show<void>(
      context: context,
      title: result.title,
      height: MediaQuery.of(context).size.height * 0.64,
      child: SelectableText(content),
    );
  }

  void _ensureProxyInitialized(BuildContext context) {
    if (_proxyInitialized) return;
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    _proxyController.text = settingsProvider.githubProxyUrl;
    _proxyInitialized = true;
  }

  String _proxySubtitle(BuildContext context) {
    _ensureProxyInitialized(context);
    if (_isProxySaving) return _proxySavingText(context);
    if (_proxyUrlError != null) return _proxyUrlError!;
    final value = _proxyController.text.trim();
    if (value.isEmpty) return _githubProxyHint(context);
    return value;
  }

  String? _validateProxyUrl(BuildContext context, String? url) {
    if (url == null || url.trim().isEmpty) {
      return null;
    }
    final trimmed = url.trim();
    if (!trimmed.startsWith('https://') && !trimmed.startsWith('http://')) {
      return _text(
        context,
        'URL必须以 http:// 或 https:// 开头',
        'URL必須以 http:// 或 https:// 開頭',
        'URL must start with http:// or https://',
      );
    }
    if (!trimmed.endsWith('/')) {
      return _text(
        context,
        'URL必须以 / 结尾',
        'URL必須以 / 結尾',
        'URL must end with /',
      );
    }
    try {
      final uri = Uri.parse(trimmed);
      if (!uri.hasScheme || !uri.hasAuthority) {
        return _invalidUrlText(context);
      }
    } catch (_) {
      return _invalidUrlText(context);
    }
    return null;
  }

  String _pluginSubtitle(
    BuildContext context,
    PluginDescriptor plugin,
    String? updateVersion,
  ) {
    final subtitle = StringBuffer()
      ..write('v${plugin.manifest.version} · ${plugin.manifest.author}');
    if (updateVersion != null) {
      subtitle
        ..write('\n')
        ..write(_pluginUpdateAvailable(context, updateVersion));
    }
    if (plugin.manifest.description.isNotEmpty) {
      subtitle
        ..write('\n')
        ..write(plugin.manifest.description);
    }
    if (plugin.manifest.github != null && plugin.manifest.github!.isNotEmpty) {
      subtitle
        ..write('\nGitHub: ')
        ..write(plugin.manifest.github);
    }
    if (plugin.errorMessage != null && plugin.errorMessage!.isNotEmpty) {
      subtitle
        ..write('\n')
        ..write(_pluginLoadFailed(context, plugin.errorMessage!));
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

  String _importPluginTitle(BuildContext context) =>
      _text(context, '导入插件', '導入插件', 'Import Plugin');

  String _importPluginHint(BuildContext context) =>
      _text(context, '从本机选择 .js 文件', '從本機選擇 .js 檔案', 'Choose a local .js file');

  String _pluginMarketTitle(BuildContext context) =>
      _text(context, '插件市场', '插件市場', 'Plugin Market');

  String _pluginMarketSubtitle(BuildContext context) => _text(
        context,
        '浏览、安装或更新远程插件',
        '瀏覽、安裝或更新遠端插件',
        'Browse, install, or update remote plugins.',
      );

  String _githubProxyLabel(BuildContext context) =>
      _text(context, 'GitHub 加速', 'GitHub 加速', 'GitHub Proxy');

  String _githubProxyHint(BuildContext context) => _text(
        context,
        '请输入加速源地址，留空不启用',
        '請輸入加速源地址，留空不啟用',
        'Enter a proxy URL, or leave empty to disable.',
      );

  String _checkingUpdatesTitle(BuildContext context) => _isCheckingUpdates
      ? _text(context, '正在检查插件更新', '正在檢查插件更新', 'Checking Plugin Updates')
      : _text(context, '检查插件更新', '檢查插件更新', 'Check Plugin Updates');

  String _checkingUpdatesSubtitle(BuildContext context) => _text(
        context,
        '从插件索引刷新可用更新信息',
        '從插件索引重新整理可用更新資訊',
        'Refresh available updates from the plugin index.',
      );

  String _pluginsEmpty(BuildContext context) =>
      _text(context, '暂无可用插件', '暫無可用插件', 'No Plugins Available');

  String _pluginsEmptyHint(BuildContext context) => _text(
        context,
        '可以导入本地插件，或从插件市场安装',
        '可以導入本機插件，或從插件市場安裝',
        'Import a local plugin or install one from the plugin market.',
      );

  String _pluginActionTitle(BuildContext context, PluginDescriptor plugin) =>
      _text(context, '配置 ${plugin.manifest.name}', '配置 ${plugin.manifest.name}',
          'Configure ${plugin.manifest.name}');

  String _pluginActionChooseHint(BuildContext context) => _text(
        context,
        '选择要打开的插件功能',
        '選擇要開啟的插件功能',
        'Choose a plugin action to open.',
      );

  String _pluginActionNotAvailable(BuildContext context) => _text(
        context,
        '需先启用并加载插件',
        '需先啟用並載入插件',
        'Enable and load the plugin first.',
      );

  String _pluginActionNotLoaded(BuildContext context) => _text(
        context,
        '插件尚未就绪，请稍后重试',
        '插件尚未就緒，請稍後重試',
        'The plugin is not ready yet. Try again later.',
      );

  String _pluginActionEmpty(BuildContext context) =>
      _text(context, '插件未返回内容', '插件未返回內容', 'The plugin returned no content.');

  String _pluginActionError(BuildContext context, Object error) => _text(
        context,
        '插件操作失败：$error',
        '插件操作失敗：$error',
        'Plugin action failed: $error',
      );

  String _pluginActionContentFallback(BuildContext context) =>
      _text(context, '（无可显示内容）', '（無可顯示內容）', '(No content to display)');

  String _pluginDeleteTitle(BuildContext context, PluginDescriptor plugin) =>
      _text(context, '删除 ${plugin.manifest.name}', '刪除 ${plugin.manifest.name}',
          'Delete ${plugin.manifest.name}');

  String _pluginDeleteSubtitle(BuildContext context) =>
      _text(context, '从本机移除此插件', '從本機移除此插件', 'Remove this plugin locally.');

  String _confirmDeleteTitle(BuildContext context) =>
      _text(context, '确认删除', '確認刪除', 'Confirm Delete');

  String _confirmDeleteMessage(BuildContext context, String pluginName) =>
      _text(
        context,
        '确定要删除插件「$pluginName」吗？此操作不可撤销。',
        '確定要刪除插件「$pluginName」嗎？此操作不可復原。',
        'Delete "$pluginName"? This cannot be undone.',
      );

  String _deleteText(BuildContext context) =>
      _text(context, '删除', '刪除', 'Delete');

  String _saveText(BuildContext context) => _text(context, '保存', '儲存', 'Save');

  String _saveAndCloseText(BuildContext context) =>
      _text(context, '保存并关闭', '儲存並關閉', 'Save and Close');

  String _proxySavingText(BuildContext context) =>
      _text(context, '正在验证加速源...', '正在驗證加速源...', 'Verifying proxy...');

  String _invalidUrlText(BuildContext context) =>
      _text(context, 'URL格式无效', 'URL格式無效', 'Invalid URL format');

  String _proxySavedToast(BuildContext context) =>
      _text(context, '加速源验证通过，已保存', '加速源驗證通過，已儲存', 'Proxy verified and saved.');

  String _proxyDisabledToast(BuildContext context) => _text(
      context, '已关闭 GitHub 加速', '已關閉 GitHub 加速', 'GitHub proxy disabled.');

  String _proxyRequestFailedToast(BuildContext context, int statusCode) =>
      _text(context, '加速源请求失败 ($statusCode)', '加速源請求失敗 ($statusCode)',
          'Proxy request failed ($statusCode).');

  String _proxyConnectFailedToast(BuildContext context) => _text(
        context,
        '加速源连接失败，请检查地址',
        '加速源連線失敗，請檢查地址',
        'Proxy connection failed. Check the URL.',
      );

  String _pluginEnableToast(BuildContext context, String name) =>
      _text(context, '已启用插件：$name', '已啟用插件：$name', 'Plugin enabled: $name');

  String _pluginDisableToast(BuildContext context, String name) =>
      _text(context, '已禁用插件：$name', '已停用插件：$name', 'Plugin disabled: $name');

  String _pluginDeleteToast(BuildContext context, String name) =>
      _text(context, '已删除插件：$name', '已刪除插件：$name', 'Plugin deleted: $name');

  String _pluginDeleteFailed(BuildContext context) => _text(
      context, '内置插件无法删除', '內建插件無法刪除', 'Built-in plugins cannot be deleted.');

  String _importPluginSuccess(BuildContext context, String pluginId) => _text(
      context,
      '插件导入成功：$pluginId',
      '插件導入成功：$pluginId',
      'Plugin imported: $pluginId');

  String _importPluginFailed(BuildContext context, Object error) => _text(
        context,
        '导入插件失败：$error',
        '導入插件失敗：$error',
        'Failed to import plugin: $error',
      );

  String _importPluginCanceled(BuildContext context) =>
      _text(context, '已取消导入插件', '已取消導入插件', 'Plugin import canceled.');

  String _pluginUpdateAvailable(BuildContext context, String version) => _text(
      context, '有更新 v$version', '有更新 v$version', 'Update available: v$version');

  String _pluginLoadFailed(BuildContext context, String error) =>
      _text(context, '加载失败: $error', '載入失敗: $error', 'Load failed: $error');

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') {
      return english;
    }
    if (locale == 'zh_Hant') {
      return traditional;
    }
    return simplified;
  }
}

class _PluginTextSettingField extends StatefulWidget {
  const _PluginTextSettingField({
    super.key,
    required this.title,
    required this.initialValue,
    required this.onChanged,
    this.description,
    this.hintText,
    this.useCupertino = false,
  });

  final String title;
  final String? description;
  final String initialValue;
  final String? hintText;
  final ValueChanged<String> onChanged;
  final bool useCupertino;

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
    final description = widget.description;
    final title = Text(
      widget.title,
      style: const TextStyle(
        fontWeight: FontWeight.w600,
        fontSize: 15,
      ),
    );
    final subtitle = description == null || description.trim().isEmpty
        ? null
        : Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: widget.useCupertino
                  ? cupertino.CupertinoColors.systemGrey
                  : Theme.of(context).colorScheme.onSurface.withValues(
                        alpha: 0.6,
                      ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          subtitle,
        ],
        const SizedBox(height: 8),
        if (widget.useCupertino)
          cupertino.CupertinoTextField(
            controller: _controller,
            placeholder: widget.hintText,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onChanged: widget.onChanged,
          )
        else
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: widget.hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
            ),
            onChanged: widget.onChanged,
          ),
      ],
    );
  }
}
