import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/tokens.dart';

/// Short natural phrases the interface builds from data. Nothing here may
/// contain IDs, sources or process details.
abstract final class Words {
  static String episode(int number) => '第 $number 集';

  /// Whether a play button makes sense: NipaPlay can play that episode.
  static bool canPlay(UiWork work, [UiEpisode? episode]) =>
      (episode ?? work.next)?.playable ?? false;

  static String play(UiWork work) =>
      work.next == null ? '播放' : '播放 ${episode(work.next!.number)}';

  static String remaining(Duration? left) {
    if (left == null) return '';
    if (left.inSeconds < 60) return '马上就好';
    if (left.inMinutes < 60) return '还要 ${left.inMinutes} 分钟';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return m == 0 ? '还要 $h 小时' : '还要 $h 小时 $m 分钟';
  }

  static String task(UiTask task) => switch (task.state) {
        UiTaskState.queued => '等着开始',
        UiTaskState.paused => '已暂停',
        UiTaskState.finished => '好了',
        UiTaskState.failed => '没成功',
        UiTaskState.running => task.remaining == null
            ? (task.progress == null
                ? '进行中'
                : '${(task.progress! * 100).round()}%')
            : remaining(task.remaining),
      };

  static String runtime(Duration d) => '${d.inMinutes} 分';

  /// The first sentence, for Nipa's one line after a conversation.
  static String firstSentence(String text) {
    final trimmed = text.trim();
    var depth = 0;
    var end = trimmed.length;
    for (var i = 0; i < trimmed.length; i++) {
      final c = trimmed[i];
      if ('《「『“（('.contains(c)) depth++;
      if ('》」』”）)'.contains(c) && depth > 0) depth--;
      if (depth == 0 && '。！？!?\n'.contains(c)) {
        end = c == '\n' ? i : i + 1;
        break;
      }
    }
    final sentence = trimmed.substring(0, end).trim();
    return sentence.length > 60 ? '${sentence.substring(0, 58)}…' : sentence;
  }

  /// Genres worth showing: the medium itself (“动画”) says nothing here.
  static List<String> genres(UiWork work) =>
      work.genres.where((g) => g != '动画' && g != 'Animation').take(2).toList();
}

/// `.meta`: ★ 8.8 · 2023 · 奇幻 · 冒险 · 28 集
class MetaLine extends StatelessWidget {
  const MetaLine(this.work,
      {super.key,
      this.allRatings = false,
      this.studio = false,
      this.size = 13.5});
  final UiWork work;
  final bool allRatings;
  final bool studio;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    final ratings = allRatings ? work.ratings : work.ratings.take(1);
    var first = true;
    for (final r in ratings) {
      parts.add(first
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              Text('★ ', style: NextText.sans(size, weight: FontWeight.w600)),
              Text(r.value.toStringAsFixed(1),
                  style: NextText.num(size + 1.5, weight: FontWeight.w600)),
            ])
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${r.source} ',
                  style: NextText.sans(size, color: NextColors.p2)),
              Text(r.value.toStringAsFixed(1),
                  style: NextText.num(size, color: NextColors.p2)),
            ]));
      first = false;
    }
    if (work.year != null) {
      parts.add(Text('${work.year}',
          style: NextText.num(size, color: NextColors.p2)));
    }
    final genres = Words.genres(work);
    if (genres.isNotEmpty) {
      parts.add(Text(genres.join(' · '),
          style: NextText.sans(size, color: NextColors.p2)));
    }
    if (work.episodeCount != null) {
      parts.add(Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${work.episodeCount}',
            style: NextText.num(size, color: NextColors.p2)),
        Text(' 集', style: NextText.sans(size, color: NextColors.p2)),
      ]));
    }
    if (studio && work.studio != null && work.studio!.isNotEmpty) {
      parts.add(
          Text(work.studio!, style: NextText.sans(size, color: NextColors.p2)));
    }
    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        children.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: _Dot(),
        ));
      }
      children.add(parts[i]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => Container(
        width: 3,
        height: 3,
        decoration:
            const BoxDecoration(shape: BoxShape.circle, color: NextColors.p4),
      );
}

/// Nipa's sentence with work titles in 《》 set in bold paper.
class NipaSentence extends StatelessWidget {
  const NipaSentence(this.text,
      {super.key, this.style, this.lead, this.maxLines = 2});
  final String text;
  final TextStyle? style;

  /// A work title to lead with when the sentence does not name one.
  final String? lead;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? NextText.sans(15.5, color: const Color(0xE6F5F1EA));
    final bold =
        base.copyWith(fontWeight: FontWeight.w600, color: NextColors.paper);
    final spans = <InlineSpan>[];
    final source =
        (lead != null && !text.contains('《')) ? '《$lead》$text' : text;
    final pattern = RegExp(r'《[^》]+》');
    var at = 0;
    for (final m in pattern.allMatches(source)) {
      if (m.start > at) {
        spans.add(TextSpan(text: source.substring(at, m.start)));
      }
      spans.add(TextSpan(text: m.group(0), style: bold));
      at = m.end;
    }
    if (at < source.length) spans.add(TextSpan(text: source.substring(at)));
    return Text.rich(TextSpan(style: base, children: spans),
        maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}

/// Text whose digits are set in SF with tabular figures, the rest in
/// PingFang, as in the concept's `.num` spans.
class NumText extends StatelessWidget {
  const NumText(this.text, {super.key, required this.style, this.maxLines = 1});
  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final numStyle = NextText.num(style.fontSize ?? 14,
        weight: style.fontWeight ?? FontWeight.w500,
        color: style.color ?? NextColors.paper);
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'[0-9][0-9.:%]*');
    var at = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      spans.add(TextSpan(text: m.group(0), style: numStyle));
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: style, children: spans),
        maxLines: maxLines, overflow: TextOverflow.ellipsis);
  }
}
