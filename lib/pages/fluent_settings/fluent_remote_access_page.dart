import 'package:fluent_ui/fluent_ui.dart';

class FluentRemoteAccessPage extends StatefulWidget {
  const FluentRemoteAccessPage({super.key});

  @override
  State<FluentRemoteAccessPage> createState() => _FluentRemoteAccessPageState();
}

class _FluentRemoteAccessPageState extends State<FluentRemoteAccessPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('远程访问'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            InfoBar(
              title: const Text('开发中'),
              content: const Text('远程访问设置页面正在开发中，敬请期待。'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ),
      ),
    );
  }
}