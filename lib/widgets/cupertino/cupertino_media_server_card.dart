import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Cupertino 风格的网络媒体服务器状态卡片。
enum ServerBrand { jellyfin, emby }

class CupertinoMediaServerCard extends StatelessWidget {
  const CupertinoMediaServerCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.isConnected,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
    this.serverUrl,
    this.username,
    this.selectedLibraries = const <String>[],
    this.mediaItemCount,
    required this.onManage,
    this.onViewLibrary,
    this.onDisconnect,
    this.onRefresh,
    this.disconnectedDescription,
    this.serverBrand,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final bool isConnected;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;
  final String? serverUrl;
  final String? username;
  final List<String> selectedLibraries;
  final int? mediaItemCount;
  final VoidCallback onManage;
  final VoidCallback? onViewLibrary;
  final VoidCallback? onDisconnect;
  final VoidCallback? onRefresh;
  final String? disconnectedDescription;
  final ServerBrand? serverBrand;

  @override
  Widget build(BuildContext context) {
    final Color background = CupertinoDynamicColor.resolve(
      CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );
    final Color labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final Color secondaryLabelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: serverBrand != null
                    ? SvgPicture.asset(
                        serverBrand == ServerBrand.jellyfin
                            ? 'assets/jellyfin.svg'
                            : 'assets/emby.svg',
                        width: 20,
                        height: 20,
                        colorFilter: ColorFilter.mode(accentColor, BlendMode.srcIn),
                      )
                    : Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                  ),
                ),
              ),
              if (isLoading)
                const CupertinoActivityIndicator(radius: 10)
              else
                _buildStatusPill(context),
            ],
          ),
          const SizedBox(height: 16),
          if (hasError && errorMessage != null)
            _buildErrorBanner(context, errorMessage!),
          if (hasError && errorMessage != null) const SizedBox(height: 12),
          if (isConnected)
            ..._buildConnectedContent(context, labelColor, secondaryLabelColor)
          else
            _buildDisconnectedContent(context, secondaryLabelColor),
        ],
      ),
    );
  }

  Widget _buildStatusPill(BuildContext context) {
    final bool connected = isConnected;
    final Color pillColor = CupertinoDynamicColor.resolve(
      connected ? CupertinoColors.systemGreen : CupertinoColors.systemGrey,
      context,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pillColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        connected ? '已连接' : '未连接',
        style: TextStyle(
          color: pillColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<Widget> _buildConnectedContent(
    BuildContext context,
    Color labelColor,
    Color secondaryLabelColor,
  ) {
    final List<Widget> children = [];

    children.addAll([
      _buildInfoRow(context, label: '服务器地址', value: serverUrl ?? '未知'),
      const SizedBox(height: 8),
      _buildInfoRow(context, label: '登录用户', value: username ?? '匿名'),
    ]);

    if (mediaItemCount != null) {
      children.addAll([
        const SizedBox(height: 8),
        _buildInfoRow(
          context,
          label: '媒体条目',
          value: mediaItemCount!.toString(),
        ),
      ]);
    }

    if (selectedLibraries.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          '已选媒体库',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: selectedLibraries.map((lib) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                lib,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: accentColor,
                ),
              ),
            );
          }).toList(),
        ),
      ]);
    }

    children.addAll([
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 10,
        children: [
          if (onViewLibrary != null)
            _buildActionButton(
              context,
              label: '查看媒体库',
              icon: CupertinoIcons.collections,
              onPressed: onViewLibrary!,
              primary: true,
            ),
          if (onRefresh != null)
            _buildActionButton(
              context,
              label: '刷新',
              icon: CupertinoIcons.refresh,
              onPressed: onRefresh!,
            ),
          _buildActionButton(
            context,
            label: '管理服务器',
            icon: CupertinoIcons.slider_horizontal_3,
            onPressed: onManage,
          ),
          if (onDisconnect != null)
            _buildActionButton(
              context,
              label: '断开连接',
              icon: CupertinoIcons.clear,
              onPressed: onDisconnect!,
              destructive: true,
            ),
        ],
      ),
    ]);

    return children;
  }

  Widget _buildDisconnectedContent(
    BuildContext context,
    Color secondaryLabelColor,
  ) {
    final String description = disconnectedDescription ?? '尚未连接此媒体服务器，点击下方按钮完成登录。';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            color: secondaryLabelColor,
          ),
        ),
        const SizedBox(height: 18),
        _buildFilledButton(
          context,
          label: '连接服务器',
          icon: CupertinoIcons.cloud_download,
          onPressed: onManage,
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final Color labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final Color valueColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: valueColor, fontSize: 14, height: 1.35),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final Color borderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemRed,
      context,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: borderColor.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(CupertinoIcons.exclamationmark_triangle_fill,
              color: borderColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: borderColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilledButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    final Color foreground = CupertinoColors.white;

    return CupertinoButton(
      onPressed: onPressed,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      color: accentColor,
      borderRadius: BorderRadius.circular(14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool primary = false,
    bool destructive = false,
  }) {
    final Color primaryBackground = primary
        ? accentColor
        : CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey5,
            context,
          );
    final Color destructiveBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.systemRed,
      context,
    );
    final Color backgroundColor = destructive
        ? destructiveBackground
        : primaryBackground;
    final Color textColor;
    if (destructive || primary) {
      textColor = CupertinoColors.white;
    } else {
      textColor = CupertinoDynamicColor.resolve(
        CupertinoColors.label,
        context,
      );
    }

    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
