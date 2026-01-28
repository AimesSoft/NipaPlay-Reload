import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/dependency_versions_loader.dart';

class DependencyVersionsWindow extends StatefulWidget {
  const DependencyVersionsWindow({super.key});

  @override
  State<DependencyVersionsWindow> createState() =>
      _DependencyVersionsWindowState();
}

class _DependencyVersionsWindowState extends State<DependencyVersionsWindow> {
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
      BlurSnackBar.show(context, '链接无效');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      BlurSnackBar.show(context, '无法打开链接: $urlString');
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

  Widget _buildContent(BuildContext context, List<DependencyEntry> entries) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = entries.length;
    final directMain =
        entries.where((entry) => entry.dependency == 'direct main').length;
    final directDev =
        entries.where((entry) => entry.dependency == 'direct dev').length;
    final transitive =
        entries.where((entry) => entry.dependency == 'transitive').length;
    final other = total - directMain - directDev - transitive;
    final summary = other > 0
        ? '共 $total 个库 · 直接 $directMain / 开发 $directDev / 间接 $transitive / 其他 $other'
        : '共 $total 个库 · 直接 $directMain / 开发 $directDev / 间接 $transitive';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              summary,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
        ),
        Divider(
          height: 1,
          color: colorScheme.onSurface.withOpacity(0.12),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: entries.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: colorScheme.onSurface.withOpacity(0.08),
            ),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
                dense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                leading: Icon(
                  Ionicons.list_outline,
                  size: 18,
                  color: colorScheme.primary,
                ),
                title: Text(entry.name),
                subtitle: Text(
                  '版本: ${entry.version} · ${_formatDependencyType(entry.dependency)} · ${_formatSourceType(entry.source)}',
                ),
                trailing: Icon(
                  Ionicons.logo_github,
                  size: 18,
                  color: colorScheme.primary,
                ),
                onTap: () => _openUrl(entry.githubUrl),
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
    return NipaplayWindowScaffold(
      maxWidth: 900,
      maxHeightFactor: 0.85,
      onClose: () => Navigator.of(context).maybePop(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Row(
              children: [
                Text(
                  '依赖库版本',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '刷新',
                  icon: Icon(
                    Ionicons.refresh_outline,
                    size: 18,
                    color: colorScheme.onSurface,
                  ),
                  onPressed: _reload,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.onSurface.withOpacity(0.12),
          ),
          Expanded(
            child: FutureBuilder<List<DependencyEntry>>(
              future: _entriesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('正在解析依赖信息...'),
                      ],
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('读取依赖列表失败'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  );
                }
                return _buildContent(context, snapshot.data ?? []);
              },
            ),
          ),
        ],
      ),
    );
  }
}
