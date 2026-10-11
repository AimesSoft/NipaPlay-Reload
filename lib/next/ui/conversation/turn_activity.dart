import '../widgets/words.dart';

/// One thing Nipa did in a turn.
sealed class ActivityStep {
  ActivityStep(this.id);
  final String id;
}

/// Its thinking, as the summary text arrives (merged).
final class ThoughtStep extends ActivityStep {
  ThoughtStep(super.id);
  final text = StringBuffer();
}

/// A shell command: what ran, its output, how it ended.
final class CommandStep extends ActivityStep {
  CommandStep(super.id, this.command);
  String command;
  final output = StringBuffer();
  int? exitCode;
  bool running = true;

  /// Its output is unfolded.
  bool outputShown = false;
}

/// Another tool (web search, a file change, an MCP call).
final class ToolStep extends ActivityStep {
  ToolStep(super.id, this.label);
  String label;
  bool running = true;
}

/// What Nipa is doing in one turn, from the host's display events (already
/// redacted there): the steps, how long it has been going, one line for it
/// now and one when it is over.
class TurnActivity {
  TurnActivity({this.turnId, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  String? turnId;
  DateTime startedAt;
  DateTime? endedAt;

  /// From history, where the clock was not watched.
  Duration? recorded;

  /// Time spent waiting for your answer, which is not thinking.
  Duration _waited = Duration.zero;
  DateTime? _waitingSince;
  bool get waiting => _waitingSince != null;
  final steps = <ActivityStep>[];

  /// The steps are unfolded under the line.
  bool shown = false;

  bool get running => endedAt == null && recorded == null;

  /// How long Nipa has been at it, without the time it waited for you.
  Duration elapsed([DateTime? now]) {
    if (recorded case final r?) return r;
    final end = endedAt ?? now ?? DateTime.now();
    final waiting = _waitingSince == null
        ? Duration.zero
        : end.difference(_waitingSince!);
    return end.difference(startedAt) - _waited - waiting;
  }

  /// Nipa asked something; the clock stops until [endWait].
  void beginWait([DateTime? at]) {
    if (!running || _waitingSince != null) return;
    _waitingSince = at ?? DateTime.now();
  }

  void endWait([DateTime? at]) {
    final since = _waitingSince;
    if (since == null) return;
    _waited += (at ?? endedAt ?? DateTime.now()).difference(since);
    _waitingSince = null;
  }

  /// Steps worth counting and listing (the card mechanism is not one).
  int get stepCount => steps.where((s) => s is! ThoughtStep).length;

  // —— Reading events ——

  static String? _itemType(Map params) =>
      params['item'] is Map ? params['item']['type'] as String? : null;

  static String _commandOf(Map item) {
    final command = item['command'];
    if (command is String) return command;
    if (command is List) return command.join(' ');
    return '';
  }

  T? _find<T extends ActivityStep>(String id) {
    for (final s in steps) {
      if (s is T && s.id == id) return s;
    }
    return null;
  }

  /// Applies one display event of this turn; true when something changed.
  bool apply(String method, Map params) {
    switch (method) {
      case 'turn/started':
        final turn = params['turn'] as Map? ?? const {};
        turnId = turn['id'] as String? ?? turnId;
        return false;
      case 'turn/completed':
        endedAt = DateTime.now();
        endWait(endedAt);
        for (final s in steps) {
          if (s is CommandStep) s.running = false;
          if (s is ToolStep) s.running = false;
        }
        return true;
      case 'host/reasoning':
        final key = params['key'] as String? ?? '';
        final id = key.split(':').first;
        final delta = params['delta'] as String? ?? '';
        if (id.isEmpty || delta.isEmpty) return false;
        final step = _find<ThoughtStep>(id) ?? _add(ThoughtStep(id));
        step.text.write(delta);
        return true;
      case 'item/commandExecution/outputDelta':
        final step = _find<CommandStep>(params['itemId'] as String? ?? '');
        if (step == null) return false;
        step.output.write(params['delta'] as String? ?? '');
        return true;
    }
    if (method != 'item/started' && method != 'item/completed') return false;
    final item = params['item'] as Map;
    final id = '${item['id']}';
    final done = method == 'item/completed';
    switch (_itemType(params)) {
      case 'reasoning':
        final text = [
          ...(item['summary'] as List? ?? const []),
          if ((item['summary'] as List? ?? const []).isEmpty)
            ...(item['content'] as List? ?? const []),
        ].map((p) => p is Map ? '${p['text'] ?? ''}' : '$p').join('\n\n');
        final step = _find<ThoughtStep>(id) ?? _add(ThoughtStep(id));
        if (done && text.trim().isNotEmpty) {
          step.text
            ..clear()
            ..write(text.trim());
        }
        return true;
      case 'commandExecution':
        final command = _commandOf(item);
        if (hiddenCommand(command)) return false;
        final step = _find<CommandStep>(id) ?? _add(CommandStep(id, command));
        if (command.isNotEmpty) step.command = command;
        if (done) {
          step.running = false;
          step.exitCode = item['exitCode'] as int?;
          final output = item['aggregatedOutput'] as String? ?? '';
          if (output.isNotEmpty) {
            step.output
              ..clear()
              ..write(output);
          }
        }
        return true;
      case 'webSearch' || 'mcpToolCall' || 'dynamicToolCall' || 'fileChange':
        final label = switch (_itemType(params)) {
          'webSearch' => '在搜索网页',
          'fileChange' => '在改文件',
          _ => '在用 ${item['tool'] ?? item['name'] ?? '工具'}',
        };
        final step = _find<ToolStep>(id) ?? _add(ToolStep(id, label));
        if (done) step.running = false;
        return true;
    }
    return false;
  }

  S _add<S extends ActivityStep>(S step) {
    steps.add(step);
    return step;
  }

  /// A turn from Codex's history: its time, and the steps it kept.
  static TurnActivity? fromHistory(Map turn) {
    final ms = turn['durationMs'];
    final activity = TurnActivity(turnId: turn['id'] as String?)
      ..recorded = ms is num ? Duration(milliseconds: ms.round()) : null;
    for (final item in (turn['items'] as List? ?? const []).whereType<Map>()) {
      activity.apply('item/completed', {'item': item});
    }
    if (activity.recorded == null && activity.steps.isEmpty) return null;
    activity.recorded ??= Duration.zero;
    return activity;
  }

  // —— Saying it ——

  /// Now: “在想”, “在查资料”, “在运行 python3 tools/mikan.py”.
  String get doing {
    for (final s in steps.reversed) {
      if (s is CommandStep && s.running) return verb(s.command);
      if (s is ToolStep && s.running) return s.label;
    }
    return '在想';
  }

  /// Afterwards: “想了 32 秒 · 5 步”.
  String get summary {
    final time = '想了 ${Words.duration(elapsed())}';
    final n = stepCount;
    return n == 0 ? time : '$time · $n 步';
  }

  /// m:ss for the live line.
  static String clock(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// The command without the login-shell wrapper Codex puts around it.
  static String bare(String command) {
    final wrapped =
        RegExp(r'''^\S*sh\s+-l?c\s+(['"])([\s\S]*)\1\s*$''').firstMatch(command);
    return (wrapped?.group(2) ?? command).trim();
  }

  static final _call = RegExp(r'(?:^|[\s;&|(])(?:\./|python3?\s+)?nipa\s+(call|status|list|describe)\b\s*([\w.]+)?');

  /// `nipa` calls the interface has a word for, by action or prefix.
  static const _verbs = <String, String>{
    'download.add': '在添加下载',
    'download.preview': '在看资源',
    'download.read': '在看下载',
    'download.pause': '在暂停下载',
    'download.resume': '在继续下载',
    'download.': '在管理下载',
    'media.metadata.search': '在查资料',
    'media.metadata.search_batch': '在查资料',
    'media.metadata.': '在整理资料',
    'media.library.scan': '在扫描片库',
    'media.library.': '在翻片库',
    'media.identity.': '在认作品',
    'media.hash.match': '在认文件',
    'media.files.': '在看文件',
    'media.sources.': '在看媒体服务器',
    'danmaku.fetch': '在取弹幕',
    'danmaku.search': '在找弹幕',
    'danmaku.': '在处理弹幕',
    'playback.': '在控制播放',
    'history.': '在看观看记录',
    'task.wait': '在等任务',
    'task.': '在看任务',
    'followup.register': '在记下之后要做的事',
    'followup.': '在看后续',
    'settings.set': '在改设置',
    'settings.': '在看设置',
    'accounts.': '在看账号',
    'ui.shelves.': '在摆书架',
    'ui.open': '在打开',
    'ui.capture': '在看画面',
    'state.': '在查状态',
    'mesh.': '在联系其他设备',
    'plugins.': '在看插件',
  };

  /// The card mechanism is not something Nipa “does”.
  static bool hiddenCommand(String command) =>
      _call.firstMatch(bare(command))?.group(2) == 'ui.present';

  static String verb(String command) {
    final text = bare(command);
    final call = _call.firstMatch(text);
    if (call != null) {
      final action = call.group(2) ?? '';
      switch (call.group(1)) {
        case 'status':
          return '在看 NipaPlay 的情况';
        case 'list' || 'describe':
          return '在看能做什么';
      }
      if (_verbs[action] case final v?) return v;
      String? best;
      for (final key in _verbs.keys) {
        if (key.endsWith('.') &&
            action.startsWith(key) &&
            (best == null || key.length > best.length)) {
          best = key;
        }
      }
      if (best != null) return _verbs[best]!;
    }
    final line = text.split('\n').first;
    return '在运行 ${line.length > 40 ? '${line.substring(0, 40)}…' : line}';
  }
}
