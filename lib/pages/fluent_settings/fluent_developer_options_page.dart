import 'package:fluent_ui/fluent_ui.dart';

class FluentDeveloperOptionsPage extends StatefulWidget {
  const FluentDeveloperOptionsPage({super.key});

  @override
  State<FluentDeveloperOptionsPage> createState() => _FluentDeveloperOptionsPageState();
}

class _FluentDeveloperOptionsPageState extends State<FluentDeveloperOptionsPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('开发者选项'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            InfoBar(
              title: const Text('开发中'),
              content: const Text('开发者选项页面正在开发中，敬请期待。'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ),
      ),
    );
  }
}