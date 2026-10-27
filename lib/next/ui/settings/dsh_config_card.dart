import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../ui_data/host_settings.dart';
import 'controls.dart';

/// Common controls and the raw JSON edit the same document. No background
/// refresh can replace an unsaved draft.
class DshConfigCard extends StatefulWidget {
  const DshConfigCard({super.key, required this.host});
  final NextHostDshConfigSettings host;
  @override
  State<DshConfigCard> createState() => _DshConfigCardState();
}

class _DshConfigCardState extends State<DshConfigCard> {
  UiDshConfig? _saved;
  String _text = '', _error = '';
  bool _busy = false, _raw = false, _dirty = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _run(_read);
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _read() async {
    final value = await widget.host.dshConfig();
    if (!mounted) return;
    setState(() {
      _saved = value;
      _text = value.text;
      _error = value.error ?? '';
      _dirty = false;
      _generation++;
    });
  }

  Map<String, dynamic> get _document {
    try {
      return jsonDecode(_text) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Object? _value(String path) {
    Object? value = _document;
    for (final key in path.split('.')) {
      value = value is Map ? value[key] : null;
    }
    return value;
  }

  void _change(String path, Object? value) {
    try {
      final document = jsonDecode(_text) as Map<String, dynamic>;
      var node = document;
      final keys = path.split('.');
      for (final key in keys.take(keys.length - 1)) {
        node = (node[key] ??= <String, dynamic>{}) as Map<String, dynamic>;
      }
      if (value == null) {
        node.remove(keys.last);
      } else {
        node[keys.last] = value;
      }
      setState(() {
        _text = const JsonEncoder.withIndent('  ').convert(document);
        _dirty = true;
        _error = '';
      });
    } catch (_) {
      setState(() => _error = '请先在 JSON 编辑器中修正配置结构');
    }
  }

  Widget _number(String title, String path, String hint) => SettingsRow(
        title: title,
        trailing: LiveTextField(
          key: ValueKey('$path:$_generation'),
          width: 140,
          value: _value(path)?.toString() ?? '',
          hint: hint,
          onChanged: (text) => _change(
              path, text.trim().isEmpty ? null : num.tryParse(text) ?? text),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final auto = _value('compaction.auto') != false;
    return SettingsCard(title: 'DSH 高级配置 · Alpha', children: [
      const SettingsRow(
        title: '上下文与压缩',
        subtitle: '留空沿用 DSH 默认值，并不代表服务商实际容量。保存后在下一轮对话生效；执行中的回合和子任务继续完成。',
      ),
      if (saved != null) ...[
        _number('上下文容量（token）', 'model.contextWindow', '262144'),
        _number('输出上限（token）', 'model.maxTokens', '32768'),
        _number('请求输出上限（覆盖模型值）', 'request.maxTokens', '沿用模型'),
        _number('请求重试次数', 'provider.retryPolicy.maxRetries', '3'),
        SettingsRow(
            title: '自动压缩',
            trailing: PillButton(
              label: auto ? '已开启' : '已关闭',
              onTap: () => _change('compaction.auto', !auto),
            )),
        _number('压缩触发比例', 'compaction.thresholdRatio', '0.8'),
        _number('近期内容保留比例', 'compaction.retainRatio', '0.16'),
        _number('近期内容保留 token（与比例二选一）', 'compaction.retainTokens', '未指定'),
        _number('压缩预留 token', 'compaction.headroomTokens', '65536'),
        _number('摘要输出上限', 'compaction.maxTokens', '沿用压缩预留'),
        _number('压缩重试次数', 'compaction.compactionRetries', '1'),
        _number('上下文溢出恢复次数', 'compaction.maxOverflowRetries', '1'),
        SettingsRow(
          title: '原生 JSON 配置',
          subtitle:
              'model / provider / request / compaction / plugins。支持超时、传输方式、兼容参数、分模型压缩策略与现有插件配置。API 地址和密钥仍在模型设置管理。',
          trailing: PillButton(
              label: _raw ? '收起' : '编辑 JSON',
              onTap: () => setState(() => _raw = !_raw)),
          below: _raw
              ? LiveTextField(
                  key: ValueKey('json:$_generation'),
                  width: null,
                  lines: 16,
                  mono: true,
                  value: _text,
                  onChanged: (text) => setState(() {
                    _text = text;
                    _dirty = true;
                  }),
                )
              : null,
        ),
        SettingsRow(
          title: _dirty
              ? '尚未保存'
              : saved.fingerprint != null &&
                      saved.fingerprint == saved.activeFingerprint
                  ? '当前配置已生效'
                  : '下次启动或下一轮对话时应用',
          subtitle: _error.isNotEmpty ? _error : saved.path,
          below: Wrap(spacing: 8, runSpacing: 8, children: [
            PillButton(
                label: '保存配置',
                primary: true,
                busy: _busy,
                onTap: !_dirty || _busy
                    ? null
                    : () => _run(() async {
                          await widget.host.saveDshConfig(_text,
                              expectedRevision: saved.revision);
                          await _read();
                        })),
            PillButton(
                label: _dirty ? '放弃草稿并重新读取' : '重新读取',
                onTap: _busy ? null : () => _run(_read)),
            PillButton(
                label: '打开配置文件',
                onTap: _busy ? null : () => _run(widget.host.openDshConfig)),
          ]),
        ),
      ] else
        SettingsRow(
            title: _error.isEmpty ? '读取配置…' : _error,
            trailing: PillButton(
                label: '重试', onTap: _busy ? null : () => _run(_read))),
    ]);
  }
}
