import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/gui_calls.dart';
import '../data/rika_store.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/sheet.dart';
import 'controls.dart';
import 'section_accounts.dart' show ConfirmPill;

/// 梨花's store: skills that teach her more (BT sources, danmaku tools) and
/// plugins that bring her models from elsewhere. The official list is
/// reviewed and pinned; an npm package anyone names is installed only after
/// the person has read that nobody reviewed it. What changes takes effect
/// when she starts again, which this card offers to do.
class RikaStoreCard extends StatefulWidget {
  const RikaStoreCard({super.key, required this.store});
  final NextRikaStore store;

  @override
  State<RikaStoreCard> createState() => _RikaStoreCardState();
}

class _RikaStoreCardState extends State<RikaStoreCard> {
  UiStore? _store;
  String? _failed;
  bool _refreshing = false;

  /// Something changed since 梨花 started.
  bool _pending = false;
  bool _applying = false;
  final _busy = <String>{};
  final _errors = <String, String>{};
  String _npm = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) setState(() => _refreshing = true);
    try {
      final store = await widget.store.read(refresh: refresh);
      if (mounted) {
        setState(() {
          _store = store;
          _failed = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _failed = callFailure(error));
    }
    if (mounted && refresh) setState(() => _refreshing = false);
  }

  Future<void> _run(String key, Future<void> Function() action) async {
    setState(() {
      _busy.add(key);
      _errors.remove(key);
    });
    try {
      await action();
      _pending = true;
    } catch (error) {
      if (mounted) setState(() => _errors[key] = callFailure(error));
    }
    await _load();
    if (mounted) setState(() => _busy.remove(key));
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await widget.store.apply();
      if (mounted) setState(() => _pending = false);
    } catch (error) {
      if (mounted) setState(() => _errors['apply'] = callFailure(error));
    }
    if (mounted) setState(() => _applying = false);
  }

  /// Installs [item] after the person has read what it says of itself.
  Future<void> _install(UiStoreItem item) async {
    if (item.notices.isNotEmpty) {
      final go = await showNextSheet<bool>(
          (context, close) => _Notices(
              title: '安装「${item.name}」',
              notices: item.notices,
              onAnswer: close),
          width: 460);
      if (go != true) return;
    }
    await _run(item.id,
        () => widget.store.install(id: item.id, version: item.version));
  }

  Future<void> _installNpm() async {
    final spec = _npm.trim();
    if (spec.isEmpty) return;
    final go = await showNextSheet<bool>(
        (context, close) => _Notices(
            title: '安装 npm 包 $spec',
            notices: const [
              '这个包没有经过审核。插件在梨花的运行环境里运行，技能的脚本由梨花运行：它们能读写你的账户能访问的文件、连接任意网络地址，也能看到交给它的数据。',
              '只安装你信任、知道来历的包。商店不运行包的安装脚本，也只接受依赖都由梨花运行环境提供的插件。',
            ],
            onAnswer: close),
        width: 460);
    if (go != true) return;
    await _run('npm', () async {
      await widget.store.install(npm: spec);
      if (mounted) setState(() => _npm = '');
    });
  }

  Future<void> _details(UiStoreItem item) async {
    await showNextSheet<void>(
        (context, close) => _Details(
            item: item,
            readme: item.reviewed ? widget.store.readme(item.id) : null,
            onClose: close),
        width: 560);
  }

  Widget _mark(UiStoreItem item) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(item.installedVersion ?? item.version,
            style: NextText.num(11.5, color: NextColors.p4)),
        if (!item.reviewed) ...[
          const SizedBox(width: 8),
          Text('未审核', style: NextText.sans(11.5, color: NextColors.accent2)),
        ],
        if (item.updateAvailable) ...[
          const SizedBox(width: 8),
          Text('可更新到 ${item.version}',
              style: NextText.sans(11.5, color: NextColors.mint)),
        ],
        if (item.notLoaded != null) ...[
          const SizedBox(width: 8),
          const StateDot(NextColors.accent2),
        ],
      ]);

  Widget _row(UiStoreItem item) {
    final busy = _busy.contains(item.id);
    final error = _errors[item.id] ?? item.notLoaded;
    return SettingsRow(
      key: ValueKey('store.${item.id}'),
      title: item.name,
      subtitle: error ?? item.description,
      mark: _mark(item),
      onTap: () => _details(item),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (!item.installed)
          PillButton(
              label: '安装', busy: busy, onTap: busy ? null : () => _install(item))
        else ...[
          if (item.updateAvailable)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PillButton(
                  label: '更新',
                  busy: busy,
                  onTap: busy ? null : () => _install(item)),
            ),
          NextToggle(
              value: item.enabled ?? true,
              label: '启用${item.name}',
              onChanged: busy
                  ? null
                  : (on) => _run(item.id,
                      () => widget.store.setEnabled(item.id, on))),
          const SizedBox(width: 8),
          ConfirmPill(
              label: '卸载',
              confirm: '确认卸载',
              onConfirm: () =>
                  _run(item.id, () => widget.store.remove(item.id))),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final groups = <String, List<UiStoreItem>>{};
    for (final item in store?.official ?? const <UiStoreItem>[]) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    return SettingsCard(title: '扩展', children: [
      SettingsRow(
        title: '技能和插件',
        subtitle: '技能教梨花新的本事（比如更多 BT 来源、弹幕工具），插件给她接入别处的模型。'
            '安装、卸载或开关后，重启梨花才生效。',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (_pending)
            PillButton(
                label: '重启梨花',
                primary: true,
                busy: _applying,
                onTap: _applying ? null : _apply),
          const SizedBox(width: 8),
          PillButton(
              label: '刷新',
              busy: _refreshing,
              onTap: _refreshing ? null : () => _load(refresh: true)),
        ]),
      ),
      if (_errors['apply'] case final error?)
        SettingsRow(title: '没能重启梨花', subtitle: error, dim: true),
      if (_failed != null)
        SettingsRow(title: '没能读取商店', subtitle: _failed, dim: true)
      else if (store == null)
        const SettingsRow(title: '正在读取…', dim: true)
      else ...[
        if (store.listProblem != null)
          SettingsRow(
              title: store.official.isEmpty ? '没能取到官方列表' : '官方列表可能不是最新的',
              subtitle: store.listProblem,
              dim: true),
        for (final category in storeCategoryNames.keys)
          if (groups[category] case final items?) ...[
            _Heading(storeCategoryNames[category]!),
            for (final item in items) _row(item),
          ],
        if (store.fromNpm.isNotEmpty) ...[
          const _Heading('来自 npm（未审核）'),
          for (final item in store.fromNpm) _row(item),
        ],
      ],
      SettingsRow(
        title: '安装 npm 包',
        subtitle: _errors['npm'] ??
            'DeepSeek Harness 插件，或带 SKILL.md 的技能包。没有经过审核，安装前请确认来历。',
        below: Row(children: [
          Expanded(
            child: LiveTextField(
                value: _npm,
                width: null,
                mono: true,
                hint: '包名，例如 some-plugin 或 @scope/name@1.2.3',
                label: 'npm 包名',
                onChanged: (value) => setState(() => _npm = value)),
          ),
          const SizedBox(width: 10),
          PillButton(
              label: '安装',
              busy: _busy.contains('npm'),
              onTap: _busy.contains('npm') || _npm.trim().isEmpty
                  ? null
                  : _installNpm),
        ]),
      ),
    ]);
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
        child: Text(text,
            style: NextText.sans(12,
                weight: FontWeight.w600, color: NextColors.p3)),
      );
}

/// What an item says of itself before it is installed; yes or no.
class _Notices extends StatelessWidget {
  const _Notices(
      {required this.title, required this.notices, required this.onAnswer});
  final String title;
  final List<String> notices;
  final void Function([bool?]) onAnswer;

  @override
  Widget build(BuildContext context) => SheetSurface(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: NextText.sans(16, weight: FontWeight.w600)),
              const SizedBox(height: 14),
              for (final notice in notices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(notice,
                      key: const Key('store.notice'),
                      style: NextText.sans(13.5,
                          color: NextColors.p2, height: 1.55)),
                ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                PillButton(label: '取消', onTap: () => onAnswer(false)),
                const SizedBox(width: 10),
                PillButton(
                    key: const Key('store.notice.accept'),
                    label: '我知道了，安装',
                    primary: true,
                    onTap: () => onAnswer(true)),
              ]),
            ]),
      );
}

class _Details extends StatelessWidget {
  const _Details(
      {required this.item, required this.readme, required this.onClose});
  final UiStoreItem item;
  final Future<String?>? readme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SheetSurface(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(item.name,
                      style: NextText.sans(17, weight: FontWeight.w600)),
                ),
                NextIconButton(
                    glyph: NextGlyph.close, label: '关闭', onTap: onClose),
              ]),
              const SizedBox(height: 6),
              Text(
                  [
                    item.plugin ? '插件' : '技能',
                    item.reviewed ? '官方' : '未审核',
                    item.version,
                    if (item.author != null) item.author!,
                  ].join(' · '),
                  style: NextText.sans(12.5, color: NextColors.p3)),
              const SizedBox(height: 12),
              Text(item.description,
                  style: NextText.sans(14, color: NextColors.p2, height: 1.5)),
              for (final notice in item.notices)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(notice,
                      style: NextText.sans(13,
                          color: NextColors.accent2, height: 1.5)),
                ),
              if (readme case final readme?)
                FutureBuilder<String?>(
                  future: readme,
                  builder: (context, snapshot) => Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        child: Text(
                            snapshot.hasError
                                ? '说明没能取到'
                                : snapshot.data ??
                                    (snapshot.connectionState ==
                                            ConnectionState.done
                                        ? '没有说明'
                                        : '正在读取说明…'),
                            style: NextText.sans(13,
                                color: NextColors.p3, height: 1.6)),
                      ),
                    ),
                  ),
                ),
            ]),
      );
}
