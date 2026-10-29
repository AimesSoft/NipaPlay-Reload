import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipa_harness/nipa_harness.dart'
    show Failure, FailureCode, JsonMap;
import 'package:flutter/foundation.dart';
import '../data/gui_calls.dart';

/// Nonmodal, never requests focus on arrival. The queue remains accessible
/// when popups are disabled or a question is hidden.
class AgentInboxOverlay extends StatefulWidget {
  const AgentInboxOverlay(
      {super.key,
      required this.calls,
      required this.events,
      this.peer,
      this.onOpen,
      this.errors});
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
    final size = MediaQuery.sizeOf(context);
    return SafeArea(
        child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                    width: math.min(
                        row == null && !_expanded && _error == null ? 150 : 380,
                        math.max(0, size.width - 32)),
                    child: Material(
                        color: const Color(0xff202125),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: DefaultTextStyle(
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                                child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxHeight: math.max(
                                            80,
                                            size.height -
                                                MediaQuery.paddingOf(context)
                                                    .vertical -
                                                64)),
                                    child: SingleChildScrollView(
                                        child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Row(children: [
                                            Expanded(
                                                child: TextButton(
                                                    onPressed: () => setState(
                                                        () => _expanded =
                                                            !_expanded),
                                                    child: Text(
                                                        '梨花提醒 · ${_items.length}${_more ? '+' : ''}'))),
                                            if (row != null)
                                              IconButton(
                                                  tooltip: '收起；问题仍待回答',
                                                  icon: const Icon(Icons.close,
                                                      color: Colors.white70),
                                                  onPressed: _acting
                                                      ? null
                                                      : () => _act(
                                                          row,
                                                          'ui.inbox.dismiss',
                                                          {})),
                                          ]),
                                          if (_error != null) ...[
                                            ConstrainedBox(
                                                constraints: BoxConstraints(
                                                    maxHeight:
                                                        size.height * .22),
                                                child: SingleChildScrollView(
                                                    child: SelectableText(
                                                        _error!,
                                                        style: const TextStyle(
                                                            color: Colors
                                                                .redAccent)))),
                                            Row(children: [
                                              TextButton(
                                                  onPressed: () =>
                                                      Clipboard.setData(
                                                          ClipboardData(
                                                              text: _error!)),
                                                  child: const Text('复制错误')),
                                              TextButton(
                                                  onPressed: () => setState(
                                                      () => _error = null),
                                                  child: const Text('收起错误'))
                                            ]),
                                          ],
                                          if (row != null) ...[
                                            Text('${row['title']}',
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                            const SizedBox(height: 8),
                                            ConstrainedBox(
                                                constraints: BoxConstraints(
                                                    maxHeight:
                                                        size.height * .23),
                                                child: SingleChildScrollView(
                                                    child: SelectableText(
                                                        '${row['body']}'))),
                                            if (row['severity'] == 'error')
                                              TextButton(
                                                  onPressed: () => Clipboard
                                                      .setData(ClipboardData(
                                                          text:
                                                              '${row['body']}')),
                                                  child: const Text('复制完整错误')),
                                            if (row['state'] == 'pending') ...[
                                              Wrap(spacing: 6, children: [
                                                for (final option
                                                    in (row['options']
                                                            as List? ??
                                                        []))
                                                  OutlinedButton(
                                                      onPressed: _acting
                                                          ? null
                                                          : () => _act(
                                                              row,
                                                              'ui.inbox.respond',
                                                              {'answer': option}),
                                                      child: Text('$option'))
                                              ]),
                                              TextField(
                                                  controller: _text,
                                                  enabled: !_acting,
                                                  maxLength: 16000,
                                                  minLines: 1,
                                                  maxLines: 3,
                                                  style: const TextStyle(
                                                      color: Colors.white),
                                                  decoration:
                                                      const InputDecoration(
                                                          hintText: '也可以直接回复',
                                                          counterText: '',
                                                          hintStyle: TextStyle(
                                                              color: Colors
                                                                  .white54))),
                                              Row(children: [
                                                TextButton(
                                                    onPressed: _acting
                                                        ? null
                                                        : () {
                                                            if (_text.text
                                                                .trim()
                                                                .isNotEmpty) {
                                                              _act(
                                                                  row,
                                                                  'ui.inbox.respond',
                                                                  {
                                                                    'answer':
                                                                        _text
                                                                            .text
                                                                  });
                                                            }
                                                          },
                                                    child: const Text('回复')),
                                                TextButton(
                                                    onPressed: _acting
                                                        ? null
                                                        : () => _act(
                                                            row,
                                                            'ui.inbox.dismiss',
                                                            {'cancel': true}),
                                                    child: const Text('取消问题'))
                                              ]),
                                            ],
                                            TextButton(
                                                onPressed: () async {
                                                  if (row['_peer'] !=
                                                      widget.peer?.call()) {
                                                    setState(() => _error =
                                                        '请先切换到这条提醒所属的设备。');
                                                    return;
                                                  }
                                                  await widget.onOpen
                                                      ?.call(row);
                                                },
                                                child: const Text('查看对话')),
                                            if (_expanded && visible.length > 1)
                                              TextButton(
                                                  onPressed: () => setState(() {
                                                        final i = visible
                                                            .indexOf(row);
                                                        final next = visible[
                                                            (i + 1) %
                                                                visible.length];
                                                        _selectedId =
                                                            '${next['_peer']}:${next['id']}';
                                                        _text.clear();
                                                      }),
                                                  child: const Text('下一条')),
                                          ] else if (_expanded)
                                            const Text('没有待处理提醒'),
                                          if (_expanded && _more)
                                            TextButton(
                                                onPressed: () {
                                                  _limit += 30;
                                                  _load();
                                                },
                                                child: const Text('加载更多')),
                                        ]))))))))));
  }
}
