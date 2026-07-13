import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_lan_scan_dialog.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/remote/shared_remote_host_selection_model.dart';
import 'package:nipaplay/services/remote_access_qr_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_shared_remote_host_selection_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

class SharedRemoteHostSelectionSheet extends StatelessWidget {
  const SharedRemoteHostSelectionSheet({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  static Future<void> show(BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoBottomSheet.show<void>(
        context: context,
        title: '选择共享客户端',
        floatingTitle: true,
        child: const SharedRemoteHostSelectionSheet(embedded: true),
      );
    }

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
    final data = _buildViewModel(context, provider);
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return CupertinoSharedRemoteHostSelectionView(data: data);
    }
    final screenSize = MediaQuery.of(context).size;
    final baseDialogWidth =
        globals.DialogSizes.getDialogWidth(screenSize.width);
    final bool useWideDialog =
        globals.isDesktopOrTablet && screenSize.width >= 720;
    final dialogWidth = useWideDialog
        ? (screenSize.width * 0.78).clamp(600.0, 880.0)
        : baseDialogWidth;
    final bool useSplitLayout = dialogWidth >= 620;
    final sheetHeight = data.items.isEmpty
        ? (screenSize.height * 0.4).clamp(260.0, 360.0).toDouble()
        : screenSize.height * 0.55;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = colorScheme.onSurface;
    final subTextColor = colorScheme.onSurface.withOpacity(0.7);
    final mutedTextColor = colorScheme.onSurface.withOpacity(0.5);
    final borderColor = colorScheme.onSurface.withOpacity(isDark ? 0.12 : 0.18);
    final panelColor =
        isDark ? const Color(0xFF242424) : const Color(0xFFEDEDED);
    final itemColor =
        isDark ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7);
    final backgroundColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    final listWidget = data.items.isEmpty
        ? _buildEmptyState(
            context,
            backgroundColor: panelColor,
            borderColor: borderColor,
            subTextColor: subTextColor,
          )
        : _buildHostList(
            context,
            data.items,
            textColor: textColor,
            subTextColor: subTextColor,
            mutedTextColor: mutedTextColor,
            borderColor: borderColor,
            itemColor: itemColor,
          );

    final content = ClipRRect(
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
                if (!embedded) ...[
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
                ],
                Text(
                  '从下方列表中选择已开启远程访问的 NipaPlay 客户端，切换后即可浏览它的本地媒体库。',
                  locale: const Locale('zh', 'CN'),
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 16),
                Expanded(
                  child: useSplitLayout
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: listWidget),
                            SizedBox(width: 16),
                            SizedBox(
                              width: (dialogWidth * 0.32).clamp(220.0, 280.0),
                              child: _buildActionPanel(
                                context,
                                data.actions,
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
                              data.actions,
                            ),
                            SizedBox(height: 12),
                            Expanded(child: listWidget),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (embedded) return content;
    return NipaplayWindowScaffold(
      maxWidth: dialogWidth,
      maxHeightFactor: (sheetHeight / screenSize.height).clamp(0.5, 0.85),
      onClose: () => Navigator.of(context).maybePop(),
      backgroundColor: backgroundColor,
      child: content,
    );
  }

  SharedRemoteHostSelectionViewModel _buildViewModel(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) {
    return SharedRemoteHostSelectionViewModel(
      items: [
        for (final host in provider.hosts)
          SharedRemoteHostSelectionItem(
            id: host.id,
            displayName:
                host.displayName.isNotEmpty ? host.displayName : host.baseUrl,
            baseUrl: host.baseUrl,
            isOnline: host.isOnline,
            isActive: provider.activeHostId == host.id,
            lastConnectedLabel: host.lastConnectedAt == null
                ? '尚未成功连接'
                : '最后连接：${host.lastConnectedAt!.toLocal().toString().split('.').first}',
            errorMessage: host.lastError,
            onSelect: () async {
              await provider.setActiveHost(host.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
      actions: [
        SharedRemoteHostSelectionAction(
          kind: SharedRemoteHostSelectionActionKind.scanLan,
          label: '扫描局域网',
          onPressed: () => _showLanScanDialog(context, provider),
        ),
        SharedRemoteHostSelectionAction(
          kind: SharedRemoteHostSelectionActionKind.scanQr,
          label: '扫码连接',
          enabled: RemoteAccessQrCameraScanner.isSupported,
          onPressed: () => _connectByQr(context, provider),
        ),
        SharedRemoteHostSelectionAction(
          kind: SharedRemoteHostSelectionActionKind.addManually,
          label: '添加共享客户端',
          onPressed: () => _showAddHostDialog(context, provider),
        ),
      ],
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
          SizedBox(height: 10),
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
    List<SharedRemoteHostSelectionItem> hosts, {
    required Color textColor,
    required Color subTextColor,
    required Color mutedTextColor,
    required Color borderColor,
    required Color itemColor,
  }) {
    return ListView.separated(
      itemCount: hosts.length,
      separatorBuilder: (_, __) => SizedBox(height: 12),
      itemBuilder: (context, index) {
        final host = hosts[index];
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => host.onSelect(),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor, width: 0.6),
                color: itemColor,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Ionicons.desktop_outline,
                        color: subTextColor,
                        size: 18,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          host.displayName,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (host.isActive)
                        Icon(
                          Ionicons.checkmark_circle,
                          color: textColor,
                          size: 18,
                        )
                      else
                        Icon(Ionicons.chevron_forward,
                            color: textColor.withOpacity(0.5), size: 16),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text(
                    host.baseUrl,
                    style: TextStyle(color: subTextColor, fontSize: 12),
                  ),
                  if (host.errorMessage?.isNotEmpty == true) ...[
                    SizedBox(height: 8),
                    Text(
                      host.errorMessage!,
                      locale: const Locale('zh', 'CN'),
                      style: TextStyle(color: subTextColor, fontSize: 12),
                    ),
                  ],
                  SizedBox(height: 6),
                  Text(
                    '${host.isOnline ? '在线' : '离线'} · ${host.lastConnectedLabel}',
                    style: TextStyle(color: mutedTextColor, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInlineActions(
    BuildContext context,
    List<SharedRemoteHostSelectionAction> actions,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        for (var index = 0; index < actions.length; index++)
          (index == 0
              ? _buildPrimaryActionButton
              : _buildSecondaryActionButton)(
            icon: _desktopActionIcon(actions[index].kind),
            label: actions[index].label,
            onPressed: actions[index].enabled
                ? () => actions[index].onPressed()
                : null,
            minWidth: 160,
          ),
      ],
    );
  }

  Widget _buildActionPanel(
    BuildContext context,
    List<SharedRemoteHostSelectionAction> actions, {
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
          SizedBox(height: 12),
          for (var index = 0; index < actions.length; index++) ...[
            (index == 0
                ? _buildPrimaryActionButton
                : _buildSecondaryActionButton)(
              icon: _desktopActionIcon(actions[index].kind),
              label: actions[index].label,
              onPressed: actions[index].enabled
                  ? () => actions[index].onPressed()
                  : null,
              expand: true,
            ),
            if (index != actions.length - 1) const SizedBox(height: 8),
          ],
          SizedBox(height: 12),
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

  Widget _buildPrimaryActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool expand = false,
    double minWidth = 0,
  }) {
    final button = AdaptiveMediaActionButton(
      label: label,
      onPressed: onPressed,
      desktopIcon: icon,
      phoneIcon: icon,
      emphasis: AdaptiveMediaActionEmphasis.primary,
      expand: expand,
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
    required VoidCallback? onPressed,
    bool expand = false,
    double minWidth = 0,
  }) {
    final button = AdaptiveMediaActionButton(
      label: label,
      onPressed: onPressed,
      desktopIcon: icon,
      phoneIcon: icon,
      expand: expand,
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth),
      child: button,
    );
  }

  IconData _desktopActionIcon(SharedRemoteHostSelectionActionKind kind) {
    return switch (kind) {
      SharedRemoteHostSelectionActionKind.scanLan => Ionicons.wifi_outline,
      SharedRemoteHostSelectionActionKind.scanQr => Ionicons.qr_code_outline,
      SharedRemoteHostSelectionActionKind.addManually => Ionicons.add_outline,
    };
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

  Future<void> _connectByQr(
    BuildContext context,
    SharedRemoteLibraryProvider provider,
  ) async {
    try {
      final payload = await RemoteAccessQrCameraScanner.scan(context);
      if (payload == null) return;
      RemoteAccessServerInfo? info;
      for (final candidate in payload.allCandidateBaseUrls) {
        info = await RemoteAccessQrService.fetchServerInfo(candidate);
        if (info != null) break;
      }
      if (info == null) {
        if (context.mounted) {
          BlurSnackBar.show(context, '未识别到可访问的 NipaPlay 共享客户端');
        }
        return;
      }
      final displayName = payload.displayName?.trim().isNotEmpty == true
          ? payload.displayName!.trim()
          : info.displayName;
      await provider.connectOrActivateHost(
        displayName: displayName,
        baseUrl: info.baseUrl,
      );
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (context.mounted) {
        BlurSnackBar.show(context, '扫码连接失败：$error');
      }
    }
  }
}
