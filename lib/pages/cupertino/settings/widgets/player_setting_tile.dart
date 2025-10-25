import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import 'package:nipaplay/player_abstraction/player_factory.dart';

import '../pages/cupertino_player_settings_page.dart';

class CupertinoPlayerSettingTile extends StatefulWidget {
  const CupertinoPlayerSettingTile({super.key});

  @override
  State<CupertinoPlayerSettingTile> createState() =>
      _CupertinoPlayerSettingTileState();
}

class _CupertinoPlayerSettingTileState
    extends State<CupertinoPlayerSettingTile> {
  late String _kernelName;

  @override
  void initState() {
    super.initState();
    _kernelName = _kernelLabel(PlayerFactory.getKernelType());
  }

  String _kernelLabel(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return '当前：MDK';
      case PlayerKernelType.videoPlayer:
        return '当前：Video Player';
      case PlayerKernelType.mediaKit:
        return '当前：Libmpv';
    }
  }

  Future<void> _refreshKernelName() async {
    setState(() {
      _kernelName = _kernelLabel(PlayerFactory.getKernelType());
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveListTile(
      leading: const Icon(CupertinoIcons.play_circle),
      title: const Text('播放器'),
      subtitle: Text(_kernelName),
      trailing: Icon(
        PlatformInfo.isIOS
            ? CupertinoIcons.chevron_forward
            : CupertinoIcons.forward,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey2,
          context,
        ),
      ),
      onTap: () async {
        await Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoPlayerSettingsPage(),
          ),
        );
        if (!mounted) return;
        await _refreshKernelName();
      },
    );
  }
}
