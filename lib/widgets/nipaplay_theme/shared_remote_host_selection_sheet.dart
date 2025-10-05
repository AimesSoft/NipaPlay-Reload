import 'package:flutter/material.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';

class SharedRemoteHostSelectionSheet extends StatelessWidget {
  const SharedRemoteHostSelectionSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const SharedRemoteHostSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SharedRemoteLibraryProvider>();
    final hosts = provider.hosts;
    final enableBlur = context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect;

    final sheetHeight = hosts.isEmpty
        ? 220.0
        : MediaQuery.of(context).size.height * 0.55;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        top: 12,
      ),
      child: GlassmorphicContainer(
        width: double.infinity,
        height: sheetHeight,
        borderRadius: 24,
        blur: enableBlur ? 20 : 0,
        border: 1,
        alignment: Alignment.topCenter,
        linearGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.22),
            Colors.white.withOpacity(0.12),
          ],
        ),
        borderGradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.4),
            Colors.white.withOpacity(0.4),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Ionicons.link_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    '选择共享客户端',
                    locale: Locale('zh', 'CN'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '从下方列表中选择已开启远程访问的 NipaPlay 客户端，切换后即可浏览它的本地媒体库。',
                locale: Locale('zh', 'CN'),
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
              ),
              const SizedBox(height: 16),
              if (hosts.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Ionicons.cloud_offline_outline, color: Colors.white60),
                      SizedBox(height: 10),
                      Text(
                        '尚未添加任何共享客户端\n请先在“远程媒体库”设置中添加',
                        textAlign: TextAlign.center,
                        locale: Locale('zh', 'CN'),
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: hosts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final host = hosts[index];
                      final isActive = provider.activeHostId == host.id;
                      final displayName = host.displayName.isNotEmpty ? host.displayName : host.baseUrl;
                      final lastSync = host.lastConnectedAt != null
                          ? host.lastConnectedAt!.toLocal().toString().split('.').first
                          : null;
                      final statusColor = host.isOnline ? Colors.greenAccent : Colors.orangeAccent;
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
                              color: isActive ? Colors.lightBlueAccent.withOpacity(0.5) : Colors.white.withOpacity(0.08),
                              width: isActive ? 1.2 : 0.6,
                            ),
                            color: Colors.black.withOpacity(0.22),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    host.isOnline ? Ionicons.checkmark_circle_outline : Ionicons.alert_circle_outline,
                                    color: statusColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      displayName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: Colors.lightBlueAccent.withOpacity(0.24),
                                      ),
                                      child: const Text(
                                        '当前使用',
                                        locale: Locale('zh', 'CN'),
                                        style: TextStyle(color: Colors.lightBlueAccent, fontSize: 11),
                                      ),
                                    )
                                  else
                                    const Icon(Ionicons.chevron_forward, color: Colors.white54, size: 16),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                host.baseUrl,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              if (host.lastError != null && host.lastError!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  host.lastError!,
                                  locale: const Locale('zh', 'CN'),
                                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                lastSync != null
                                    ? '最后同步: $lastSync'
                                    : '最后同步: 尚未成功连接',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
