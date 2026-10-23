import 'package:flutter/widgets.dart';

import '../../ui/theme/tokens.dart';
import '../../ui/widgets/buttons.dart';
import 'playback_sources.dart';

/// The countdown is pushed by the source controller, including cancellation
/// from Nipa. No native state or separate countdown runs in the interface.
final class AutoNextOverlay extends StatelessWidget {
  const AutoNextOverlay({super.key, required this.sources});
  final PlaybackSources sources;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: sources,
      builder: (context, _) {
        final countdown = sources.autoNext;
        if (countdown == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 24, 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                    color: const Color(0xED171717),
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${countdown['remainingSeconds']} 秒后播放下一集',
                              style:
                                  NextText.sans(14, color: NextColors.paper)),
                          const SizedBox(height: 6),
                          Text(countdown['nextTitle'] as String? ?? '',
                              style: NextText.sans(12, color: NextColors.p3)),
                          const SizedBox(height: 12),
                          Pressable(
                              onTap: sources.cancelAutoNext,
                              semanticLabel: '取消自动下一集',
                              builder: (_, hovered) => Text('取消',
                                  style: NextText.sans(13,
                                      color: hovered
                                          ? NextColors.paper
                                          : NextColors.p3))),
                        ])),
              )),
        );
      });
}
