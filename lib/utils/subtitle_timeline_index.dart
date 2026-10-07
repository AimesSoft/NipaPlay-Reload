import 'subtitle_parser.dart';

/// Immutable interval index. Keeps source order for overlapping/duplicate cues,
/// including inclusive end times, and caches text between cue boundaries.
class SubtitleTimelineIndex {
  SubtitleTimelineIndex(Iterable<SubtitleEntry> entries) {
    final cues = <_Cue>[];
    var order = 0;
    final boundaries = <int>{};
    for (final entry in entries) {
      final text = entry.content.trim();
      if (text.isNotEmpty && entry.endTimeMs >= entry.startTimeMs) {
        cues.add(_Cue(entry.startTimeMs, entry.endTimeMs, text, order));
        boundaries.add(entry.startTimeMs);
        boundaries.add(entry.endTimeMs + 1);
      }
      order++;
    }
    cues.sort((a, b) => a.start.compareTo(b.start));
    _root = _build(cues, 0, cues.length);
    _boundaries = boundaries.toList()..sort();
  }

  late final _Node? _root;
  late final List<int> _boundaries;
  int? _from;
  int? _until;
  bool _hasCachedText = false;
  String _text = '';

  String textAt(int positionMs) {
    if (_hasCachedText &&
        (_from == null || positionMs >= _from!) &&
        (_until == null || positionMs < _until!)) {
      return _text;
    }
    var low = 0;
    var high = _boundaries.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_boundaries[mid] <= positionMs) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    _from = low == 0 ? null : _boundaries[low - 1];
    _until = low == _boundaries.length ? null : _boundaries[low];
    final matches = <_Cue>[];
    _query(_root, positionMs, matches);
    matches.sort((a, b) => a.order.compareTo(b.order));
    _text = matches.map((cue) => cue.text).toSet().join('\n');
    _hasCachedText = true;
    return _text;
  }

  static _Node? _build(List<_Cue> cues, int start, int end) {
    if (start >= end) return null;
    final mid = (start + end) ~/ 2;
    return _Node(
        cues[mid], _build(cues, start, mid), _build(cues, mid + 1, end));
  }

  static void _query(_Node? node, int time, List<_Cue> matches) {
    if (node == null || node.maxEnd < time) return;
    _query(node.left, time, matches);
    if (node.cue.start > time) return;
    if (node.cue.end >= time) matches.add(node.cue);
    _query(node.right, time, matches);
  }
}

class _Cue {
  const _Cue(this.start, this.end, this.text, this.order);
  final int start;
  final int end;
  final String text;
  final int order;
}

class _Node {
  _Node(this.cue, this.left, this.right) {
    var end = cue.end;
    if (left != null && left!.maxEnd > end) end = left!.maxEnd;
    if (right != null && right!.maxEnd > end) end = right!.maxEnd;
    maxEnd = end;
  }
  final _Cue cue;
  final _Node? left;
  final _Node? right;
  late final int maxEnd;
}
