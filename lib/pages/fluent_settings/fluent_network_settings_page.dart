import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';

class FluentNetworkSettingsPage extends StatefulWidget {
  const FluentNetworkSettingsPage({super.key});

  @override
  State<FluentNetworkSettingsPage> createState() => _FluentNetworkSettingsPageState();
}

class _FluentNetworkSettingsPageState extends State<FluentNetworkSettingsPage> {
  String _currentServer = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentServer();
  }

  Future<void> _loadCurrentServer() async {
    final server = await NetworkSettings.getDandanplayServer();
    if (!mounted) return;
    setState(() {
      _currentServer = server;
      _isLoading = false;
    });
  }

  Future<void> _changeServer(String serverUrl) async {
    await NetworkSettings.setDandanplayServer(serverUrl);
    if (!mounted) return;
    setState(() {
      _currentServer = serverUrl;
    });

    final displayName = _getServerDisplayName(serverUrl);
    FluentInfoBar.show(
      context,
      '弹弹play 服务器已切换到 $displayName',
      severity: InfoBarSeverity.success,
    );
  }

  String _getServerDisplayName(String serverUrl) {
    switch (serverUrl) {
      case NetworkSettings.primaryServer:
        return '主服务器';
      case NetworkSettings.backupServer:
        return '备用服务器';
      default:
        return serverUrl;
    }
  }

  List<ComboBoxItem<String>> _buildServerItems() {
    final items = [
      ComboBoxItem<String>(
        value: NetworkSettings.primaryServer,
        child: const Text('主服务器 (推荐)'),
      ),
      ComboBoxItem<String>(
        value: NetworkSettings.backupServer,
        child: const Text('备用服务器'),
      ),
    ];

    if (_currentServer != NetworkSettings.primaryServer &&
        _currentServer != NetworkSettings.backupServer &&
        _currentServer.isNotEmpty) {
      items.add(
        ComboBoxItem<String>(
          value: _currentServer,
          child: Text(_currentServer),
        ),
      );
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ScaffoldPage(
        content: Center(
          child: ProgressRing(),
        ),
      );
    }

    return ScaffoldPage(
      header: const PageHeader(
        title: Text('网络设置'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弹弹play 服务器',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择弹弹play 弹幕数据来源，当主服务器不可用时可切换至备用服务器。',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ComboBox<String>(
                        value: _currentServer,
                        items: _buildServerItems(),
                        onChanged: (value) {
                          if (value != null && value != _currentServer) {
                            _changeServer(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          FluentIcons.info,
                          color: FluentTheme.of(context).accentColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '当前服务器信息',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    InfoLabel(
                      label: '服务器',
                      child: Text(_getServerDisplayName(_currentServer)),
                    ),
                    const SizedBox(height: 8),
                    InfoLabel(
                      label: 'URL',
                      child: Text(_currentServer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '服务器说明',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 12),
                    Text('• 主服务器：api.dandanplay.net（官方服务器，推荐使用）'),
                    SizedBox(height: 4),
                    Text('• 备用服务器：139.217.235.62:16001（镜像服务器，主服务器无法访问时使用）'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
