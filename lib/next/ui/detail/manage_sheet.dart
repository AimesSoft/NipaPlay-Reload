import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/work_manage.dart';
import '../settings/controls.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/devices.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/segmented.dart';

/// A sheet over the detail page: it slides in from the right while the
/// page behind darkens a little; Esc, × or a click outside closes it. The
/// page stays where it was.
class ManageLayer extends StatefulWidget {
  const ManageLayer({super.key, required this.child, required this.onClose});
  final Widget child;
  final VoidCallback onClose;

  static const width = 468.0;

  @override
  State<ManageLayer> createState() => _ManageLayerState();
}

class _ManageLayerState extends State<ManageLayer>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 360))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    final t = CurvedAnimation(parent: _c, curve: NextMotion.ease);
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: t,
        builder: (context, child) => Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: ColoredBox(
                  color: Color.fromRGBO(6, 6, 9, 0.38 * t.value)),
            ),
          ),
          Positioned(
            top: NextLayout.underBar(context) + 4,
            right: 12,
            bottom: 12 + MediaQuery.paddingOf(context).bottom,
            // A phone: as wide as it is, less the margins.
            left: NextLayout.compact(context) ? 12 : null,
            width: NextLayout.compact(context) ? null : ManageLayer.width,
            child: Opacity(
              opacity: t.value,
              child: Transform.translate(
                offset: Offset(reduced ? 0 : (1 - t.value) * 48, 0),
                child: child,
              ),
            ),
          ),
        ]),
        child: RepaintBoundary(
          child: Glass(
            blur: 34,
            color: const Color(0xD912121A),
            borderColor: const Color(0x1FFFFFFF),
            radius: BorderRadius.circular(22),
            shadows: const [
              BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 60,
                  offset: Offset(0, 24))
            ],
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The sheet's frame: a picture and a title (and the device it is changed
/// on, when not this one), the sections, the body, a word after something
/// was done, and a question over all of it when NipaPlay asks one.
class ManageFrame<T> extends StatelessWidget {
  const ManageFrame({
    super.key,
    required this.leading,
    required this.title,
    this.caption,
    this.device,
    required this.section,
    required this.sections,
    required this.onSection,
    required this.body,
    required this.onClose,
    this.note,
    this.confirm,
  });
  final Widget leading;
  final String title;
  final String? caption;
  final String? device;
  final T section;
  final List<(T, String)> sections;
  final ValueChanged<T> onSection;
  final Widget body;
  final VoidCallback onClose;
  final ManageNote? note;
  final Widget? confirm;

  @override
  Widget build(BuildContext context) => Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 0),
            child: Row(children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (caption != null)
                      Text(caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12,
                              color: NextColors.p3, letterSpacing: 0.6)),
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.serif(19,
                            weight: FontWeight.w700, height: 1.3)),
                    if (device != null) ...[
                      const SizedBox(height: 4),
                      DeviceMark([UiDevice(name: device!)]),
                    ],
                  ],
                ),
              ),
              NextIconButton(
                  glyph: NextGlyph.close, label: '关闭', onTap: onClose),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Segmented<T>(
                value: section,
                options: [
                  for (final (value, label) in sections)
                    (
                      value,
                      label,
                      (color) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(label,
                                style: NextText.sans(13, color: color)),
                          )
                    )
                ],
                onChanged: onSection,
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(key: ValueKey(section), child: body),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.bottomCenter,
            child: note == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
                    child: Row(children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: note!.error ? NextColors.accent : NextColors.mint,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(note!.text,
                            style: NextText.sans(12.5,
                                color: note!.error
                                    ? NextColors.accent2
                                    : NextColors.p2)),
                      ),
                      if (note!.action case (final label, final onTap))
                        PillButton(label: label, onTap: onTap),
                    ]),
                  ),
          ),
        ]),
        if (confirm != null)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: ColoredBox(
                  color: const Color(0x8C08080B),
                  child: Center(child: confirm),
                ),
              ),
            ),
          ),
      ]);
}

/// A word after something was done, or that it was not.
final class ManageNote {
  const ManageNote(this.text, {this.error = false, this.action});
  final String text;
  final bool error;

  /// The way back, beside the word: “撤回”.
  final (String, VoidCallback)? action;
}

/// What a sheet does for each change: one at a time, a word after it, the
/// sheet read again.
mixin ManageRunner<W extends StatefulWidget> on State<W> {
  ManageNote? note;
  bool busy = false;
  Timer? _noteTimer;

  /// Read the sheet again (and tell the page).
  Future<void> reload();

  void say(String text, {bool error = false, (String, VoidCallback)? action}) {
    _noteTimer?.cancel();
    setState(() => note = ManageNote(text, error: error, action: action));
    _noteTimer = Timer(Duration(seconds: action != null ? 8 : error ? 4 : 2), () {
      if (mounted) setState(() => note = null);
    });
  }

  /// Runs [change]; [done] is said after it, a refusal in a word.
  Future<bool> run(Future<void> Function() change, {String? done}) async {
    if (busy) return false;
    setState(() => busy = true);
    try {
      await change();
      if (!mounted) return true;
      if (done != null) say(done);
      return true;
    } on UiManageError catch (e) {
      if (mounted) say(e.conflict ? '刚刚有了变化，再试一次' : '没能完成', error: true);
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
      await reload();
    }
  }

  void disposeRunner() => _noteTimer?.cancel();
}

/// NipaPlay asks before it deletes: what it touches, and the way on or
/// back.
class ConfirmCard extends StatefulWidget {
  const ConfirmCard({
    super.key,
    required this.title,
    required this.items,
    required this.action,
    required this.onConfirm,
    required this.onCancel,
  });
  final String title;
  final List<String> items;
  final String action;
  final Future<void> Function() onConfirm;
  final VoidCallback onCancel;

  @override
  State<ConfirmCard> createState() => _ConfirmCardState();
}

class _ConfirmCardState extends State<ConfirmCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.96, end: 1),
        duration: const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        builder: (context, s, child) => Transform.scale(scale: s, child: child),
        child: Container(
          width: 360,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          decoration: BoxDecoration(
            color: const Color(0xF216161D),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x99000000),
                  blurRadius: 40,
                  offset: Offset(0, 16))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title,
                  style: NextText.sans(16, weight: FontWeight.w600)),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final item in widget.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            const NextIcon(NextGlyph.file,
                                size: 14, color: NextColors.p3),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(item,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: NextText.sans(13,
                                      color: NextColors.p2)),
                            ),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                PillButton(label: '取消', onTap: _busy ? null : widget.onCancel),
                const SizedBox(width: 10),
                DangerButton(
                  label: widget.action,
                  busy: _busy,
                  onTap: () async {
                    setState(() => _busy = true);
                    await widget.onConfirm();
                    if (mounted) setState(() => _busy = false);
                  },
                ),
              ]),
            ],
          ),
        ),
      );
}

/// The crimson pill for what deletes.
class DangerButton extends StatelessWidget {
  const DangerButton(
      {super.key, required this.label, this.onTap, this.busy = false});
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: busy ? null : onTap,
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? NextColors.accent2 : NextColors.accent,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Text(busy ? '…' : label,
              style: NextText.sans(12.5, weight: FontWeight.w600)),
        ),
      );
}

/// A small heading inside a section; [glyph] before it (a device).
class ManageHeading extends StatelessWidget {
  const ManageHeading(this.text, {super.key, this.trailing, this.glyph});
  final String text;
  final Widget? trailing;
  final NextGlyph? glyph;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10, left: 2),
        child: Row(children: [
          if (glyph != null) ...[
            NextIcon(glyph!, size: 13, color: NextColors.p3, stroke: 1.9),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(text,
                style: NextText.sans(12.5,
                    weight: FontWeight.w500,
                    color: NextColors.p3,
                    letterSpacing: 0.4)),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// A device that cannot be asked now, in its phrase: “旧笔记本不在线”.
class AwayNote extends StatelessWidget {
  const AwayNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(children: [
          const NextIcon(NextGlyph.device,
              size: 13, color: NextColors.p4, stroke: 1.9),
          const SizedBox(width: 7),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12.5, color: NextColors.p3)),
          ),
        ]),
      );
}

/// A change of matches as NipaPlay previewed it — the work, how many
/// episodes and files, those with progress, the matches now on them, the
/// devices — and the way on or back. [notice] says why it is shown again.
class ImpactCard extends StatefulWidget {
  const ImpactCard({
    super.key,
    required this.title,
    this.image,
    required this.plan,
    required this.action,
    this.danger = false,
    this.notice,
    required this.onConfirm,
    required this.onCancel,
  });
  final String title;
  final String? image;
  final UiAssociation plan;
  final String action;
  final bool danger;
  final String? notice;
  final Future<void> Function() onConfirm;
  final VoidCallback onCancel;

  @override
  State<ImpactCard> createState() => _ImpactCardState();
}

class _ImpactCardState extends State<ImpactCard> {
  bool _busy = false;

  Future<void> _confirm() async {
    setState(() => _busy = true);
    await widget.onConfirm();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final others = [
      for (final w in plan.works)
        if (w != widget.title) w
    ];
    Widget stat(int n, String label) => Expanded(
          child: Column(children: [
            Text('$n',
                style: NextText.num(24,
                    weight: FontWeight.w700,
                    color: n == 0 ? NextColors.p4 : NextColors.paper)),
            const SizedBox(height: 2),
            Text(label, style: NextText.sans(11.5, color: NextColors.p3)),
          ]),
        );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: NextMotion.ease,
      builder: (context, s, child) => Transform.scale(scale: s, child: child),
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        decoration: BoxDecoration(
          color: const Color(0xF216161D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 16))
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              if (widget.image != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                      width: 34,
                      height: 51,
                      child: NextImage(widget.image, shape: ArtShape.poster)),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(16, weight: FontWeight.w600)),
              ),
            ]),
            for (final w in others)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  const SizedBox(width: 2),
                  const NextIcon(NextGlyph.plus, size: 12, color: NextColors.p3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(w,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(13, color: NextColors.p2)),
                  ),
                ]),
              ),
            const SizedBox(height: 18),
            Row(children: [
              stat(plan.episodes, '剧集'),
              stat(plan.files, '文件'),
              stat(plan.watched, '有进度'),
            ]),
            if (plan.sources.isNotEmpty ||
                plan.devices.any((d) => d != null)) ...[
              const SizedBox(height: 16),
              Row(children: [
                for (final s in plan.sources) ...[
                  TagChip(s),
                  const SizedBox(width: 6),
                ],
                if (plan.devices.any((d) => d != null))
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: DeviceMark([
                        for (final d in {...plan.devices})
                          UiDevice(name: d ?? '本机')
                      ]),
                    ),
                  ),
              ]),
            ],
            if (widget.notice != null) ...[
              const SizedBox(height: 14),
              Text(widget.notice!,
                  style: NextText.sans(12.5, color: NextColors.accent2)),
            ],
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              PillButton(label: '取消', onTap: _busy ? null : widget.onCancel),
              const SizedBox(width: 10),
              if (widget.danger)
                DangerButton(
                    label: widget.action, busy: _busy, onTap: _confirm)
              else
                PillButton(
                    label: widget.action,
                    primary: true,
                    busy: _busy,
                    onTap: _confirm),
            ]),
          ],
        ),
      ),
    );
  }
}

/// A quiet rounded group of rows.
class ManageGroup extends StatelessWidget {
  const ManageGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x08FFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: NextColors.line),
        ),
        child: Column(children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0)
              Container(
                  height: 1,
                  margin: const EdgeInsets.only(left: 16),
                  color: NextColors.line),
            child,
          ],
        ]),
      );
}

/// A tiny label: a format, where a subtitle is.
class TagChip extends StatelessWidget {
  const TagChip(this.text, {super.key, this.color = NextColors.p3});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: NextColors.line2),
        ),
        child: Text(text,
            style: NextText.sans(10.5,
                weight: FontWeight.w500, color: color, letterSpacing: 0.3)),
      );
}

/// A word that is a link: “屏蔽词 ›”.
class LinkText extends StatelessWidget {
  const LinkText(this.text, {super.key, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: text,
        pressScale: 0.98,
        builder: (context, hovered) =>
            Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text,
              style: NextText.sans(12.5,
                  color: hovered ? NextColors.paper : NextColors.p2)),
          const SizedBox(width: 2),
          NextIcon(NextGlyph.chevronRight,
              size: 13, color: hovered ? NextColors.paper : NextColors.p3),
        ]),
      );
}

/// “1.3 GB”.
String fileSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v >= 100 || i == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[i]}';
}

/// “3,214”.
String countText(int n) => n >= 10000
    ? '${(n / 10000).toStringAsFixed(n >= 100000 ? 0 : 1)} 万'
    : n.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

/// “+1.5 秒”, “−2 秒”, “0”.
String offsetText(Duration d) {
  final s = d.inMilliseconds / 1000;
  if (s == 0) return '0';
  final text = s == s.roundToDouble() ? s.toStringAsFixed(0) : s.toStringAsFixed(1);
  return s > 0 ? '+$text 秒' : '−${text.substring(1)} 秒';
}
