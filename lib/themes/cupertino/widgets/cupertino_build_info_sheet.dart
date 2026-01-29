import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/build_info.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoBuildInfoSheet extends StatefulWidget {
  const CupertinoBuildInfoSheet({super.key});

  @override
  State<CupertinoBuildInfoSheet> createState() =>
      _CupertinoBuildInfoSheetState();
}

class _CupertinoBuildInfoSheetState extends State<CupertinoBuildInfoSheet> {
  late Future<List<BuildInfoSection>> _infoFuture;

  @override
  void initState() {
    super.initState();
    _infoFuture = loadBuildInfoSections();
  }

  void _reload() {
    setState(() {
      _infoFuture = loadBuildInfoSections();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BuildInfoSection>>(
      future: _infoFuture,
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
                      Text('正在收集构建信息...'),
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
                      const Text('读取构建信息失败'),
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

        final sections = snapshot.data ?? [];
        final labelColor = CupertinoDynamicColor.resolve(
          CupertinoColors.secondaryLabel,
          context,
        );
        final tileColor = resolveSettingsTileBackground(context);

        return CupertinoBottomSheetContentLayout(
          sliversBuilder: (context, topSpacing) {
            final slivers = <Widget>[];
            for (var i = 0; i < sections.length; i++) {
              final section = sections[i];
              final topPadding = i == 0 ? topSpacing + 12.0 : 12.0;
              slivers.add(
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, topPadding, 20, 8),
                    child: Text(
                      section.title,
                      style: TextStyle(
                        fontSize: 13,
                        color: labelColor,
                      ),
                    ),
                  ),
                ),
              );
              slivers.add(
                SliverToBoxAdapter(
                  child: CupertinoSettingsGroupCard(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    backgroundColor: resolveSettingsSectionBackground(context),
                    addDividers: true,
                    children: section.entries
                        .map(
                          (entry) => CupertinoSettingsTile(
                            title: Text(entry.label),
                            subtitle: Text(entry.value),
                            backgroundColor: tileColor,
                          ),
                        )
                        .toList(),
                  ),
                ),
              );
              if (i != sections.length - 1) {
                slivers.add(
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                );
              }
            }

            slivers.add(
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    '注：构建前需生成 assets/build_info.json，未生成将显示“未注入”。',
                    style: TextStyle(fontSize: 12, color: labelColor),
                  ),
                ),
              ),
            );
            slivers.add(
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            );

            return slivers;
          },
        );
      },
    );
  }
}
