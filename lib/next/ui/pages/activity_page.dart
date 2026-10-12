import 'package:flutter/widgets.dart';

import '../cards/card_views.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/words.dart';

/// 动态: what is running now, and Nipa's latest word.
class ActivityPage extends StatelessWidget {
  const ActivityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final actions = shell.services.actions;
    return ListenableBuilder(
      listenable: Listenable.merge([shell.tasks, shell.chat]),
      builder: (context, _) {
        final tasks = shell.activeTasks;
        final c = shell.chat;
        final line = c.doing ?? c.latestLine;
        return ListView(
          key: const PageStorageKey('activity'),
          padding: const EdgeInsets.fromLTRB(
              NextMetrics.gutter, NextMetrics.topBar + 40, 56, 64),
          children: [
            Text('动态', style: NextText.sans(28, weight: FontWeight.w600)),
            const SizedBox(height: 28),
            if (line != null) ...[
              Row(children: [
                NipaAvatar(
                    size: 28,
                    mood: c.mood,
                    sentence: c.moodSentence,
                    onTap: shell.openChat),
                const SizedBox(width: 12),
                Expanded(child: NipaSentence(line)),
              ]),
              const SizedBox(height: 28),
            ],
            if (tasks.isEmpty)
              Text('现在没有在忙的事。',
                  style: NextText.sans(14.5, color: NextColors.p3))
            else
              Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 520,
                  child: Column(children: [
                    for (final (i, task) in tasks.indexed) ...[
                      if (i > 0) const SizedBox(height: 12),
                      CardSurface(
                        padding: const EdgeInsets.all(14),
                        child: TaskRow(
                          task: task,
                          callbacks: CardCallbacks(
                            onPauseTask: (t) => actions.pauseTask(t.taskId),
                            onResumeTask: (t) => actions.resumeTask(t.taskId),
                            onCancelTask: (t) => actions.cancelTask(t.taskId),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}
