import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

class SharedRemoteHostSelectionSheet extends StatelessWidget {
  const SharedRemoteHostSelectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    final enableAnimation = Provider.of<AppearanceSettingsProvider>(
      context,
      listen: false,
    ).enablePageAnimation;

    return NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      child: const SharedRemoteHostSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SharedRemoteLibraryProvider>();
    final hosts = provider.hosts;
    final screenSize = MediaQuery.of(context).size;
    final baseDialogWidth = globals.DialogSizes.getDialogWidth(screenSize.width);
    final bool useWideDialog =
        globals.isDesktopOrTablet && screenSize.width >= 720;
    final dialogWidth = useWideDialog
        ? (screenSize.width * 0.78).clamp(600.0, 880.0)
        : baseDialogWidth;
    final bool useSplitLayout = dialogWidth >= 620;
    final sheetHeight = hosts.isEmpty
        ? (screenSize.height * 0.4).clamp(260.0, 360.0).toDouble()
        : screenSize.height * 0.55;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurface.withOpacity(0.7);
    final mutedTextColor = colorScheme.onSurface.withOpacity(0.5);
    const accentColor = Color(0xFFFF2E55);
    final borderColor = colorScheme.onSurface.withOpacity(isDark ? 0.12 : 0.18);
    final panelColor = isDark ? const Color(0xFF242424) : const Color(0xFFEDEDED);
    final itemColor = isDark ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);
    final backgroundColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final listWidget = hosts.isEmpty
        ? _buildEmptyState(
            context,
            backgroundColor: panelColor,
            borderColor: borderColor,
            subTextColor: subTextColor,
          )
        : _buildHostList(
            context,
            provider,
            hosts,
            textColor: textColor,
            subTextColor: subTextColor,
            mutedTextColor: mutedTextColor,
            borderColor: borderColor,
            itemColor: itemColor,
          );

    return NipaplayWindowScaffold(
      maxWidth: dialogWidth,
      maxHeightFactor: (sheetHeight / screenSize.height).clamp(0.5, 0.85),
      onClose: () => Navigator.of(context).maybePop(),
      backgroundColor: backgroundColor,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: keyboardHeight),
          child: SizedBox(
            height: sheetHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Ionicons.link_outline, color: textColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '选择共享客户端',
                        locale: const Locale('zh', 'CN'),
                        style: textTheme.titleLarge?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ) ??
                            TextStyle(
                              color: textColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.left,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '从下方列表中选择已开启远程访问的 NipaPlay 客户端，切换后即可浏览它的本地媒体库。',
                    locale: const Locale('zh', 'CN'),
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: useSplitLayout
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: listWidget),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: (dialogWidth * 0.32).clamp(220.0, 280.0),
                                child: _buildActionPanel(
                                  context,
                                  provider,
                                  accentColor: accentColor,
                                  textColor: textColor,
                                  subTextColor: subTextColor,
                                  borderColor: borderColor,
                                  panelColor: panelColor,
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInlineActions(
                                context,
                                provider,
                                accentColor: accentColor,
                              ),
                              const SizedBox(height: 12),
                              Expanded(child: listWidget),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required Color backgroundColor,
    required Color borderColor,
    required Color subTextColor,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Ionicons.cloud_offline_outline,
              color: subTextColor.withOpacity(0.8)),
          const SizedBox(height: 10),
          Text(
            '尚未添加任何共享客户端\n请使用操作按钮进行添加',
            textAlign: TextAlign.center,
            locale: const Locale('zh', 'CN'),
            style: TextStyle(color: subTextColor),
          ),
        ],
      ),
    );
  }

  Widget _buildHostList(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
    List<SharedRemoteHost> hosts, {
    required Color textColor,
    required Color subTextColor,
    required Color mutedTextColor,
    required Color borderColor,
    required Color itemColor,
  }) {
    return ListView.separated(
      itemCount: hosts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final host = hosts[index];
        final isActive = provider.activeHostId == host.id;
        final displayName =
            host.displayName.isNotEmpty ? host.displayName : host.baseUrl;
        final lastSync = host.lastConnectedAt != null
            ? host.lastConnectedAt!.toLocal().toString().split('.').first
            : null;
        final statusColor =
            host.isOnline ? Colors.greenAccent : Colors.orangeAccent;
        return GestureDetector(
          onTap: () async {
            await provider.setActiveHost(host.id);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive
                    ? Colors.lightBlueAccent.withOpacity(0.5)
                    : borderColor,
                width: isActive ? 1.2 : 0.6,
              ),
              color: itemColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      host.isOnline
                          ? Ionicons.checkmark_circle_outline
                          : Ionicons.alert_circle_outline,
                      color: statusColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.lightBlueAccent.withOpacity(0.24),
                        ),
                        child: const Text(
                          '当前使用',
                          locale: Locale('zh', 'CN'),
                          style: TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 11),
                        ),
                      )
                    else
                      Icon(Ionicons.chevron_forward,
                          color: textColor.withOpacity(0.5), size: 16),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  host.baseUrl,
                  style: TextStyle(color: subTextColor, fontSize: 12),
                ),
                if (host.lastError != null && host.lastError!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    host.lastError!,
                    locale: const Locale('zh', 'CN'),
                    style: const TextStyle(
                        color: Colors.orangeAccent, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  lastSync != null ? '最后同步: $lastSync' : '最后同步: 尚未成功连接',
                  style: TextStyle(color: mutedTextColor, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineActions(
    BuildContext context,
    SharedRemoteLibraryProvider provider, {
    required Color accentColor,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        _buildPrimaryActionButton(
          icon: Ionicons.wifi_outline,
          label: '扫描局域网',
          onPressed: () => _showLanScanDialog(context, provider),
          accentColor: accentColor,
          minWidth: 160,
        ),
        _buildSecondaryActionButton(
          icon: Ionicons.add_outline,
          label: '添加共享客户端',
          onPressed: () => _showAddHostDialog(context, provider),
          accentColor: accentColor,
          minWidth: 160,
        ),
      ],
    );
  }

  Widget _buildActionPanel(
    BuildContext context,
    SharedRemoteLibraryProvider provider, {
    required Color accentColor,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color panelColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '快速操作',
            locale: const Locale('zh', 'CN'),
            style: TextStyle(
              color: textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildPrimaryActionButton(
            icon: Ionicons.wifi_outline,
            label: '扫描局域网',
            onPressed: () => _showLanScanDialog(context, provider),
            accentColor: accentColor,
            expand: true,
          ),
          const SizedBox(height: 8),
          _buildSecondaryActionButton(
            icon: Ionicons.add_outline,
            label: '添加共享客户端',
            onPressed: () => _showAddHostDialog(context, provider),
            accentColor: accentColor,
            expand: true,
          ),
          const SizedBox(height: 12),
          Text(
            '已开启远程访问的设备会被自动发现，未发现可手动输入地址。',
            locale: const Locale('zh', 'CN'),
            style: TextStyle(
              color: subTextColor,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _primaryActionStyle(Color accentColor) {
    return ElevatedButton.styleFrom(
      backgroundColor: accentColor,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      elevation: 0,
    ).copyWith(
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    );
  }

  ButtonStyle _secondaryActionStyle(Color accentColor) {
    return OutlinedButton.styleFrom(
      foregroundColor: accentColor,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      side: BorderSide(color: accentColor.withOpacity(0.7)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ).copyWith(
      overlayColor: MaterialStateProperty.all(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
    );
  }

  Widget _buildPrimaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color accentColor,
    bool expand = false,
    double minWidth = 0,
  }) {
    final button = ElevatedButton.icon(
      onPressed: onPressed,
      style: _primaryActionStyle(accentColor),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: button,
    );
  }

  Widget _buildSecondaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color accentColor,
    bool expand = false,
    double minWidth = 0,
  }) {
    final button = OutlinedButton.icon(
      onPressed: onPressed,
      style: _secondaryActionStyle(accentColor),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: button,
    );
  }

  Future<void> _showAddHostDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    final result = await BlurLoginDialog.show(
      context,
      title: '添加共享客户端',
      fields: const [
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

          return const LoginResult(
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

    if (result == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showLanScanDialog(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    final result =
        await SharedRemoteLanScanDialog.show(context, provider: provider);
    if (result == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }
}
