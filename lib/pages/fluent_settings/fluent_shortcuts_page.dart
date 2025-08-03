import 'package:fluent_ui/fluent_ui.dart';

class FluentShortcutsPage extends StatefulWidget {
  const FluentShortcutsPage({super.key});

  @override
  State<FluentShortcutsPage> createState() => _FluentShortcutsPageState();
}

class _FluentShortcutsPageState extends State<FluentShortcutsPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('快捷键设置'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            InfoBar(
              title: const Text('开发中'),
              content: const Text('快捷键设置页面正在开发中，敬请期待。'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ),
      ),
    );
  }
}