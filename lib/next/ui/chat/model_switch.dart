import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../ui_data/host_settings.dart';
import '../conversation/nipa_chat.dart';
import '../data/gui_calls.dart' show callFailure;
import '../settings/settings_layout.dart';
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/progress.dart';
import '../widgets/segmented.dart';
import '../widgets/sheet.dart';

/// Which model Nipa thinks with, where the conversation is: its name over
/// the conversation, and a tap away the models set up before, the others
/// its provider lists, and how hard she thinks. The settings page stays
/// where a new provider and its key are set up.
///
/// Only on a device whose own Nipa this is: a device that speaks with the
/// Nipa of another one does not choose that device's model.
class ModelSwitch extends StatefulWidget {
  const ModelSwitch({super.key});

  @override
  State<ModelSwitch> createState() => _ModelSwitchState();
}

class _ModelSwitchState extends State<ModelSwitch> {
  NextHostSettings? _host;
  StreamSubscription<void>? _changes;
  UiModelSetup? _setup;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    final host = shell.nipaSetup.picksDevice ? null : shell.nipaSetup.host;
    if (identical(host, _host)) return;
    _host = host;
    _changes?.cancel();
    _changes = host?.changes.listen((_) => _load());
    _load();
  }

  Future<void> _load() async {
    final host = _host;
    if (host == null) return;
    try {
      final setup = await host.model();
      if (mounted && identical(host, _host)) setState(() => _setup = setup);
    } catch (error) {
      debugPrint('[NextUi] model: $error');
    }
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    final host = _host;
    final name = setup == null ? null : modelLabel(setup);
    if (host == null || setup == null || name == null) {
      return const SizedBox.shrink();
    }
    final shell = NextShellScope.of(context);
    return Pressable(
      key: const Key('chat.model'),
      semanticLabel: '模型：$name',
      onTap: () => showNextSheet<void>(
          width: 440,
          (context, close) => ModelSheet(
              host: host,
              chat: shell.chat,
              onSettings: () {
                close();
                shell.openSettings(section: SettingsSection.nipa);
              },
              onClose: close)),
      builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: hovered ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: NextColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            // A phone's title keeps most of its line.
            constraints: BoxConstraints(
                maxWidth: NextLayout.compact(context) ? 104 : 170),
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12.5,
                    color: hovered ? NextColors.paper : NextColors.p2)),
          ),
          const SizedBox(width: 6),
          RotatedBox(
            quarterTurns: 1,
            child: NextIcon(NextGlyph.chevronRight,
                size: 9, color: hovered ? NextColors.p2 : NextColors.p4),
          ),
        ]),
      ),
    );
  }
}

/// What the pill says: the model chosen (the running conversation takes it
/// up at its next turn; naming the one still in use would look as if the
/// choice had not been taken), else the one in use; null while there is
/// none to name (the setup chip shows the way then).
String? modelLabel(UiModelSetup setup) {
  final choice = setup.nextTurnChoice ?? setup.sessionChoice;
  if (choice != null) return choice.label ?? choice.model;
  if (setup.source == UiModelSource.chatgpt) return setup.inUse ?? 'ChatGPT';
  if (setup.source == UiModelSource.codex) return setup.inUse ?? 'Codex 配置';
  return setup.model ?? setup.inUse;
}

/// The choice that keeps [setup] and changes what is given: a recent
/// model is taken whole (its wire, thinking and template switches), so
/// nothing of the previous provider's is carried over.
UiModelChoice choiceOf(UiModelChoice model) => UiModelChoice(
    source: UiModelSource.nipaplay,
    provider: model.provider,
    baseUrl: model.baseUrl,
    model: model.model,
    api: model.api ?? UiModelApi.responses,
    reasoning: model.reasoning ?? '',
    compat: model.compat ?? const {});

UiModelChoice currentChoice(UiModelSetup setup,
        {String? model, String? reasoning}) =>
    UiModelChoice(
        source: UiModelSource.nipaplay,
        provider: setup.provider,
        baseUrl: setup.baseUrl,
        model: model ?? setup.model,
        api: setup.api,
        reasoning: reasoning ?? setup.reasoning ?? '',
        compat: setup.compat ?? const {});

class ModelSheet extends StatefulWidget {
  const ModelSheet(
      {super.key,
      required this.host,
      required this.chat,
      required this.onSettings,
      required this.onClose});
  final NextHostSettings host;
  final NipaChat chat;
  final VoidCallback onSettings;
  final VoidCallback onClose;

  @override
  State<ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<ModelSheet> {
  UiModelSetup? _setup;
  UiModelCandidates? _listed;
  bool _busy = false;
  bool _once = false;
  UiModelChoice? _pendingChoice;
  String? _said;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  Future<void> _read() async {
    try {
      final setup = await widget.host.model();
      if (!mounted) return;
      setState(() => _setup = setup);
      final listed = await widget.host.providerModels();
      if (mounted) setState(() => _listed = listed);
    } catch (error) {
      if (mounted) setState(() => _said = callFailure(error));
    }
  }

  Future<void> _choose(UiModelChoice choice, {bool close = true}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _said = null;
    });
    try {
      final host = widget.host;
      if (choice.catalog != null && host is NextSessionModelSettings) {
        await (host as NextSessionModelSettings).setSessionModel(choice, once: _once);
      } else {
        await host.setModel(choice);
      }
      if (close) {
        widget.onClose();
        return;
      }
      final setup = await widget.host.model();
      if (mounted) setState(() => _setup = setup);
    } catch (error) {
      if (mounted) setState(() => _said = callFailure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static bool _same(UiModelChoice a, UiModelSetup b) =>
      b.source == UiModelSource.nipaplay &&
      a.provider == b.provider &&
      a.baseUrl == b.baseUrl &&
      a.model == b.model &&
      (a.api ?? UiModelApi.responses) == b.api;

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    // Codex speaks Responses only: a Chat Completions model set up for
    // DeepSeek Harness cannot be picked under it.
    final recent = [
      for (final model in setup?.recent ?? const <UiModelChoice>[])
        if (setup?.runtime != UiAgentRuntimeKind.codex ||
            model.api != UiModelApi.chat)
          model
    ];
    final others = [
      for (final choice in _listed?.choices ?? const <UiModelChoice>[])
        if (!recent.any((saved) =>
            saved.model == choice.model &&
            saved.provider == choice.provider &&
            saved.baseUrl == choice.baseUrl &&
            (saved.api ?? UiModelApi.responses) == choice.api))
          choice
    ];
    return SheetSurface(
      padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text('模型',
                    style: NextText.sans(17, weight: FontWeight.w600))),
            if (_busy)
              const Padding(
                  padding: EdgeInsets.only(right: 8), child: ThinkingDots()),
            NextIconButton(
                glyph: NextGlyph.close, label: '关闭', onTap: widget.onClose),
          ]),
          const SizedBox(height: 4),
          Text(widget.chat.running ? '这一轮说完后换用，正在进行的不受影响。' : '从下一句开始换用。',
              style: NextText.sans(12.5, color: NextColors.p3)),
          if (_said case final said?) ...[
            const SizedBox(height: 10),
            Text(said, style: NextText.sans(12.5, color: NextColors.accent2)),
          ],
          if (setup == null)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: ThinkingDots()))
          else
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (setup.source == UiModelSource.codex ||
                          (setup.codexAvailable &&
                              setup.runtime == UiAgentRuntimeKind.codex)) ...[
                        const _Heading('这台电脑'),
                        _Row(
                            key: const Key('chat.model.codex'),
                            title: 'Codex 配置',
                            detail: setup.source == UiModelSource.codex
                                ? setup.inUse
                                : null,
                            current: setup.source == UiModelSource.codex &&
                                setup.sessionChoice == null,
                            onTap: setup.source == UiModelSource.codex
                                ? null
                                : () => _choose(const UiModelChoice(
                                    source: UiModelSource.codex))),
                      ],
                      if (recent.isNotEmpty) ...[
                        const _Heading('用过的'),
                        for (final (i, model) in recent.indexed)
                          _Row(
                              key: Key('chat.model.recent.$i'),
                              title: model.model ?? '',
                              detail: model.provider,
                              current: setup.sessionChoice == null &&
                                  _same(model, setup),
                              onTap: _same(model, setup)
                                  ? null
                                  : () => _choose(choiceOf(model))),
                      ],
                      ...[
                        const _Heading('候选模型'),
                        if (_listed?.choices.any((choice) => choice.catalog != null) == true)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Segmented<bool>(
                              value: _once,
                              options: [for (final (once, label) in const [(false, '从现在起'), (true, '仅下一轮')])
                                (once, label, (color) => Text(label, style: NextText.sans(12.5, color: color)))],
                              onChanged: (value) => setState(() => _once = value),
                            ),
                          ),
                        if (_listed == null)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: ThinkingDots())
                        else if (_listed!.status !=
                                UiModelQueryStatus.succeeded ||
                            others.isEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                  switch (_listed!.status) {
                                    UiModelQueryStatus.succeeded => '没有列出别的模型',
                                    UiModelQueryStatus.failed =>
                                      '候选查询失败：${_listed!.reason}',
                                    UiModelQueryStatus.unavailable =>
                                      '候选查询不可用：${_listed!.reason}',
                                  },
                                  style: NextText.sans(12.5,
                                      color: NextColors.p4)))
                        else
                          for (final choice in others)
                            _Row(
                                key: Key(choice.catalog == null
                                    ? 'chat.model.listed.${choice.model}'
                                    : 'chat.model.listed.${choice.catalog!.name}.${choice.provider}.${choice.model}'),
                                title: choice.label ?? choice.model ?? '',
                                detail: switch (choice.candidateOrigin) {
                                  UiModelCandidateOrigin.openai => 'OpenAI',
                                  UiModelCandidateOrigin.chatgptAccount => 'ChatGPT 账号',
                                  UiModelCandidateOrigin.provider => '这个服务商',
                                  UiModelCandidateOrigin.dshProvider => 'DSH 服务商',
                                  null => choice.providerLabel ?? choice.provider,
                                },
                                current: setup.sessionChoice?.catalog == choice.catalog &&
                                    setup.sessionChoice?.model == choice.model &&
                                    setup.sessionChoice?.provider == choice.provider,
                                onTap: () => choice.catalog != null
                                    ? choice.reasoningLevels.isEmpty
                                        ? _choose(choice)
                                        : setState(() => _pendingChoice = choice)
                                    : _choose(choice.source ==
                                            setup.source &&
                                        choice.provider == setup.provider &&
                                        choice.baseUrl == setup.baseUrl &&
                                        choice.api == setup.api
                                    ? currentChoice(setup, model: choice.model)
                                    : choiceOf(choice))),
                      ],
                      if (_pendingChoice case final selected?) ...[
                        _Heading(selected.label ?? selected.model ?? '思考'),
                        for (final effort in selected.reasoningLevels)
                          _Row(title: switch (effort) {
                            'none' => '关', 'minimal' => '极低', 'low' => '低',
                            'medium' => '中', 'high' => '高', 'xhigh' => '很高',
                            'max' => '最高', 'ultra' => '超高', _ => effort,
                          }, current: effort == selected.reasoning,
                          onTap: () => _choose(selected.withReasoning(effort))),
                      ],
                      if (setup.sessionChoice == null &&
                          setup.source == UiModelSource.nipaplay &&
                          setup.runtime == UiAgentRuntimeKind.dsh) ...[
                        const _Heading('思考'),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Segmented<String>(
                            value: setup.reasoning ?? '',
                            options: [
                              for (final (v, t) in const [
                                ('', '关'),
                                ('low', '低'),
                                ('medium', '中'),
                                ('high', '高'),
                              ])
                                (
                                  v,
                                  t,
                                  (c) => Text(t,
                                      style: NextText.sans(12.5, color: c))
                                ),
                            ],
                            onChanged: (v) => _choose(
                                currentChoice(setup, reasoning: v),
                                close: false),
                          ),
                        ),
                      ],
                    ]),
              ),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child:
                NextButton.ghost(label: '添加或修改模型…', onTap: widget.onSettings),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(text,
            style: NextText.sans(12, color: NextColors.p3, letterSpacing: 0.4)),
      );
}

class _Row extends StatelessWidget {
  const _Row(
      {super.key,
      required this.title,
      this.detail,
      this.current = false,
      this.onTap});
  final String title;
  final String? detail;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: title,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: const BoxConstraints(minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: hovered && onTap != null ? const Color(0x12FFFFFF) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: NextText.sans(14,
                            weight:
                                current ? FontWeight.w600 : FontWeight.w400)),
                    if (detail case final detail? when detail.isNotEmpty)
                      Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: NextText.sans(12, color: NextColors.p3)),
                  ]),
            ),
            if (current)
              const NextIcon(NextGlyph.check,
                  size: 14, color: NextColors.accent),
          ]),
        ),
      );
}
