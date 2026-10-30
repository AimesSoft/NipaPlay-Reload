import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart'
    show Failure, FailureCode, JsonMap;
import 'package:flutter/foundation.dart';
import '../data/gui_calls.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';

/// Nonmodal, never requests focus on arrival. The queue remains accessible
/// when popups are disabled or a question is hidden.
class AgentInboxOverlay extends StatefulWidget {
  const AgentInboxOverlay(
      {super.key,
      required this.calls,
      required this.events,
      this.peer,
      this.onOpen,
      this.errors,
      this.bottomInset = 0});

  /// Space reserved for the player controls while video is open.
  final double bottomInset;
  final GuiCalls calls;
  final Stream<Map> events;
  final String? Function()? peer;
  final Future<void> Function(JsonMap)? onOpen;
  final ValueListenable<String?>? errors;
  @override
  State<AgentInboxOverlay> createState() => _AgentInboxOverlayState();
}

class _AgentInboxOverlayState extends State<AgentInboxOverlay> {
  Timer? _timer;
  StreamSubscription? _events;
  final _text = TextEditingController();
  List<JsonMap> _items = [];
  bool _loading = false, _acting = false, _expanded = false, _more = false;
  int _limit = 30;
  String? _error, _lastEventError, _lastLoadError;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _events = widget.events.listen(_event);
    widget.errors?.addListener(_externalError);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
    unawaited(_load());
  }

  Future<JsonMap> _call(String action, JsonMap input, [String? peer]) => peer ==
          null
      ? widget.calls.call(action, input, reportFailure: false)
      : widget.calls.call(
          'mesh.invoke', {'deviceId': peer, 'action': action, 'input': input},
          reportFailure: false);

  void _externalError() {
    final error = widget.errors?.value;
    if (error != null) _recordError(error);
  }

  void _event(Map event) {
    final method = event['method'];
    final params = event['params'] as Map? ?? const {};
    final turn = params['turn'] as Map?;
    Object? raw;
    if (method == 'host/error') raw = params['error'] ?? params;
    if (method == 'turn/completed' && turn?['status'] == 'failed') {
      raw = turn?['error'];
    }
    if (method == 'host/liveness') raw = params['latestError'];
    if (raw == null || raw == '') return;
    final body =
        raw is String ? raw : const JsonEncoder.withIndent('  ').convert(raw);
    _recordError(body);
  }

  void _recordError(String body) {
    if (body == _lastEventError) return;
    _lastEventError = body;
    // This is the runner's original UI error payload, never a model summary.
    unawaited(_call('ui.notify', {
      'requestId': 'runtime-${DateTime.now().microsecondsSinceEpoch}',
      'title': '梨花运行失败',
      'body': body,
      'severity': 'error'
    }).then((_) => _load()).catchError((Object e) {
      if (mounted) setState(() => _error = '$body\n\n$e');
    }));
  }

  Future<void> _load() async {
    if (_loading || !mounted) return;
    _loading = true;
    final peers = <String?>[null];
    final peer = widget.peer?.call();
    if (peer != null) peers.add(peer);
    final result = <JsonMap>[];
    var more = false;
    String? loadError;
    for (final peer in peers) {
      try {
        var offset = 0;
        while (offset < _limit) {
          final page = await _call('ui.inbox.list',
              {'offset': offset, 'limit': math.min(30, _limit - offset)}, peer);
          for (final raw in (page['items'] as List).cast<Map>()) {
            result.add({
              ...raw.cast<String, Object?>(),
              '_peer': peer,
              '_popup':
                  page['popupsEnabled'] == true || raw['severity'] == 'error'
            });
          }
          final next = page['nextOffset'] as int?;
          if (next == null) break;
          offset = next;
          if (offset >= _limit) more = true;
        }
      } catch (e) {
        // Keep other devices usable and retain pending input during an outage.
        final fetched =
            result.map((row) => '${row['_peer']}:${row['id']}').toSet();
        result.addAll(_items.where((row) =>
            row['_peer'] == peer &&
            !fetched.contains('${row['_peer']}:${row['id']}')));
        if (!(e is Failure && e.code == FailureCode.notFound)) {
          loadError = rawFailureText(e);
        }
      }
    }
    if (mounted) {
      setState(() {
        _items = result;
        _more = more;
        if (loadError != null && loadError != _lastLoadError) {
          _error = loadError;
        }
        _lastLoadError = loadError;
      });
    }
    _loading = false;
  }

  Future<void> _act(JsonMap row, String action, JsonMap input) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      await _call(action, {'id': row['id'], ...input}, row['_peer'] as String?);
      _text.clear();
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = rawFailureText(e));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _events?.cancel();
    widget.errors?.removeListener(_externalError);
    _text.dispose();
    super.dispose();
  }

  void _send(JsonMap row) {
    if (_acting || _text.text.trim().isEmpty) return;
    _act(row, 'ui.inbox.respond', {'answer': _text.text});
  }

  void _select(JsonMap row) => setState(() {
        _selectedId = '${row['_peer']}:${row['id']}';
        _text.clear();
      });

  Future<void> _open(JsonMap row) async {
    if (row['_peer'] != widget.peer?.call()) {
      setState(() => _error = '请先切换到这条提醒所属的设备。');
      return;
    }
    await widget.onOpen?.call(row);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _expanded
        ? _items
        : _items
            .where((r) => r['hidden'] != true && r['_popup'] == true)
            .toList();
    final row = visible
            .where((r) => '${r['_peer']}:${r['id']}' == _selectedId)
            .firstOrNull ??
        visible.firstOrNull;
    final id = '${row?['_peer']}:${row?['id']}';
    if (_selectedId != id) {
      _selectedId = id;
      _text.clear();
    }
    if (_items.isEmpty && _error == null) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final collapsed = row == null && !_expanded && _error == null;
    final count = '${_items.length}${_more ? '+' : ''}';
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 20, 20 + widget.bottomInset),
          // TextField needs a Material ancestor; it paints nothing itself.
          child: Material(
            type: MaterialType.transparency,
            // The card or the pill comes in; nothing lingers to be pressed
            // on its way out.
            child: TweenAnimationBuilder<double>(
              key: ValueKey(collapsed),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 220),
              curve: NextMotion.ease,
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                    offset: Offset(0, (1 - t) * 10), child: child),
              ),
              child: collapsed
                  ? _Pill(
                      key: const ValueKey('pill'),
                      label: '梨花提醒 · $count',
                      onTap: () => setState(() => _expanded = true))
                  : SizedBox(
                      key: const ValueKey('card'),
                      width: math.min(380, math.max(0, size.width - 36)),
                      child: _card(context, size, visible, row, count),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Size size, List<JsonMap> visible,
      JsonMap? row, String count) {
    final pending = row?['state'] == 'pending';
    final failed = row?['severity'] == 'error';
    final options = [
      for (final o in (row?['options'] as List? ?? const [])) '$o'
    ];
    return Glass(
      blur: 30,
      color: const Color(0xD9121218),
      borderColor: const Color(0x1AFFFFFF),
      radius: BorderRadius.circular(18),
      shadows: const [
        BoxShadow(
            color: Color(0x8C000000), blurRadius: 50, offset: Offset(0, 20)),
      ],
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: math.max(
                120,
                size.height -
                    MediaQuery.paddingOf(context).vertical -
                    72 -
                    widget.bottomInset)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Who speaks, how many are waiting, and the way to put it away.
              Row(children: [
                NipaAvatar(
                    size: 24, mood: pending ? NipaMood.waiting : NipaMood.idle),
                const SizedBox(width: 10),
                Expanded(
                  child: Pressable(
                    onTap: () => setState(() => _expanded = !_expanded),
                    pressScale: 1,
                    semanticLabel: '全部提醒',
                    builder: (context, hovered) => Text(
                        _items.length > 1 || _more ? '梨花 · $count 条' : '梨花',
                        style: NextText.sans(12.5,
                            weight: FontWeight.w500,
                            letterSpacing: 0.4,
                            color: hovered ? NextColors.paper : NextColors.p3)),
                  ),
                ),
                if (row != null)
                  NextIconButton(
                      key: const Key('agent-inbox.collapse'),
                      glyph: NextGlyph.close,
                      label: '收起',
                      size: 28,
                      onTap: _acting
                          ? null
                          : () => _act(row, 'ui.inbox.dismiss', {}))
                else
                  NextIconButton(
                      glyph: NextGlyph.close,
                      label: '收起',
                      size: 28,
                      onTap: () => setState(() {
                            _expanded = false;
                            _error = null;
                          })),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 10),
                _ErrorText(_error!, maxHeight: size.height * .22),
                const SizedBox(height: 6),
                Row(children: [
                  _Quiet('复制错误',
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: _error!))),
                  const SizedBox(width: 14),
                  _Quiet('收起错误', onTap: () => setState(() => _error = null)),
                ]),
              ],
              if (row != null) ...[
                const SizedBox(height: 12),
                Text('${row['title']}',
                    style: NextText.sans(15,
                        weight: FontWeight.w600, height: 1.4)),
                if ('${row['body'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  failed
                      ? _ErrorText('${row['body']}',
                          maxHeight: size.height * .23)
                      : ConstrainedBox(
                          constraints:
                              BoxConstraints(maxHeight: size.height * .23),
                          child: SingleChildScrollView(
                            child: SelectableText('${row['body']}',
                                style: NextText.sans(13.5,
                                    color: NextColors.p2, height: 1.6)),
                          ),
                        ),
                ],
                if (pending) ...[
                  if (options.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final option in options)
                        _Option(option,
                            onTap: _acting
                                ? null
                                : () => _act(row, 'ui.inbox.respond',
                                    {'answer': option})),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  _Reply(
                    controller: _text,
                    enabled: !_acting,
                    onSend: () => _send(row),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(spacing: 16, runSpacing: 4, children: [
                  if (failed)
                    _Quiet('复制完整错误',
                        onTap: () => Clipboard.setData(
                            ClipboardData(text: '${row['body']}'))),
                  _Quiet('查看对话', arrow: true, onTap: () => _open(row)),
                  if (pending)
                    _Quiet('取消问题',
                        onTap: _acting
                            ? null
                            : () => _act(
                                row, 'ui.inbox.dismiss', {'cancel': true})),
                ]),
                // The others waiting, one line each; a tap brings one up.
                if (visible.length > 1) ...[
                  Container(
                      height: 1,
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      color: NextColors.line),
                  for (final other in visible
                      .where((r) => !identical(r, row))
                      .take(_expanded ? visible.length : 3))
                    _OtherRow(other, onTap: () => _select(other)),
                  if (!_expanded && visible.length > 4)
                    _Quiet('还有 ${visible.length - 4} 条',
                        onTap: () => setState(() => _expanded = true)),
                ],
              ] else if (_expanded) ...[
                const SizedBox(height: 12),
                Text('没有待处理提醒', style: NextText.sans(13, color: NextColors.p3)),
              ],
              if (_expanded && _more) ...[
                const SizedBox(height: 6),
                _Quiet('加载更多', onTap: () {
                  _limit += 30;
                  _load();
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed: who is waiting and how many, out of the way.
class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => Glass(
          blur: 24,
          color: hovered ? const Color(0xE61A1A21) : const Color(0xD9121218),
          borderColor: const Color(0x1AFFFFFF),
          radius: BorderRadius.circular(22),
          shadows: const [
            BoxShadow(
                color: Color(0x66000000),
                blurRadius: 30,
                offset: Offset(0, 12)),
          ],
          padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const NipaAvatar(size: 28, mood: NipaMood.waiting),
            const SizedBox(width: 10),
            Text(label,
                style: NextText.sans(13,
                    weight: FontWeight.w500,
                    color: hovered ? NextColors.paper : NextColors.p2)),
          ]),
        ),
      );
}

/// An answer to choose, as the conversation's choices look.
class _Option extends StatelessWidget {
  const _Option(this.label, {required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1,
        duration: const Duration(milliseconds: 160),
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
            decoration: BoxDecoration(
              color:
                  hovered ? const Color(0x24FFFFFF) : const Color(0x12FFFFFF),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: NextColors.line2),
            ),
            child: Text(label,
                style: NextText.sans(13,
                    height: 1.4,
                    color: hovered ? NextColors.paper : NextColors.p2)),
          ),
        ),
      );
}

/// Typing an answer of one's own: the ask bar's field and send button,
/// smaller.
class _Reply extends StatefulWidget {
  const _Reply(
      {required this.controller, required this.enabled, required this.onSend});
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  @override
  State<_Reply> createState() => _ReplyState();
}

class _ReplyState extends State<_Reply> {
  final _focus = FocusNode(debugLabel: 'agent-inbox.reply');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    final typed = widget.controller.text.trim().isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.fromLTRB(14, 4, 5, 4),
      decoration: BoxDecoration(
        color: focused ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
            color: focused ? const Color(0x59FF2E55) : NextColors.line),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              enabled: widget.enabled,
              maxLength: 16000,
              minLines: 1,
              maxLines: 4,
              cursorColor: NextColors.accent,
              cursorWidth: 1.5,
              style: NextText.sans(13.5, height: 1.5),
              onSubmitted: (_) => widget.onSend(),
              decoration: InputDecoration.collapsed(
                hintText: '也可以直接回复',
                hintStyle: NextText.sans(13.5, color: NextColors.p4),
              ).copyWith(counterText: ''),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AnimatedOpacity(
          opacity: typed && widget.enabled ? 1 : 0.35,
          duration: const Duration(milliseconds: 160),
          child: SendButton(
              size: 32, onTap: typed && widget.enabled ? widget.onSend : null),
        ),
      ]),
    );
  }
}

/// Another reminder waiting: a dot (crimson for a question or an error),
/// its title and when it came.
class _OtherRow extends StatelessWidget {
  const _OtherRow(this.row, {required this.onTap});
  final JsonMap row;
  final VoidCallback onTap;

  static String since(Object? at) {
    final time = DateTime.tryParse('${at ?? ''}')?.toLocal();
    if (time == null) return '';
    final ago = DateTime.now().difference(time);
    if (ago.inMinutes < 1) return '刚刚';
    if (ago.inHours < 1) return '${ago.inMinutes} 分钟前';
    if (ago.inDays < 1) return '${ago.inHours} 小时前';
    return '${time.month} 月 ${time.day} 日';
  }

  @override
  Widget build(BuildContext context) {
    final urgent = row['state'] == 'pending' || row['severity'] == 'error';
    return Pressable(
      onTap: onTap,
      semanticLabel: '${row['title']}',
      pressScale: 0.99,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(left: 9, right: 19),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: urgent ? NextColors.accent : NextColors.p4,
            ),
          ),
          Expanded(
            child: Text('${row['title']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(13,
                    color: hovered ? NextColors.paper : NextColors.p2)),
          ),
          const SizedBox(width: 10),
          Text(since(row['createdAt']),
              style: NextText.sans(11.5, color: NextColors.p4)),
        ]),
      ),
    );
  }
}

/// A quiet word at the card's foot, as the background panel's.
class _Quiet extends StatelessWidget {
  const _Quiet(this.label, {required this.onTap, this.arrow = false});
  final String label;
  final VoidCallback? onTap;
  final bool arrow;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: NextText.sans(12.5,
                    color: onTap == null
                        ? NextColors.p4
                        : hovered
                            ? NextColors.paper
                            : NextColors.p3)),
            if (arrow) ...[
              const SizedBox(width: 3),
              NextIcon(NextGlyph.chevronRight,
                  size: 11, color: hovered ? NextColors.paper : NextColors.p3),
            ],
          ]),
        ),
      );
}

/// What failed, as it was received: whole, selectable, in a quiet box.
class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text, {required this.maxHeight});
  final String text;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0x14FF2E55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x33FF2E55)),
        ),
        child: SingleChildScrollView(
          child: SelectableText(text,
              style:
                  NextText.mono(12, color: NextColors.accent2, height: 1.55)),
        ),
      );
}
