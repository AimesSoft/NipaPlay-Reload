import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
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
import '../widgets/menu.dart';

/// Which model answers what is said next, in the input beside the files:
/// its name as a quiet word, and a tap away a menu that opens upward with
/// the models used before, the ones the provider lists, and how hard she
/// thinks. The settings page stays where a provider and its key are set up.
///
/// Only on a device whose own Nipa this is: a device that speaks with the
/// Nipa of another one does not choose that device's model.
class ModelSwitch extends StatefulWidget {
  const ModelSwitch({super.key});

  @override
  State<ModelSwitch> createState() => _ModelSwitchState();
}

class _ModelSwitchState extends State<ModelSwitch> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
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
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => Stack(children: [
          Positioned.fill(
            child: GestureDetector(
                behavior: HitTestBehavior.opaque, onTap: _portal.hide),
          ),
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              // The input sits at the bottom: the menu opens upward.
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(-4, -10),
              child: Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.escape) {
                    _portal.hide();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                        offset: Offset(0, 6 * (1 - t)), child: child),
                  ),
                  child: ModelMenu(
                    host: host,
                    chat: shell.chat,
                    onSettings: () {
                      _portal.hide();
                      shell.openSettings(section: SettingsSection.nipa);
                    },
                    onClose: _portal.hide,
                  ),
                ),
              ),
            ),
          ),
        ]),
        child: Pressable(
          key: const Key('chat.model'),
          semanticLabel: '模型：$name',
          onTap: _portal.toggle,
          // A quiet word in the input, like the files beside it: what the
          // next thing said is answered with. No frame until hovered.
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hovered || _portal.isShowing
                  ? const Color(0x12FFFFFF)
                  : null,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: NextLayout.compact(context) ? 96 : 180),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(12.5,
                        color: hovered ? NextColors.paper : NextColors.p3)),
              ),
              const SizedBox(width: 5),
              RotatedBox(
                quarterTurns: 3,
                child: NextIcon(NextGlyph.chevronRight,
                    size: 8, color: hovered ? NextColors.p2 : NextColors.p4),
              ),
            ]),
          ),
        ),
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

/// The model menu: the models used before and the ones the provider lists,
/// each once, the one in use checked; how hard she thinks, when the model
/// has a choice; whether a pick holds only for the next thing said; and
/// the way to the settings where providers are set up.
class ModelMenu extends StatefulWidget {
  const ModelMenu(
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
  State<ModelMenu> createState() => _ModelMenuState();
}

class _ModelMenuState extends State<ModelMenu> {
  UiModelSetup? _setup;
  UiModelCandidates? _listed;
  List<UiModelService>? _services;
  final _byService = <String, UiModelCandidates>{};
  bool _busy = false;
  bool _once = false;
  UiModelChoice? _expanded;
  String? _said;

  static String _serviceId(UiModelChoice c) => '${c.provider}|${c.baseUrl}';

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
      final host = widget.host;
      if (host is NextModelServices &&
          setup.source == UiModelSource.nipaplay) {
        final services = await (host as NextModelServices).services();
        if (!mounted) return;
        setState(() => _services = services);
        for (final service in services) {
          unawaited((host as NextModelServices)
              .modelsOf(service.choice)
              .then((models) {
            if (mounted) {
              setState(() => _byService[_serviceId(service.choice)] = models);
            }
          }, onError: (Object error) {
            if (mounted) {
              setState(() => _byService[_serviceId(service.choice)] =
                  UiModelCandidates(UiModelQueryStatus.failed,
                      reason: callFailure(error)));
            }
          }));
        }
      }
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
        await (host as NextSessionModelSettings)
            .setSessionModel(choice, once: _once);
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

  static String _key(UiModelChoice c) =>
      '${c.provider}|${c.baseUrl}|${c.model}|${(c.api ?? UiModelApi.responses).name}';

  static bool _same(UiModelChoice a, UiModelSetup b) =>
      b.source == UiModelSource.nipaplay &&
      a.provider == b.provider &&
      a.baseUrl == b.baseUrl &&
      a.model == b.model &&
      (a.api ?? UiModelApi.responses) == b.api;

  static String _effort(String effort) => switch (effort) {
        '' || 'none' => '关',
        'minimal' => '极低',
        'low' => '低',
        'medium' => '中',
        'high' => '高',
        'xhigh' => '很高',
        'max' => '最高',
        'ultra' => '超高',
        _ => effort,
      };

  static String? _origin(UiModelChoice choice) =>
      switch (choice.candidateOrigin) {
        UiModelCandidateOrigin.openai => 'OpenAI',
        UiModelCandidateOrigin.chatgptAccount => 'ChatGPT',
        UiModelCandidateOrigin.provider => null,
        UiModelCandidateOrigin.dshProvider => null,
        null => choice.providerLabel ?? choice.provider,
      };

  /// A service by its provider's name; by its address too when another
  /// service has the same name.
  static String _serviceName(UiModelService service, List<UiModelService> all) {
    final name = service.choice.provider ?? '';
    final twins = all.where((s) => s.choice.provider == name).length;
    if (twins < 2) return name;
    final host = Uri.tryParse(service.choice.baseUrl ?? '');
    return '$name · ${host == null ? service.choice.baseUrl : host.hasPort ? '${host.host}:${host.port}' : host.host}';
  }

  /// A service's models, or its default one while they are read or when
  /// they cannot be listed.
  List<Widget> _serviceRows(
      UiModelSetup setup, UiModelService service, List<UiModelService> services) {
    final listed = _byService[_serviceId(service.choice)];
    String? trim(String? url) => url?.replaceFirst(RegExp(r'/$'), '');
    bool current(UiModelChoice m) =>
        setup.sessionChoice == null &&
        setup.source == UiModelSource.nipaplay &&
        setup.provider == m.provider &&
        trim(setup.baseUrl) == trim(m.baseUrl) &&
        setup.model == m.model;
    final models = [
      ...(listed?.status == UiModelQueryStatus.succeeded &&
              listed!.choices.isNotEmpty
          ? listed.choices
          : [service.choice])
    ];
    // The one in use and the service's default first, then the rest.
    int rank(UiModelChoice m) =>
        current(m) ? 0 : m.model == service.choice.model ? 1 : 2;
    models.sort((a, b) => rank(a).compareTo(rank(b)));
    return [
      for (final m in models)
        _ModelRow(
            key: Key(services.where((s) => s.choice.provider == service.choice.provider).length > 1
                ? 'chat.model.service.${service.choice.provider}.${service.choice.baseUrl}.${m.model}'
                : 'chat.model.service.${service.choice.provider}.${m.model}'),
            title: m.label ?? m.model ?? '',
            current: current(m),
            onTap: current(m) || !service.hasKey
                ? null
                // Another model of the service in use keeps its thinking
                // and wire settings; another service brings its own.
                : () => _choose(service.current &&
                        setup.source == UiModelSource.nipaplay
                    ? currentChoice(setup, model: m.model)
                    : choiceOf(m.withReasoning(
                        m.reasoning ?? service.choice.reasoning)))),
      if (listed == null)
        const Padding(
            padding: EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Align(
                alignment: Alignment.centerLeft, child: ThinkingDots())),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final setup = _setup;
    // Each model once: the same provider, address, model and wire set up
    // twice is one entry. Codex speaks Responses only.
    // Two set-ups that would read the same in the menu (the same model
    // under the same provider) are one row: the most recent.
    final seen = <String>{};
    String shown(UiModelChoice c) =>
        '${c.label ?? c.model}|${c.providerLabel ?? c.provider}';
    final recent = [
      for (final model in setup?.recent ?? const <UiModelChoice>[])
        if ((setup?.runtime != UiAgentRuntimeKind.codex ||
                model.api != UiModelApi.chat) &&
            seen.add(_key(model)) &&
            seen.add(shown(model)))
          model
    ].take(5).toList();
    final services = _services;
    // What the services list themselves, by model, so the runtime's own
    // catalog does not repeat them.
    final serviceModels = {
      for (final listed in _byService.values)
        for (final c in listed.choices) c.model,
      for (final service in services ?? const <UiModelService>[])
        service.choice.model,
    };
    final others = [
      for (final choice in _listed?.choices ?? const <UiModelChoice>[])
        // With services, each lists its own models; the runtime's catalog
        // stays here.
        if ((services == null ||
                (choice.catalog != null &&
                    !serviceModels.contains(choice.model))) &&
            seen.add(_key(choice)))
          choice
    ];
    final sessionPicks =
        _listed?.choices.any((choice) => choice.catalog != null) == true;
    final dshEffort = setup != null &&
        setup.sessionChoice == null &&
        setup.source == UiModelSource.nipaplay &&
        setup.runtime == UiAgentRuntimeKind.dsh;
    return MenuPanel(
      width: 296,
      children: [
        if (setup == null)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: ThinkingDots()))
        else
          ConstrainedBox(
            // Every model is listed; a long list scrolls inside the menu.
            constraints: BoxConstraints(
                maxHeight: math.max(
                    240, MediaQuery.sizeOf(context).height * 0.6 - 160)),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (setup.source == UiModelSource.codex ||
                    (setup.codexAvailable &&
                        setup.runtime == UiAgentRuntimeKind.codex)) ...[
                  const _Label('这台电脑'),
                  _ModelRow(
                      key: const Key('chat.model.codex'),
                      title: 'Codex 配置',
                      caption: setup.source == UiModelSource.codex
                          ? setup.inUse
                          : null,
                      current: setup.source == UiModelSource.codex &&
                          setup.sessionChoice == null,
                      onTap: setup.source == UiModelSource.codex
                          ? null
                          : () => _choose(const UiModelChoice(
                              source: UiModelSource.codex))),
                ],
                if (services != null)
                  for (final service in services) ...[
                    _Label([
                      _serviceName(service, services),
                      if (!service.hasKey) '没有密钥',
                    ].join(' · ')),
                    ..._serviceRows(setup, service, services),
                  ]
                else if (recent.isNotEmpty) ...[
                  const _Label('用过的'),
                  for (final (i, model) in recent.indexed)
                    _ModelRow(
                        key: Key('chat.model.recent.$i'),
                        title: model.label ?? model.model ?? '',
                        caption: model.providerLabel ?? model.provider,
                        current: setup.sessionChoice == null &&
                            _same(model, setup),
                        onTap: _same(model, setup)
                            ? null
                            : () => _choose(choiceOf(model))),
                ],
                if (_listed == null)
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: ThinkingDots()))
                else if (services != null && others.isEmpty)
                  const SizedBox.shrink()
                else if (_listed!.status != UiModelQueryStatus.succeeded)
                  _Note(switch (_listed!.status) {
                    UiModelQueryStatus.succeeded => '',
                    UiModelQueryStatus.failed => '没能列出可用模型：${_listed!.reason}',
                    UiModelQueryStatus.unavailable =>
                      '这里列不出可用模型：${_listed!.reason}',
                  })
                else if (others.isNotEmpty) ...[
                  _Label(services != null ? '运行器提供' : '可用'),
                  for (final choice in others) ...[
                    _ModelRow(
                        key: Key(choice.catalog == null
                            ? 'chat.model.listed.${choice.model}'
                            : 'chat.model.listed.${choice.catalog!.name}.${choice.provider}.${choice.model}'),
                        title: choice.label ?? choice.model ?? '',
                        caption: _origin(choice),
                        current:
                            setup.sessionChoice?.catalog == choice.catalog &&
                                setup.sessionChoice?.model == choice.model &&
                                setup.sessionChoice?.provider == choice.provider,
                        open: identical(_expanded, choice),
                        onTap: () => choice.catalog != null
                            ? choice.reasoningLevels.isEmpty
                                ? _choose(choice)
                                : setState(() => _expanded =
                                    identical(_expanded, choice) ? null : choice)
                            : _choose(choice.source == setup.source &&
                                    choice.provider == setup.provider &&
                                    choice.baseUrl == setup.baseUrl &&
                                    choice.api == setup.api
                                ? currentChoice(setup, model: choice.model)
                                : choiceOf(choice))),
                    if (identical(_expanded, choice))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 8, 8),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
                          for (final effort in choice.reasoningLevels)
                            _Chip(
                                label: _effort(effort),
                                selected: effort == choice.reasoning,
                                onTap: () =>
                                    _choose(choice.withReasoning(effort))),
                        ]),
                      ),
                  ],
                ],
              ]),
            ),
          ),
        if (_said case final said?) _Note(said, warn: true),
        if (dshEffort) ...[
          const _Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(children: [
              Text('思考', style: NextText.sans(13, color: NextColors.p2)),
              const Spacer(),
              Segmented<String>(
                value: setup.reasoning ?? '',
                options: [
                  for (final v in const ['', 'low', 'medium', 'high'])
                    (
                      v,
                      _effort(v),
                      (c) => Text(_effort(v),
                          style: NextText.sans(12, color: c))
                    ),
                ],
                onChanged: (v) =>
                    _choose(currentChoice(setup, reasoning: v), close: false),
              ),
            ]),
          ),
        ],
        if (sessionPicks)
          _ToggleRow(
              label: '只用于下一句',
              value: _once,
              onChanged: (value) => setState(() => _once = value)),
        const _Divider(),
        Row(children: [
          Expanded(
            child: MenuItem(
                label: '管理模型…', onTap: widget.onSettings),
          ),
          if (_busy)
            const Padding(
                padding: EdgeInsets.only(right: 12), child: ThinkingDots()),
        ]),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: NextText.sans(11.5, color: NextColors.p4, letterSpacing: 0.6)),
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: NextText.sans(12,
                  color: warn ? NextColors.accent2 : NextColors.p3)),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: NextColors.line);
}

/// A model: its name, where it comes from in a fainter word on the right,
/// a check on the one in use.
class _ModelRow extends StatelessWidget {
  const _ModelRow(
      {super.key,
      required this.title,
      this.caption,
      this.current = false,
      this.open = false,
      this.onTap});
  final String title;
  final String? caption;
  final bool current;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: title,
        pressScale: 0.99,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: (hovered && onTap != null) || open
                ? const Color(0x14FFFFFF)
                : const Color(0x00FFFFFF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: NextText.sans(13.5,
                      color: current || hovered
                          ? NextColors.paper
                          : NextColors.p2)),
            ),
            if (caption case final caption? when caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 96),
                  child: Text(caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(11.5, color: NextColors.p4)),
                ),
              ),
            SizedBox(
              width: 22,
              child: current
                  ? const Align(
                      alignment: Alignment.centerRight,
                      child: NextIcon(NextGlyph.check,
                          size: 13, color: NextColors.accent))
                  : null,
            ),
          ]),
        ),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        builder: (context, hovered) => Container(
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? NextColors.accentSoft
                : hovered
                    ? const Color(0x14FFFFFF)
                    : const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(label,
              style: NextText.sans(12,
                  color: selected ? NextColors.accent2 : NextColors.p2)),
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => onChanged(!value),
        semanticLabel: label,
        builder: (context, hovered) => Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: hovered ? const Color(0x0FFFFFFF) : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Expanded(
                child: Text(label,
                    style: NextText.sans(13, color: NextColors.p2))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: 30,
              height: 18,
              padding: const EdgeInsets.all(2),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? NextColors.accent : const Color(0x29F5F1EA),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Container(
                  width: 14,
                  height: 14,
                  decoration: const BoxDecoration(
                      color: NextColors.paper, shape: BoxShape.circle)),
            ),
          ]),
        ),
      );
}

