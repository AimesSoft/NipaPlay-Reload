import 'package:fluent_ui/fluent_ui.dart';

class FluentRemoteMediaLibraryPage extends StatefulWidget {
  const FluentRemoteMediaLibraryPage({super.key});

  @override
  State<FluentRemoteMediaLibraryPage> createState() => _FluentRemoteMediaLibraryPageState();
}

class _FluentRemoteMediaLibraryPageState extends State<FluentRemoteMediaLibraryPage> {
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: const PageHeader(
        title: Text('远程媒体库'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            InfoBar(
              title: const Text('开发中'),
              content: const Text('远程媒体库设置页面正在开发中，敬请期待。'),
              severity: InfoBarSeverity.info,
            ),
          ],
        ),
      ),
    );
  }
}