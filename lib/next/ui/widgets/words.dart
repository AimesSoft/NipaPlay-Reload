import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/tokens.dart';

/// Short natural phrases the interface builds from data. Nothing here may
/// contain IDs, sources or process details.
abstract final class Words {
  /// “第 3 集”; null when the episode has no number, so nothing is said.
  static String? episode(int? number) =>
      number == null ? null : '第 $number 集';

  /// Whether a play button makes sense: NipaPlay can play that episode.
  static bool canPlay(UiWork work, [UiEpisode? episode]) =>
      (episode ?? work.next)?.playable ?? false;

  static String play(UiWork work) => switch (episode(work.next?.number)) {
        final number? when !work.film => '播放 $number',
        _ => '播放',
      };

  static String remaining(Duration? left) {
    if (left == null) return '';
    if (left.inSeconds < 60) return '马上就好';
    if (left.inMinutes < 60) return '还要 ${left.inMinutes} 分钟';
    final h = left.inHours;
    final m = left.inMinutes % 60;
    return m == 0 ? '还要 $h 小时' : '还要 $h 小时 $m 分钟';
  }

  /// [task] as a row says it: one another device runs, that device first.
  static String taskLine(UiTask task) => task.device == null
      ? Words.task(task)
      : '${task.device} · ${Words.task(task)}';

  static String task(UiTask task) {
    if (task.type == 'download' && task.currentActivity != null) {
      return task.currentActivity!;
    }
    return switch (task.state) {
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
  }

  /// An episode's length, “24 分”; null when it is not known (no length,
  /// or a length of nothing), so nothing is said.
  static String? runtime(Duration? d) => d == null || d <= Duration.zero
      ? null
      : '${d.inMinutes < 1 ? 1 : d.inMinutes} 分';

  /// A film's length, “1 小时 32 分”, “52 分钟”; null when it is not
  /// known.
  static String? length(Duration? d) {
    if (d == null || d <= Duration.zero) return null;
    final m = (d.inSeconds / 60).round().clamp(1, 1 << 31);
    if (m < 60) return '$m 分钟';
    return m % 60 == 0 ? '${m ~/ 60} 小时' : '${m ~/ 60} 小时 ${m % 60} 分';
  }

  /// “第一季”, “第二季”…; season 0 holds the specials.
  static String season(int? season) {
    if (season == null) return '剧集';
    if (season == 0) return '特别篇';
    return '第${_chinese(season)}季';
  }

  static String _chinese(int n) {
    const digits = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];
    if (n < 10) return digits[n];
    if (n < 20) return '十${n % 10 == 0 ? '' : digits[n % 10]}';
    if (n < 100) {
      return '${digits[n ~/ 10]}十${n % 10 == 0 ? '' : digits[n % 10]}';
    }
    return '$n';
  }

  /// How long something took: “32 秒”, “2 分 5 秒”, “1 小时 3 分”.
  static String duration(Duration d) {
    final s = (d.inMilliseconds / 1000).round().clamp(1, 1 << 31);
    if (s < 60) return '$s 秒';
    if (s < 3600) return s % 60 == 0 ? '${s ~/ 60} 分钟' : '${s ~/ 60} 分 ${s % 60} 秒';
    final m = (s % 3600) ~/ 60;
    return m == 0 ? '${s ~/ 3600} 小时' : '${s ~/ 3600} 小时 $m 分';
  }

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

/// `.meta`: ★ 8.8 · 2023 · 奇幻 · 冒险 · 28 集; a film says its length
/// instead.
class MetaLine extends StatelessWidget {
  const MetaLine(this.work,
      {super.key,
      this.allRatings = false,
      this.studio = false,
      this.genres = true,
      this.size = 13.5});
  final UiWork work;
  final bool allRatings;
  final bool studio;
  final bool genres;
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
    final shownGenres = genres ? Words.genres(work) : const <String>[];
    if (shownGenres.isNotEmpty) {
      parts.add(Text(shownGenres.join(' · '),
          style: NextText.sans(size, color: NextColors.p2)));
    }
    if (work.film) {
      if (Words.length(work.runtime) case final length?) {
        parts.add(
            NumText(length, style: NextText.sans(size, color: NextColors.p2)));
      }
    } else if (work.episodeCount != null) {
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
