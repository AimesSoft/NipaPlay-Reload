import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/gui_calls.dart';
import '../settings/controls.dart' show PillButton;
import '../settings/registry_rows.dart' show whenText;
import '../settings/section_accounts.dart' show ConfirmPill;
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';

/// 在追: what Nipa watches for, on whichever device she runs. Each shows
/// her own sentence for it, when she last looked and what came of it; it
/// can be paused, resumed or let go here as by asking her. What she looks
/// for and how is hers (her scripts), not shown.
class FollowingView extends StatefulWidget {
  const FollowingView({super.key});

  @override
  State<FollowingView> createState() => _FollowingViewState();
}

class _FollowingViewState extends State<FollowingView> {
  /// One subscription to the data for the view's life: a new stream at each
  /// build would start over, waiting, every time the page is built.
  Stream<List<UiSubscription>>? _stream;
  NextUiData? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = NextShellScope.of(context).services.data;
    if (!identical(data, _data)) {
      _data = data;
      _stream = data.subscriptions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<UiSubscription>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? const <UiSubscription>[];
        final padding = EdgeInsets.fromLTRB(NextLayout.gutter(context), 0,
            NextLayout.end(context), 64 + NextLayout.foot(context));
        if (snap.hasData && all.isEmpty) {
          return Padding(
            padding: padding,
            child: Text('没有在追的作品',
                style: NextText.sans(14, color: NextColors.p3)),
          );
        }
        // What is followed now first; paused, then ended, after.
        final sorted = [...all]
          ..sort((a, b) => a.state.index.compareTo(b.state.index));
        return ListView.separated(
          key: const PageStorageKey('activity/following'),
          padding: padding,
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: _Following(item: sorted[i]),
            ),
          ),
        );
      },
    );
  }
}

class _Following extends StatefulWidget {
  const _Following({required this.item});
  final UiSubscription item;

  @override
  State<_Following> createState() => _FollowingState();
}

class _FollowingState extends State<_Following> {
  bool _busy = false;
  String? _said;

  /// This device's subscription directly, another's on its owner.
  Future<void> _call(String action, Map<String, Object?> input) async {
    final shell = NextShellScope.of(context);
    final s = widget.item;
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final calls = shell.services.calls;
      if (s.device == null) {
        await calls.call(action, input);
      } else {
        await calls.call('mesh.invoke',
            {'deviceId': s.deviceId, 'action': action, 'input': input});
      }
    } catch (e) {
      if (mounted) setState(() => _said = callFailure(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    final shell = NextShellScope.of(context);
    final id = widget.item.workId;
    if (id == null) return;
    final work = await shell.services.data.work(id);
    if (work != null && mounted) shell.openWork(work);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.item;
    final phone = NextLayout.compact(context);
    final active = s.state == UiSubscriptionState.active;
    final latest = s.downloads.firstOrNull;
    final facts = [
      if (s.lastCheckedAt case final at?) '${whenText(at)}检查',
      if (latest != null)
        latest.episode == null
            ? '已下载 ${latest.title}'
            : '第 ${latest.episode} 集已下载',
    ];
    final poster = SizedBox(
      width: phone ? 56 : 68,
      height: phone ? 84 : 102,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: NextImage(s.artwork?.poster,
            shape: ArtShape.poster, tint: s.artwork?.tint),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Flexible(
            child: Text(s.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(15.5,
                    weight: FontWeight.w600,
                    color: active ? NextColors.paper : NextColors.p2)),
          ),
          if (!active) ...[
            const SizedBox(width: 8),
            Text(s.state == UiSubscriptionState.paused ? '已暂停' : '已完结',
                style: NextText.sans(12, color: NextColors.p3)),
          ],
        ]),
        if (s.note.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(s.note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(13.5, color: NextColors.p2, height: 1.4)),
        ],
        const SizedBox(height: 6),
        if (s.errors.isNotEmpty || _said != null)
          Text(_said ?? s.errors.first,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(12, color: NextColors.accent2))
        else if (facts.isNotEmpty)
          Text(facts.join(' · '),
              style: NextText.sans(12, color: NextColors.p3)),
        if (s.device != null) ...[
          const SizedBox(height: 3),
          Text(s.online ? '在 ${s.device} 上' : '在 ${s.device} 上 · 不在线',
              style: NextText.sans(12, color: NextColors.p4)),
        ],
      ],
    );
    final buttons = Wrap(spacing: 8, runSpacing: 8, children: [
      if (s.state != UiSubscriptionState.ended)
        PillButton(
          label: active ? '暂停' : '继续',
          busy: _busy,
          onTap: _busy || !s.online
              ? null
              : () => unawaited(_call('subscription.set_state',
                  {'id': s.id, 'state': active ? 'paused' : 'active'})),
        ),
      ConfirmPill(
        label: '移除',
        confirm: '确定移除',
        onConfirm: () => unawaited(_call('subscription.remove', {'id': s.id})),
      ),
    ]);
    return Pressable(
      onTap: s.workId == null ? null : () => unawaited(_open()),
      semanticLabel: s.title,
      pressScale: 0.99,
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x0DFFFFFF) : const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NextColors.line),
        ),
        child: phone
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                poster,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [words, const SizedBox(height: 10), buttons]),
                ),
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                poster,
                const SizedBox(width: 16),
                Expanded(child: words),
                const SizedBox(width: 16),
                buttons,
              ]),
      ),
    );
  }
}
