import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/network_media_server_dialog.dart';

class FluentRemoteMediaLibraryPage extends StatelessWidget {
  const FluentRemoteMediaLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(title: Text('远程媒体库')),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Consumer2<JellyfinProvider, EmbyProvider>(
          builder: (context, jellyfinProvider, embyProvider, child) {
            if (!jellyfinProvider.isInitialized && !embyProvider.isInitialized) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressRing(),
                    SizedBox(height: 12),
                    Text('正在初始化远程媒体库服务...'),
                  ],
                ),
              );
            }

            final hasJellyfinError = jellyfinProvider.hasError &&
                jellyfinProvider.errorMessage != null &&
                !jellyfinProvider.isConnected;
            final hasEmbyError = embyProvider.hasError &&
                embyProvider.errorMessage != null &&
                !embyProvider.isConnected;

            return ListView(
              children: [
                if (hasJellyfinError || hasEmbyError) ...[
                  _ErrorCard(jellyfinProvider: jellyfinProvider, embyProvider: embyProvider),
                  const SizedBox(height: 20),
                ],
                _JellyfinSection(provider: jellyfinProvider),
                const SizedBox(height: 20),
                _EmbySection(provider: embyProvider),
                const SizedBox(height: 20),
                const _SharedLibrarySection(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final JellyfinProvider jellyfinProvider;
  final EmbyProvider embyProvider;

  const _ErrorCard({
    required this.jellyfinProvider,
    required this.embyProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.status_error_full, color: Color(0xFFD13438)),
                const SizedBox(width: 8),
                Text(
                  '服务初始化错误',
                  style: FluentTheme.of(context)
                      .typography
                      .subtitle
                      ?.copyWith(color: const Color(0xFFD13438), fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (jellyfinProvider.hasError && jellyfinProvider.errorMessage != null)
              _buildErrorItem('Jellyfin', jellyfinProvider.errorMessage!, context),
            if (embyProvider.hasError && embyProvider.errorMessage != null) ...[
              const SizedBox(height: 8),
              _buildErrorItem('Emby', embyProvider.errorMessage!, context),
            ],
            const SizedBox(height: 12),
            InfoBar(
              title: const Text('提示'),
              content: const Text('这些错误不会影响其他功能的正常使用。您可以稍后重新配置服务器连接。'),
              severity: InfoBarSeverity.warning,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorItem(String serviceName, String message, BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDE7E9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFD13438).withOpacity(0.4), width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            serviceName,
            style: FluentTheme.of(context)
                .typography
                .bodyStrong
                ?.copyWith(color: const Color(0xFFD13438)),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style:
                FluentTheme.of(context).typography.caption?.copyWith(color: const Color(0xFFD13438)),
          ),
        ],
      ),
    );
  }
}

class _JellyfinSection extends StatelessWidget {
  final JellyfinProvider provider;

  const _JellyfinSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ServiceIcon(asset: 'assets/jellyfin.svg'),
                const SizedBox(width: 12),
                Text(
                  'Jellyfin 媒体服务器',
                  style: FluentTheme.of(context)
                      .typography
                      .subtitle
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (provider.isConnected)
                  InfoBadge(
                    color: const Color(0xFF107C10),
                    source: const Text('已连接'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!provider.isConnected)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jellyfin 是一个免费的媒体服务器软件，可在任何设备上浏览和流式播放您的收藏。',
                    style: FluentTheme.of(context).typography.body,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _showServerDialog(context, MediaServerType.jellyfin),
                    child: const Text('连接 Jellyfin 服务器'),
                  ),
                ],
              )
            else
              _ConnectedServerView(
                serverUrl: provider.serverUrl ?? '未知',
                username: provider.username ?? '匿名',
                selectedLibraries: provider.selectedLibraryIds.toList(),
                availableLibraries: provider.availableLibraries
                    .map((lib) => lib.name)
                    .toList(),
                onManagePressed: () => _showServerDialog(context, MediaServerType.jellyfin),
                onDisconnectPressed: () => _disconnectServer(context, provider),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showServerDialog(BuildContext context, MediaServerType type) async {
    final result = await NetworkMediaServerDialog.show(context, type);
    if (result == true && context.mounted) {
      _showInfoBar(
        context,
        '${type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby'} 服务器设置已更新',
        severity: InfoBarSeverity.success,
      );
    }
  }

  Future<void> _disconnectServer(BuildContext context, JellyfinProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('断开连接'),
          content: const Text('确定要断开与 Jellyfin 服务器的连接吗？这将清除服务器信息和登录状态。'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('断开连接'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await provider.disconnectFromServer();
        if (context.mounted) {
          _showInfoBar(context, '已断开与 Jellyfin 服务器的连接',
              severity: InfoBarSeverity.warning);
        }
      } catch (e) {
        if (context.mounted) {
          _showInfoBar(context, '断开连接失败: $e', severity: InfoBarSeverity.error);
        }
      }
    }
  }
}

class _EmbySection extends StatelessWidget {
  final EmbyProvider provider;

  const _EmbySection({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _ServiceIcon(asset: 'assets/emby.svg'),
                const SizedBox(width: 12),
                Text(
                  'Emby 媒体服务器',
                  style: FluentTheme.of(context)
                      .typography
                      .subtitle
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (provider.isConnected)
                  InfoBadge(
                    color: const Color(0xFF52B54B),
                    source: const Text('已连接'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!provider.isConnected)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emby 是一款强大的个人媒体服务器，支持在任意设备组织与播放媒体。',
                    style: FluentTheme.of(context).typography.body,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => _showServerDialog(context, MediaServerType.emby),
                    child: const Text('连接 Emby 服务器'),
                  ),
                ],
              )
            else
              _ConnectedServerView(
                serverUrl: provider.serverUrl ?? '未知',
                username: provider.username ?? '匿名',
                selectedLibraries: provider.selectedLibraryIds.toList(),
                availableLibraries: provider.availableLibraries
                    .map((lib) => lib.name)
                    .toList(),
                onManagePressed: () => _showServerDialog(context, MediaServerType.emby),
                onDisconnectPressed: () => _disconnectServer(context, provider),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showServerDialog(BuildContext context, MediaServerType type) async {
    final result = await NetworkMediaServerDialog.show(context, type);
    if (result == true && context.mounted) {
      _showInfoBar(
        context,
        '${type == MediaServerType.jellyfin ? 'Jellyfin' : 'Emby'} 服务器设置已更新',
        severity: InfoBarSeverity.success,
      );
    }
  }

  Future<void> _disconnectServer(BuildContext context, EmbyProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('断开连接'),
          content: const Text('确定要断开与 Emby 服务器的连接吗？这将清除服务器信息和登录状态。'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('断开连接'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      try {
        await provider.disconnectFromServer();
        if (context.mounted) {
          _showInfoBar(context, '已断开与 Emby 服务器的连接',
              severity: InfoBarSeverity.warning);
        }
      } catch (e) {
        if (context.mounted) {
          _showInfoBar(context, '断开连接失败: $e', severity: InfoBarSeverity.error);
        }
      }
    }
  }
}

class _ConnectedServerView extends StatelessWidget {
  final String serverUrl;
  final String username;
  final List<String> selectedLibraries;
  final List<String> availableLibraries;
  final VoidCallback onManagePressed;
  final VoidCallback onDisconnectPressed;

  const _ConnectedServerView({
    required this.serverUrl,
    required this.username,
    required this.selectedLibraries,
    required this.availableLibraries,
    required this.onManagePressed,
    required this.onDisconnectPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InfoTile(
          icon: FluentIcons.server,
          label: '服务器',
          value: serverUrl,
        ),
        const SizedBox(height: 8),
        _InfoTile(
          icon: FluentIcons.contact,
          label: '用户',
          value: username,
        ),
        const SizedBox(height: 12),
        _LibrarySummary(
          selectedLibraries: selectedLibraries,
          availableLibraries: availableLibraries,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: onManagePressed,
              child: const Text('管理服务器'),
            ),
            const SizedBox(width: 12),
            Button(
              onPressed: onDisconnectPressed,
              child: const Text('断开连接'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LibrarySummary extends StatelessWidget {
  final List<String> selectedLibraries;
  final List<String> availableLibraries;

  const _LibrarySummary({
    required this.selectedLibraries,
    required this.availableLibraries,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(FluentIcons.library, size: 16),
            const SizedBox(width: 8),
            Text(
              '媒体库：已选择 ${selectedLibraries.length} / ${availableLibraries.length}',
              style: theme.typography.body,
            ),
          ],
        ),
        if (selectedLibraries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: selectedLibraries
                  .map((name) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.accentColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          name,
                          style: theme.typography.caption?.copyWith(color: theme.accentColor),
                        ),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class _SharedLibrarySection extends StatelessWidget {
  const _SharedLibrarySection();

  @override
  Widget build(BuildContext context) {
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(FluentIcons.plug_connected),
                    const SizedBox(width: 8),
                    Text(
                      'NipaPlay 局域网媒体共享',
                      style: FluentTheme.of(context)
                          .typography
                          .subtitle
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Button(
                      onPressed: provider.refreshLibrary,
                      child: const Text('刷新'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '在另一台设备开启远程访问后，填写其局域网地址即可直接浏览并播放它的本地媒体库。',
                  style: FluentTheme.of(context).typography.body,
                ),
                const SizedBox(height: 16),
                if (provider.isInitializing)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: ProgressRing(),
                    ),
                  )
                else if (provider.hosts.isEmpty)
                  _EmptySharedHostView(onAddPressed: () => _showAddHostDialog(context, provider))
                else
                  Column(
                    children: [
                      ...provider.hosts.map(
                        (host) => _SharedHostTile(
                          host: host,
                          isActive: provider.activeHostId == host.id,
                          onSetActive: () => provider.setActiveHost(host.id),
                          onRename: () => _showRenameDialog(context, provider, host.id, host.displayName),
                          onUpdateUrl: () => _showUpdateUrlDialog(context, provider, host.id, host.baseUrl),
                          onRemove: () => _confirmRemoveHost(context, provider, host.id),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Button(
                        onPressed: () => _showAddHostDialog(context, provider),
                        child: const Text('新增客户端'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showAddHostDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('新增共享客户端'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextBox(
                placeholder: '显示名称',
                controller: nameController,
              ),
              const SizedBox(height: 12),
              TextBox(
                placeholder: '访问地址 (如 http://192.168.1.50:8080)',
                controller: urlController,
              ),
            ],
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (urlController.text.trim().isEmpty) {
                  _showInfoBar(context, '请输入有效的地址', severity: InfoBarSeverity.warning);
                  return;
                }
                await provider.addHost(
                  displayName: nameController.text.trim().isEmpty
                      ? '共享主机'
                      : nameController.text.trim(),
                  baseUrl: urlController.text.trim(),
                );
                if (context.mounted) {
                  _showInfoBar(context, '已添加新的共享客户端', severity: InfoBarSeverity.success);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('添加'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showRenameDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('重命名客户端'),
          content: TextBox(
            placeholder: '显示名称',
            controller: controller,
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) {
                  _showInfoBar(context, '名称不能为空', severity: InfoBarSeverity.warning);
                  return;
                }
                await provider.renameHost(hostId, controller.text.trim());
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showUpdateUrlDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
    String currentUrl,
  ) async {
    final controller = TextEditingController(text: currentUrl);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('更新访问地址'),
          content: TextBox(
            placeholder: '访问地址',
            controller: controller,
          ),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.text.trim().isEmpty) {
                  _showInfoBar(context, '地址不能为空', severity: InfoBarSeverity.warning);
                  return;
                }
                await provider.updateHostUrl(hostId, controller.text.trim());
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _confirmRemoveHost(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return ContentDialog(
          title: const Text('删除共享客户端'),
          content: const Text('确定要删除该共享客户端吗？'),
          actions: [
            Button(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await provider.removeHost(hostId);
      if (context.mounted) {
        _showInfoBar(context, '已删除共享客户端', severity: InfoBarSeverity.warning);
      }
    }
  }
}

class _SharedHostTile extends StatelessWidget {
  final SharedRemoteHost host;
  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onRename;
  final VoidCallback onUpdateUrl;
  final VoidCallback onRemove;

  const _SharedHostTile({
    required this.host,
    required this.isActive,
    required this.onSetActive,
    required this.onRename,
    required this.onUpdateUrl,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive
              ? theme.accentColor.withOpacity(0.5)
              : theme.resources.controlStrokeColorDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                host.isOnline ? FluentIcons.wifi : FluentIcons.plug_disconnected,
                color: host.isOnline
                    ? const Color(0xFF107C10)
                    : const Color(0xFFD83B01),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  host.displayName.isNotEmpty ? host.displayName : host.baseUrl,
                  style: theme.typography.bodyStrong,
                ),
              ),
              if (isActive)
                InfoBadge(color: theme.accentColor, source: const Text('当前'))
              else
                Button(
                  onPressed: onSetActive,
                  child: const Text('设为当前'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            host.baseUrl,
            style: theme.typography.caption,
          ),
          if (host.lastError != null && host.lastError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(host.lastError!,
                style:
                    theme.typography.caption?.copyWith(color: const Color(0xFFD83B01))),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Button(onPressed: onRename, child: const Text('重命名')),
              Button(onPressed: onUpdateUrl, child: const Text('修改地址')),
              Button(
                style: ButtonStyle(
                  foregroundColor: ButtonState.all(const Color(0xFFD13438)),
                ),
                onPressed: onRemove,
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptySharedHostView extends StatelessWidget {
  final VoidCallback onAddPressed;

  const _EmptySharedHostView({required this.onAddPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: const [
                Icon(FluentIcons.info, size: 24),
                SizedBox(height: 8),
                Text('尚未添加任何共享客户端'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: onAddPressed,
          child: const Text('新增客户端'),
        ),
      ],
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  final String asset;

  const _ServiceIcon({required this.asset});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: SvgPicture.asset(
        asset,
        colorFilter: ColorFilter.mode(
          FluentTheme.of(context).accentColor,
          BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor.withOpacity(0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text('$label:', style: theme.typography.caption),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              value,
              style: theme.typography.body,
            ),
          ),
        ],
      ),
    );
  }
}

void _showInfoBar(
  BuildContext context,
  String message, {
  InfoBarSeverity severity = InfoBarSeverity.info,
}) {
  displayInfoBar(
    context,
    builder: (context, close) => InfoBar(
      title: Text(_infoBarTitle(severity)),
      severity: severity,
      content: Text(message),
      action: IconButton(
        icon: const Icon(FluentIcons.clear),
        onPressed: close,
      ),
    ),
  );
}

String _infoBarTitle(InfoBarSeverity severity) {
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
