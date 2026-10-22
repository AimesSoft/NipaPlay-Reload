import '../../ui_data/ui_data.dart';
import 'chat_context.dart';

/// One thing Nipa did in a turn.
sealed class ActivityStep {
  ActivityStep(this.id);
  final String id;
  bool get running;
}

/// Its thinking, as the text arrives (merged).
final class ThoughtStep extends ActivityStep {
  ThoughtStep(super.id, {this.startedAt});
  final text = StringBuffer();

  /// When it was watched thinking (not known from history).
  final DateTime? startedAt;
  DateTime? endedAt;

  /// While the turn runs and this is the latest step.
  @override
  bool get running => _running;
  set running(bool value) {
    if (_running && !value && startedAt != null) endedAt ??= DateTime.now();
    _running = value;
  }

  bool _running = true;

  Duration? get took => startedAt == null || endedAt == null
      ? null
      : endedAt!.difference(startedAt!);
}

/// A shell command: what ran, its output, how it ended.
final class CommandStep extends ActivityStep {
  CommandStep(super.id, this.command);
  String command;
  final output = StringBuffer();
  int? exitCode;
  @override
  bool running = true;

  /// Its output is unfolded.
  bool outputShown = false;
}

/// Another tool (web search, a file change, an MCP call).
final class ToolStep extends ActivityStep {
  ToolStep(super.id, this.label);
  String label;
  @override
  bool running = true;
}

/// A turn reads, in order: what you said, what Nipa said along the way,
/// the steps between, its answer.
sealed class TurnPart {}

/// Something you said: the turn's input, or more said while it ran.
final class SaidPart extends TurnPart {
  SaidPart(this.text,
      {this.about, this.watched, this.files = const [], this.echoed = true});
  final String text;

  /// The work it was asked about.
  final String? about;

  /// What played under the conversation when it was said, as
  /// [Watching.named] names it.
  final String? watched;
  final List<String> files;

  /// Codex has it (shown before that, as soon as you send).
  bool echoed;
}

/// Something Nipa said.
final class ReplyPart extends TurnPart {
  ReplyPart(this.id, [this.text = '']);
  final String id;
  String text;
}

/// Work handed to a helper (Codex's own sub-agents): sent off, waited
/// for, told more.
final class HelperStep extends ActivityStep {
  HelperStep(super.id, this.tool);
  String tool;

  /// What the helper was asked to do.
  String prompt = '';

  /// The helpers' threads, to open their conversations.
  List<String> threads = const [];
  @override
  bool running = true;
}

/// Steps in a row, between two things said.
final class StepsPart extends TurnPart {
  final steps = <ActivityStep>[];

  /// Unfolded to the steps themselves.
  bool open = false;
}

/// One turn as it is shown. It is fed the host's display events (already
/// redacted there) or rebuilt from Codex's history.
class ChatTurn {
  ChatTurn({this.id, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  String? id;

  /// The session it runs in, when watched from elsewhere.
  String? threadId;
  DateTime startedAt;
  DateTime? endedAt;

  /// From history, where the clock was not watched.
  Duration? recorded;

  /// `inProgress`, `completed`, `interrupted`, `failed`; `queued` while what
  /// you said waits for another turn to end.
  String status = 'inProgress';

  /// NipaPlay started it for Nipa (a follow-up, a schedule).
  bool followup = false;
  final parts = <TurnPart>[];
  List<UiCard> cards = const [];

  /// Its folded work is open again.
  bool unfolded = false;

  bool get running => status == 'inProgress' || status == 'queued';
  bool get queued => status == 'queued';

  // —— The clock ——

  /// Time spent waiting for your answer, which is not working.
  Duration _waited = Duration.zero;
  DateTime? _waitingSince;
  bool get waiting => _waitingSince != null;

  Duration elapsed([DateTime? now]) {
    if (recorded case final r?) return r;
    final end = endedAt ?? now ?? DateTime.now();
    final waiting =
        _waitingSince == null ? Duration.zero : end.difference(_waitingSince!);
    final d = end.difference(startedAt) - _waited - waiting;
    return d.isNegative ? Duration.zero : d;
  }

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

  // —— What it amounts to ——

  /// Nipa's answer: what it said last, once the turn is over and nothing
  /// was done after it.
  ReplyPart? get answer {
    if (running) return null;
    final last = parts.lastOrNull;
    return last is ReplyPart && last.text.trim().isNotEmpty ? last : null;
  }

  /// Folded away once the turn is over: everything but what you said and
  /// the answer, until the fold is opened.
  bool folded(TurnPart part) {
    if (unfolded || running || part is SaidPart) return false;
    return !identical(part, answer);
  }

  /// There is something to fold.
  bool get foldable {
    if (running) return false;
    final answer = this.answer;
    return parts.any((p) => p is! SaidPart && !identical(p, answer));
  }

  Iterable<ActivityStep> get steps =>
      parts.whereType<StepsPart>().expand((p) => p.steps);

  /// What it is doing now: the running command's or tool's phrase
  /// (“查资料”), else null (thinking).
  String? get doing {
    for (final s in steps.toList().reversed) {
      if (s is CommandStep && s.running) return phrase(s);
      if (s is ToolStep && s.running) return phrase(s);
    }
    return null;
  }

  /// The last thing Nipa said in it.
  String get lastWords {
    for (final p in parts.reversed) {
      if (p is ReplyPart && p.text.trim().isNotEmpty) return p.text;
    }
    return '';
  }

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

  ReplyPart? _reply(String id) {
    for (final p in parts) {
      if (p is ReplyPart && p.id == id) return p;
    }
    return null;
  }

  /// A step goes into the steps since the last thing said.
  S _add<S extends ActivityStep>(S step) {
    for (final s in steps) {
      if (s is ThoughtStep) s.running = false;
    }
    final last = parts.lastOrNull;
    final group = last is StepsPart ? last : (StepsPart()..open = false);
    if (!identical(group, last)) parts.add(group);
    group.steps.add(step);
    return step;
  }

  ReplyPart _replyOrNew(String id) {
    final found = _reply(id);
    if (found != null) return found;
    for (final s in steps) {
      if (s is ThoughtStep) s.running = false;
    }
    final created = ReplyPart(id);
    parts.add(created);
    return created;
  }

  /// What you said, from a user message item; null for a turn NipaPlay
  /// started for Nipa.
  static SaidPart? saidOf(Map item) {
    final content = item['content'];
    final raw = content is List
        ? content
            .whereType<Map>()
            .where((part) => part['type'] == 'text')
            .map((part) => part['text'] as String? ?? '')
            .join()
        : (item['text'] as String? ?? '');
    if (ChatContext.isFollowup(raw)) return null;
    final text = ChatContext.strip(raw);
    final files = ChatContext.files(raw);
    if (text.isEmpty && files.isEmpty) return null;
    return SaidPart(text,
        about: ChatContext.aboutTitle(raw),
        watched: ChatContext.watched(raw),
        files: files);
  }

  static bool _isFollowupItem(Map item) {
    final content = item['content'];
    final raw = content is List
        ? content
            .whereType<Map>()
            .map((part) => part['text'] as String? ?? '')
            .join()
        : (item['text'] as String? ?? '');
    return ChatContext.isFollowup(raw);
  }

  /// Applies one display event of this turn; true when something changed.
  bool apply(String method, Map params) {
    switch (method) {
      case 'turn/started':
        final turn = params['turn'] as Map? ?? const {};
        id = turn['id'] as String? ?? id;
        if (status == 'queued') {
          status = 'inProgress';
          startedAt = DateTime.now();
        }
        return true;
      case 'turn/completed':
        final turn = params['turn'] as Map? ?? const {};
        endedAt = DateTime.now();
        endWait(endedAt);
        final s = turn['status'] as String?;
        status = turn['error'] != null
            ? 'failed'
            : (s == null || s == 'inProgress' ? 'completed' : s);
        _settle();
        return true;
      case 'host/reasoning':
        final key = params['key'] as String? ?? '';
        final id = key.split(':').first;
        final delta = params['delta'] as String? ?? '';
        if (id.isEmpty || delta.isEmpty) return false;
        final step = _find<ThoughtStep>(id) ??
            _add(ThoughtStep(id, startedAt: DateTime.now()));
        step.text.write(delta);
        return true;
      case 'item/commandExecution/outputDelta':
        final step = _find<CommandStep>(params['itemId'] as String? ?? '');
        if (step == null) return false;
        step.output.write(params['delta'] as String? ?? '');
        return true;
      case 'item/agentMessage/delta':
        final id = params['itemId'] as String?;
        final delta = params['delta'] as String? ?? '';
        if (id == null || delta.isEmpty) return false;
        _replyOrNew(id).text += delta;
        return true;
    }
    if (method != 'item/started' && method != 'item/completed') return false;
    final item = params['item'] as Map;
    final itemId = '${item['id']}';
    final done = method == 'item/completed';
    switch (_itemType(params)) {
      case 'userMessage':
        return _said(item);
      case 'agentMessage':
        final reply = _replyOrNew(itemId);
        final text = item['text'] as String? ?? '';
        if (text.isNotEmpty) reply.text = text;
        return true;
      case 'reasoning':
        final text = [
          ...(item['summary'] as List? ?? const []),
          if ((item['summary'] as List? ?? const []).isEmpty)
            ...(item['content'] as List? ?? const []),
        ].map((p) => p is Map ? '${p['text'] ?? ''}' : '$p').join('\n\n');
        final existing = _find<ThoughtStep>(itemId);
        if (existing == null && text.trim().isEmpty && done) return false;
        final step = existing ??
            _add(ThoughtStep(itemId,
                startedAt: _replaying ? null : DateTime.now()));
        if (done && text.trim().isNotEmpty) {
          step.text
            ..clear()
            ..write(text.trim());
        }
        return true;
      case 'commandExecution':
        final command = _commandOf(item);
        if (hiddenCommand(command)) return false;
        final step =
            _find<CommandStep>(itemId) ?? _add(CommandStep(itemId, command));
        if (command.isNotEmpty) step.command = command;
        if (done ||
            (item['status'] != null && item['status'] != 'inProgress')) {
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
      case 'collabAgentToolCall':
        final step = _find<HelperStep>(itemId) ??
            _add(HelperStep(itemId, '${item['tool'] ?? ''}'));
        step.tool = '${item['tool'] ?? step.tool}';
        if (item['prompt'] case final String prompt) step.prompt = prompt;
        if (item['receiverThreadIds'] case final List ids when ids.isNotEmpty) {
          step.threads = [for (final id in ids) '$id'];
        }
        if (done ||
            (item['status'] != null && item['status'] != 'inProgress')) {
          step.running = false;
        }
        return true;
      case 'webSearch' || 'mcpToolCall' || 'dynamicToolCall' || 'fileChange':
        final label = switch (_itemType(params)) {
          'webSearch' => '搜索网页',
          'fileChange' => '改文件',
          _ => '用 ${item['tool'] ?? item['name'] ?? '工具'}',
        };
        final step = _find<ToolStep>(itemId) ?? _add(ToolStep(itemId, label));
        if (done) step.running = false;
        return true;
    }
    return false;
  }

  /// A user message: what was shown already as you sent it, more said
  /// while it ran, or the input of a turn NipaPlay started.
  bool _said(Map item) {
    final said = saidOf(item);
    if (said == null) {
      if (_isFollowupItem(item) && !parts.any((p) => p is SaidPart)) {
        followup = true;
        return true;
      }
      return false;
    }
    for (final p in parts) {
      if (p is SaidPart &&
          p.text == said.text &&
          p.files.length == said.files.length) {
        if (p.echoed) return false;
        p.echoed = true;
        return true;
      }
    }
    parts.add(said);
    return true;
  }

  /// Nothing runs once the turn is over.
  void _settle() {
    for (final s in steps) {
      switch (s) {
        case HelperStep():
          s.running = false;
        case CommandStep():
          s.running = false;
        case ToolStep():
          s.running = false;
        case ThoughtStep():
          s.running = false;
      }
    }
  }

  /// Being rebuilt from history: no clocks.
  bool _replaying = false;

  /// A turn from Codex's history, in its own order.
  static ChatTurn fromHistory(Map turn) {
    final started = turn['startedAt'];
    final ms = turn['durationMs'];
    final status = turn['error'] != null
        ? 'failed'
        : turn['status'] as String? ?? 'completed';
    final t = ChatTurn(
        id: turn['id'] as String?,
        startedAt: started is num
            ? DateTime.fromMillisecondsSinceEpoch((started * 1000).round())
            : null)
      ..status = status;
    if (status != 'inProgress') {
      t.recorded = ms is num ? Duration(milliseconds: ms.round()) : null;
      t.endedAt = t.recorded == null ? t.startedAt : null;
    }
    t._replaying = true;
    for (final item in (turn['items'] as List? ?? const []).whereType<Map>()) {
      t.apply('item/completed', {'item': item});
    }
    t._replaying = false;
    if (!t.running) t._settle();
    return t;
  }

  // —— Saying it ——

  /// “1m 23s”, “45s”.
  static String span(Duration d) {
    final s = d.inSeconds;
    if (s < 60) return '${s}s';
    final m = s ~/ 60;
    if (m < 60) return '${m}m ${s % 60}s';
    return '${m ~/ 60}h ${m % 60}m';
  }

  /// m:ss for the live line.
  static String clock(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// A steps group in a few words: “查资料、看片库 · 5 步”; the first of
  /// its thoughts when it only thought.
  static String summary(StepsPart group) {
    final phrases = <String>[];
    var n = 0;
    for (final s in group.steps) {
      final p = phrase(s);
      if (p == null) continue;
      n++;
      if (!phrases.contains(p)) phrases.add(p);
    }
    if (n == 0) {
      final thoughts = group.steps.whereType<ThoughtStep>();
      if (thoughts.any((t) => t.running)) return 'Thinking';
      final took = thoughts.fold<Duration?>(null, (sum, t) {
        final d = t.took;
        return d == null ? sum : (sum ?? Duration.zero) + d;
      });
      return took == null || took.inSeconds < 1
          ? 'Thought'
          : 'Thought for ${span(took)}';
    }
    final head = phrases.take(2).join('、');
    return n > 1 ? '$head · $n 步' : head;
  }

  /// What a step was, in a short phrase; null for a thought.
  static String? phrase(ActivityStep step) => switch (step) {
        ThoughtStep() => null,
        CommandStep(:final command) => verb(command),
        ToolStep(:final label) => label,
        HelperStep(:final tool) => switch (tool) {
            'spawnAgent' => '派帮手',
            'wait' => '等帮手',
            'sendInput' => '给帮手补充',
            'closeAgent' => '收回帮手',
            _ => '和帮手协作',
          },
      };

  /// A helper's work in a few words, from what it was asked: its first
  /// sentence, without a “任务：” label.
  static String helperTitle(String prompt) {
    var line = prompt.trim().split('\n').first.trim();
    line = line.replaceFirst(RegExp(r'^(任务|目标|Task)\s*[：:]\s*'), '');
    final end = line.indexOf(RegExp(r'[。！？.!?；;]'));
    if (end > 0) line = line.substring(0, end);
    return line.length > 36 ? '${line.substring(0, 36)}…' : line;
  }

  /// The command without the login-shell wrapper Codex puts around it.
  static String bare(String command) {
    final wrapped = RegExp(r'''^\S*sh\s+-l?c\s+(['"])([\s\S]*)\1\s*$''')
        .firstMatch(command);
    return (wrapped?.group(2) ?? command).trim();
  }

  static final _call = RegExp(
      r'(?:^|[\s;&|(])(?:\./|python3?\s+)?nipa\s+(call|status|list|describe|query|watch)\b\s*([\w.]+)?');

  /// `nipa` calls the interface has a word for, by action or prefix.
  static const _verbs = <String, String>{
    'download.add': '添加下载',
    'download.preview': '看资源',
    'download.read': '看下载',
    'download.pause': '暂停下载',
    'download.resume': '继续下载',
    'download.wait_files': '等下载',
    'download.': '管理下载',
    'media.metadata.search': '查资料',
    'media.metadata.search_batch': '查资料',
    'media.metadata.override': '改资料',
    'media.metadata.': '整理资料',
    'media.artwork.': '换图片',
    'media.library.scan': '扫描片库',
    'media.library.': '翻片库',
    'media.identity.': '认作品',
    'media.hash.match': '认文件',
    'media.files.': '看文件',
    'media.sources.': '看媒体服务器',
    'danmaku.fetch': '取弹幕',
    'danmaku.search': '找弹幕',
    'danmaku.': '处理弹幕',
    'playback.': '控制播放',
    'history.': '看观看记录',
    'task.wait': '等任务',
    'task.': '看任务',
    'followup.register': '记下之后要做的事',
    'followup.': '看后续',
    'settings.set': '改设置',
    'settings.': '看设置',
    'accounts.': '看账号',
    'ui.shelves.': '摆书架',
    'ui.open': '打开页面',
    'ui.capture': '看画面',
    'state.': '查状态',
    'mesh.': '联系其他设备',
    'plugins.': '看插件',
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
          return '看 NipaPlay 的情况';
        case 'list' || 'describe':
          return '看能做什么';
        case 'watch':
          return '等任务';
        case 'query':
          return '查状态';
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
    return '运行命令';
  }
}
