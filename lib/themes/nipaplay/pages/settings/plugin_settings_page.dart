import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/plugins/models/plugin_descriptor.dart';
import 'package:nipaplay/plugins/models/plugin_ui_action_result.dart';
import 'package:nipaplay/plugins/models/plugin_ui_entry.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/glass_bottom_sheet.dart';
import 'package:provider/provider.dart';

class PluginSettingsPage extends StatelessWidget {
  const PluginSettingsPage({super.key});

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

  String _pluginsEmpty(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '暫無可用插件';
    }
    return '暂无可用插件';
  }

  String _pluginActionTitle(BuildContext context, PluginDescriptor plugin) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '${plugin.manifest.name}：可用操作';
    }
    return '${plugin.manifest.name}：可用操作';
  }

  String _pluginActionNotAvailable(BuildContext context) {
    if (context.l10n.localeName.startsWith('zh_Hant')) {
      return '僅在插件啟用且正常加載後可使用';
    }
    return '仅在插件启用且正常加载后可用';
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
      return;
    }
    if (entries.length == 1) {
      await _invokePluginAction(context, plugin, entries.first);
      return;
    }

    final selected = await GlassBottomSheet.show<PluginUiEntry>(
      context: context,
      title: _pluginActionTitle(context, plugin),
      height: MediaQuery.of(context).size.height * 0.56,
      child: ListView.builder(
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
    if (!context.mounted || selected == null) {
      return;
    }
    await _invokePluginAction(context, plugin, selected);
  }

  Future<void> _invokePluginAction(
    BuildContext context,
    PluginDescriptor plugin,
    PluginUiEntry entry,
  ) async {
    final pluginService = context.read<PluginService>();
    if (!plugin.enabled || !plugin.loaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pluginActionNotLoaded(context))),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_pluginActionEmpty(context))),
        );
        return;
      }
      await _showPluginActionResult(context, result);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_pluginActionError(context, error))),
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
    final colorScheme = Theme.of(context).colorScheme;
    final actionEnabled =
        plugin.enabled && plugin.loaded && plugin.uiEntries.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: actionEnabled
              ? _pluginActionTitle(context, plugin)
              : _pluginActionNotAvailable(context),
          icon: Icon(
            Icons.handyman,
            color: actionEnabled
                ? colorScheme.primary
                : colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          onPressed: actionEnabled
              ? () => _showPluginActionPicker(context, plugin)
              : null,
        ),
        Transform.scale(
          scale: 0.9,
          child: Switch(
            value: plugin.enabled,
            onChanged: (value) async {
              await pluginService.setPluginEnabled(plugin.manifest.id, value);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    value
                        ? _pluginEnableToast(context, plugin.manifest.name)
                        : _pluginDisableToast(context, plugin.manifest.name),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
          return Center(
            child: Text(_pluginsEmpty(context)),
          );
        }

        final items = <Widget>[];
        for (var i = 0; i < plugins.length; i++) {
          final plugin = plugins[i];

          items.add(
            ListTile(
              leading: Icon(
                Ionicons.extension_puzzle_outline,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              title: Text(
                plugin.manifest.name,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      target
                          ? _pluginEnableToast(context, plugin.manifest.name)
                          : _pluginDisableToast(context, plugin.manifest.name),
                    ),
                  ),
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
            ...items,
          ],
        );
      },
    );
  }
}
