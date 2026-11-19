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

/// What the pill says: the model in use, else the one chosen; null while
/// there is none to name (the setup chip shows the way then).
String? modelLabel(UiModelSetup setup) {
  if (setup.source == UiModelSource.codex) return setup.inUse ?? 'Codex 配置';
  return setup.inUse ?? setup.model;
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
  List<String>? _listed;
  bool _busy = false;
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
      if (setup.source == UiModelSource.nipaplay && setup.hasKey) {
        final listed = await widget.host.providerModels();
        if (mounted) setState(() => _listed = listed);
      } else {
        setState(() => _listed = const []);
      }
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
      await widget.host.setModel(choice);
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
    final recent = setup?.recent ?? const <UiModelChoice>[];
    final others = setup == null
        ? const <String>[]
        : [
            for (final id in _listed ?? const <String>[])
              if (!recent.any((r) =>
                  r.model == id &&
                  r.provider == setup.provider &&
                  r.baseUrl == setup.baseUrl))
                id
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
          Text(
              widget.chat.running
                  ? '这一轮说完后换用，正在进行的不受影响。'
                  : '从下一句开始换用。',
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
                            current: setup.source == UiModelSource.codex,
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
                              current: _same(model, setup),
                              onTap: _same(model, setup)
                                  ? null
                                  : () => _choose(choiceOf(model))),
                      ],
                      if (setup.source == UiModelSource.nipaplay &&
                          setup.hasKey) ...[
                        _Heading('${setup.provider ?? '这个服务'}还提供'),
                        if (_listed == null)
                          const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: ThinkingDots())
                        else if (others.isEmpty)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text('没有列出别的模型',
                                  style: NextText.sans(12.5,
                                      color: NextColors.p4)))
                        else
                          for (final id in others)
                            _Row(
                                key: Key('chat.model.listed.$id'),
                                title: id,
                                onTap: () => _choose(
                                    currentChoice(setup, model: id))),
                      ],
                      if (setup.source == UiModelSource.nipaplay &&
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
            child: NextButton.ghost(
                label: '添加或修改模型…', onTap: widget.onSettings),
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
