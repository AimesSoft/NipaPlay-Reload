import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';

class SharedRemoteLibrarySettingsSection extends StatelessWidget {
  const SharedRemoteLibrarySettingsSection({super.key});

  static const Color _accentColor = Color(0xFFFF2E55);

  @override
  Widget build(BuildContext context) {
    return Consumer<SharedRemoteLibraryProvider>(
      builder: (context, provider, child) {
        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      colorScheme.onSurface,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      'assets/nipaplay.png',
                      width: 20,
                      height: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'NipaPlay 局域网媒体共享',
                  locale: const Locale('zh', 'CN'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '在另一台设备（手机/平板/电脑等客户端）开启远程访问后，填写其局域网地址即可直接浏览并播放它的本地媒体库。',
              locale: const Locale('zh', 'CN'),
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            if (provider.isInitializing)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              )
            else if (provider.hosts.isEmpty)
              _buildEmptyState(context, provider)
            else
              _buildHostList(context, provider),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, SharedRemoteLibraryProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(Icons.info_outline, color: colorScheme.onSurface.withOpacity(0.6)),
        const SizedBox(height: 8),
        Text(
          '尚未添加任何共享客户端',
          locale: const Locale('zh', 'CN'),
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: _buildGlassButton(
            context: context,
            onPressed: () => _showAddHostDialog(context, provider),
            icon: Icons.add,
            label: '新增客户端',
          ),
        ),
      ],
    );
  }

  Widget _buildHostList(BuildContext context, SharedRemoteLibraryProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ...provider.hosts.map((host) {
        final isActive = provider.activeHostId == host.id;
        final statusColor = host.isOnline ? Colors.green : Colors.orange;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    host.isOnline ? Icons.check_circle : Icons.pending_outlined,
                    color: statusColor,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      host.displayName.isNotEmpty ? host.displayName : host.baseUrl,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (!isActive)
                    HoverScaleTextButton(
                      text: '设为当前',
                      idleColor: colorScheme.onSurface.withOpacity(0.7),
                      hoverColor: _accentColor,
                      onPressed: () => provider.setActiveHost(host.id),
                    )
                  else
                    Text(
                      '当前使用',
                      locale: const Locale('zh', 'CN'),
                      style: TextStyle(
                        color: _accentColor,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SelectableText(
                host.baseUrl,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                  fontSize: 13,
                ),
              ),
              if (host.lastError != null && host.lastError!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  host.lastError!,
                  locale: const Locale('zh', 'CN'),
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  HoverScaleTextButton(
                    text: '刷新',
                    idleColor: _accentColor,
                    hoverColor: _accentColor,
                    onPressed: () =>
                        provider.refreshLibrary(userInitiated: true),
                  ),
                  HoverScaleTextButton(
                    text: '重命名',
                    idleColor: _accentColor,
                    hoverColor: _accentColor,
                    onPressed: () => _showRenameDialog(
                      context,
                      provider,
                      host.id,
                      host.displayName,
                    ),
                  ),
                  HoverScaleTextButton(
                    text: '修改地址',
                    idleColor: _accentColor,
                    hoverColor: _accentColor,
                    onPressed: () => _showUpdateUrlDialog(
                      context,
                      provider,
                      host.id,
                      host.baseUrl,
                    ),
                  ),
                  const Spacer(),
                  HoverScaleTextButton(
                    text: '删除',
                    idleColor: _accentColor,
                    hoverColor: _accentColor,
                    onPressed: () => _confirmRemoveHost(
                      context,
                      provider,
                      host.id,
                    ),
                  ),
                ],
              ),
              Divider(
                color: colorScheme.onSurface.withOpacity(0.12),
                height: 16,
              ),
            ],
          ),
        );
      }).toList(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _buildGlassButton(
            context: context,
            onPressed: () => _showAddHostDialog(context, provider),
            icon: Icons.add,
            label: '新增客户端',
          ),
        ),
      ],
    );
  }

  Future<void> _showAddHostDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    await BlurLoginDialog.show(
      context,
      title: '添加共享客户端',
      fields: [
        LoginField(
          key: 'displayName',
          label: '备注名称',
          hint: '例如：家里的电脑',
          required: false,
        ),
        LoginField(
          key: 'baseUrl',
          label: '访问地址',
          hint: '例如：192.168.1.100（默认1180）或 192.168.1.100:2345',
        ),
      ],
      loginButtonText: '添加',
      onLogin: (values) async {
        try {
          final displayName = values['displayName']?.trim().isEmpty ?? true
              ? values['baseUrl']!.trim()
              : values['displayName']!.trim();

          await provider.addHost(
            displayName: displayName,
            baseUrl: values['baseUrl']!.trim(),
          );

          return LoginResult(
            success: true,
            message: '已添加共享客户端',
          );
        } catch (e) {
          return LoginResult(
            success: false,
            message: '添加失败：$e',
          );
        }
      },
    );
  }

  Future<void> _confirmRemoveHost(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryTextColor = colorScheme.onSurface.withOpacity(0.7);
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '删除共享客户端',
      content: '确定要删除该客户端吗？',
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          text: '取消',
          idleColor: secondaryTextColor,
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          text: '删除',
          idleColor: colorScheme.error,
          hoverColor: colorScheme.error,
        ),
      ],
    );

    if (confirm == true) {
      await provider.removeHost(hostId);
      BlurSnackBar.show(context, '已删除共享客户端');
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = colorScheme.onSurface.withOpacity(0.7);
    final hintColor = colorScheme.onSurface.withOpacity(0.5);
    final borderColor =
        colorScheme.onSurface.withOpacity(isDark ? 0.25 : 0.2);
    final selectionTheme = TextSelectionThemeData(
      cursorColor: _accentColor,
      selectionColor: _accentColor.withOpacity(0.3),
      selectionHandleColor: _accentColor,
    );
    final confirmed = await BlurDialog.show<bool>(
      context: context,
      title: '重命名',
      contentWidget: TextSelectionTheme(
        data: selectionTheme,
        child: TextField(
          controller: controller,
          cursorColor: _accentColor,
          decoration: InputDecoration(
            labelText: '备注名称',
            labelStyle: TextStyle(color: secondaryTextColor),
            hintStyle: TextStyle(color: hintColor),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _accentColor),
            ),
          ),
          style: const TextStyle(color: _accentColor),
        ),
      ),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          text: '取消',
          idleColor: secondaryTextColor,
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          text: '保存',
          idleColor: colorScheme.onSurface,
        ),
      ],
    );

    if (confirmed == true) {
      await provider.renameHost(hostId, controller.text.trim());
      BlurSnackBar.show(context, '名称已更新');
    }
  }

  Future<void> _showUpdateUrlDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    String hostId,
    String currentUrl,
  ) async {
    final controller = TextEditingController(text: currentUrl);
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryTextColor = colorScheme.onSurface.withOpacity(0.7);
    final hintColor = colorScheme.onSurface.withOpacity(0.5);
    final borderColor =
        colorScheme.onSurface.withOpacity(isDark ? 0.25 : 0.2);
    final selectionTheme = TextSelectionThemeData(
      cursorColor: _accentColor,
      selectionColor: _accentColor.withOpacity(0.3),
      selectionHandleColor: _accentColor,
    );
    final confirmed = await BlurDialog.show<bool>(
      context: context,
      title: '修改访问地址',
      contentWidget: TextSelectionTheme(
        data: selectionTheme,
        child: TextField(
          controller: controller,
          cursorColor: _accentColor,
          decoration: InputDecoration(
            labelText: '访问地址',
            labelStyle: TextStyle(color: secondaryTextColor),
            hintStyle: TextStyle(color: hintColor),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: _accentColor),
            ),
          ),
          style: const TextStyle(color: _accentColor),
        ),
      ),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          text: '取消',
          idleColor: secondaryTextColor,
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          text: '保存',
          idleColor: colorScheme.onSurface,
        ),
      ],
    );

    if (confirmed == true) {
      await provider.updateHostUrl(hostId, controller.text.trim());
      BlurSnackBar.show(context, '地址已更新');
    }
  }

  Widget _buildGlassButton({
    required BuildContext context,
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.onSurface.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: colorScheme.onSurface, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
