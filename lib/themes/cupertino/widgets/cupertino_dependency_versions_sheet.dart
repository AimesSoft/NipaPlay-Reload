import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/utils/dependency_versions_loader.dart';

class CupertinoDependencyVersionsSheet extends StatefulWidget {
  const CupertinoDependencyVersionsSheet({super.key});

  @override
  State<CupertinoDependencyVersionsSheet> createState() =>
      _CupertinoDependencyVersionsSheetState();
}

class _CupertinoDependencyVersionsSheetState
    extends State<CupertinoDependencyVersionsSheet> {
  late Future<List<DependencyEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = DependencyVersionsLoader.load();
  }

  void _reload() {
    setState(() {
      _entriesFuture = DependencyVersionsLoader.load();
    });
  }

  Future<void> _openUrl(String urlString) async {
    final uri = Uri.tryParse(urlString);
    if (uri == null) {
      AdaptiveSnackBar.show(
        context,
        message: '链接无效',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '无法打开链接: $urlString',
        type: AdaptiveSnackBarType.error,
      );
    }
  }

  String _formatDependencyType(String dependency) {
    switch (dependency) {
      case 'direct main':
        return '直接依赖';
      case 'direct dev':
        return '开发依赖';
      case 'transitive':
        return '间接依赖';
      default:
        return dependency.isEmpty ? '未知来源' : dependency;
    }
  }

  String _formatSourceType(String source) {
    switch (source) {
      case 'git':
        return 'git';
      case 'path':
        return '本地';
      case 'hosted':
        return 'pub.dev';
      default:
        return source.isEmpty ? '未知' : source;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<DependencyEntry>>(
      future: _entriesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return CupertinoBottomSheetContentLayout(
            sliversBuilder: (context, topSpacing) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, topSpacing + 32, 20, 24),
                  child: Column(
                    children: const [
                      CupertinoActivityIndicator(),
                      SizedBox(height: 12),
                      Text('正在解析依赖信息...'),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return CupertinoBottomSheetContentLayout(
            sliversBuilder: (context, topSpacing) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, topSpacing + 32, 20, 24),
                  child: Column(
                    children: [
                      Icon(
                        CupertinoIcons.exclamationmark_triangle,
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemRed,
                          context,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text('读取依赖列表失败'),
                      const SizedBox(height: 12),
                      CupertinoButton.filled(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        onPressed: _reload,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        final entries = snapshot.data ?? [];
        final total = entries.length;
        final directMain =
            entries.where((entry) => entry.dependency == 'direct main').length;
        final directDev =
            entries.where((entry) => entry.dependency == 'direct dev').length;
        final transitive =
            entries.where((entry) => entry.dependency == 'transitive').length;
        final other = total - directMain - directDev - transitive;

        final labelColor = CupertinoDynamicColor.resolve(
          CupertinoColors.secondaryLabel,
          context,
        );
        final tileColor = resolveSettingsTileBackground(context);
        final iconColor = resolveSettingsIconColor(context);

        return CupertinoBottomSheetContentLayout(
          sliversBuilder: (context, topSpacing) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, topSpacing + 12, 20, 12),
                child: Text(
                  other > 0
                      ? '共 $total 个库 · 直接 $directMain / 开发 $directDev / 间接 $transitive / 其他 $other'
                      : '共 $total 个库 · 直接 $directMain / 开发 $directDev / 间接 $transitive',
                  style: TextStyle(
                    fontSize: 13,
                    color: labelColor,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: CupertinoSettingsGroupCard(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                backgroundColor: resolveSettingsSectionBackground(context),
                addDividers: true,
                children: entries
                    .map(
                      (entry) => CupertinoSettingsTile(
                        leading: Icon(
                          CupertinoIcons.list_bullet,
                          color: iconColor,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                          '版本: ${entry.version} · ${_formatDependencyType(entry.dependency)} · ${_formatSourceType(entry.source)}',
                        ),
                        trailing: Icon(
                          Ionicons.logo_github,
                          size: 18,
                          color: iconColor,
                        ),
                        backgroundColor: tileColor,
                        onTap: () => _openUrl(entry.githubUrl),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}
