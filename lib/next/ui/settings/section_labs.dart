import 'package:flutter/widgets.dart';

import '../../voice/model_store.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import 'registry_rows.dart';
import 'settings_layout.dart';

class LabsSection extends StatelessWidget {
  const LabsSection({super.key, required this.model, this.highlight});
  final SettingsModel model;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final store = VoiceModelStore.instance;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('这里的功能仍在实验中，可以随时关闭。',
          style: NextText.sans(13, color: NextColors.p2)),
      const SizedBox(height: 18),
      RegistryGroups(
          section: SettingsSection.labs,
          model: model,
          more: true,
          onMore: () {},
          highlight: highlight),
      if (VoiceModelStore.supported)
        AnimatedBuilder(
            animation: store,
            builder: (context, _) {
              final preparing =
                  store.phase == 'downloading' || store.phase == 'installing';
              final status = switch (store.phase) {
                'downloading' =>
                  '正在下载 ${(store.received / 1048576).toStringAsFixed(1)} / ${(store.model.bytes / 1048576).toStringAsFixed(1)} MiB',
                'installing' => '正在校验并安装模型…',
                'ready' =>
                  '模型已就绪${store.enabled ? '，可在梨花对话框点击麦克风' : '，开启后即可使用'}',
                'failed' => '模型准备失败：${store.error}',
                _ => '开启后下载所选模型。下载完成后可离线使用。',
              };
              return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(status,
                          style: NextText.sans(13, color: NextColors.p2)),
                      const SizedBox(height: 10),
                      Text(
                          '录音仅用于本机转写，文字留在输入框，确认后发送。每次录音最长 3 分钟。'
                          ' Linux 需安装 PulseAudio 工具（parecord）。',
                          style: NextText.sans(12, color: NextColors.p3)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 10, children: [
                        if (!store.installed && !preparing)
                          NextButton.ghost(
                              label: store.phase == 'failed' ? '重试下载' : '下载模型',
                              onTap: () => model.change(
                                  'labs.voiceModelDownload', true)),
                        if (preparing || store.installed)
                          NextButton.ghost(
                              label: preparing ? '取消下载' : '删除所选模型',
                              onTap: () => model.change(
                                  'labs.voiceModelDownload', false)),
                      ]),
                      if (model.errors['labs.voiceModelDownload']
                          case final message?)
                        Text(message,
                            style: NextText.sans(12, color: NextColors.p2)),
                    ],
                  ));
            }),
    ]);
  }
}
