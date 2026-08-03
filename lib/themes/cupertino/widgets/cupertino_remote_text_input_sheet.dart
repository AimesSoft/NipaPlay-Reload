import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:nipaplay/services/remote_text_input_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoRemoteTextInputSheet {
  const CupertinoRemoteTextInputSheet._();

  static Future<void> show(
    BuildContext context,
    RemoteTextInputRequest request,
  ) {
    return CupertinoBottomSheet.show<void>(
      context: context,
      title: 'Apple TV 远程输入',
      floatingTitle: true,
      heightRatio: 0.84,
      child: _CupertinoRemoteTextInputContent(request: request),
    );
  }
}

class _CupertinoRemoteTextInputContent extends StatefulWidget {
  const _CupertinoRemoteTextInputContent({required this.request});

  final RemoteTextInputRequest request;

  @override
  State<_CupertinoRemoteTextInputContent> createState() =>
      _CupertinoRemoteTextInputContentState();
}

class _CupertinoRemoteTextInputContentState
    extends State<_CupertinoRemoteTextInputContent> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  RemoteTextInputMetadata? _metadata;
  Object? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final metadata = await RemoteTextInputClientService.fetchMetadata(
        widget.request,
      );
      if (!mounted) return;
      for (final field in metadata.fields) {
        final controller = TextEditingController(text: field.initialValue);
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        _controllers[field.id] = controller;
        _focusNodes[field.id] = FocusNode();
      }
      setState(() => _metadata = metadata);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _submit() async {
    final metadata = _metadata;
    if (_isSubmitting || metadata == null) return;
    for (final field in metadata.fields) {
      final value = _controllers[field.id]?.text ?? '';
      if (field.required && value.trim().isEmpty) {
        setState(() => _error = StateError('请填写${field.title}'));
        _focusNodes[field.id]?.requestFocus();
        return;
      }
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await RemoteTextInputClientService.submitValues(
        widget.request,
        <String, String>{
          for (final field in metadata.fields)
            field.id: _controllers[field.id]?.text ?? '',
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = _metadata;
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 28),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (metadata == null && _error == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(child: CupertinoActivityIndicator()),
                  )
                else if (metadata != null) ...[
                  Text(
                    metadata.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'KEY ${metadata.displayKey} · ${metadata.fields.length} 项会一起回填到 Apple TV',
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  for (var index = 0;
                      index < metadata.fields.length;
                      index++) ...[
                    _buildField(
                      metadata.fields[index],
                      index,
                      metadata.fields.length,
                      secondary,
                    ),
                    if (index != metadata.fields.length - 1)
                      const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 18),
                  CupertinoButton.filled(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const CupertinoActivityIndicator(
                            color: CupertinoColors.white,
                          )
                        : const Text('发送到 Apple TV'),
                  ),
                ],
                if (_error != null) ...[
                  if (metadata != null) const SizedBox(height: 14),
                  Text(
                    _error.toString().replaceFirst('Bad state: ', ''),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    RemoteTextInputFieldMetadata field,
    int index,
    int fieldCount,
    Color secondary,
  ) {
    final isLast = index == fieldCount - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${field.title}${field.required ? ' *' : ''}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 7),
        CupertinoTextField(
          controller: _controllers[field.id],
          focusNode: _focusNodes[field.id],
          autofocus: index == 0,
          obscureText: field.obscureText,
          keyboardType: _keyboardType(field.inputType),
          textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
          minLines: field.multiline ? 4 : 1,
          maxLines: field.multiline ? 8 : 1,
          maxLength: field.maxLength,
          placeholder: field.title,
          padding: const EdgeInsets.all(14),
          onSubmitted: field.multiline
              ? null
              : (_) {
                  if (isLast) {
                    _submit();
                  } else {
                    _focusNodes[_metadata!.fields[index + 1].id]
                        ?.requestFocus();
                  }
                },
        ),
        if (field.obscureText && field.hasInitialValue) ...[
          const SizedBox(height: 5),
          Text(
            '留空则保持 Apple TV 上的现有内容',
            style: TextStyle(color: secondary, fontSize: 12),
          ),
        ],
      ],
    );
  }

  TextInputType _keyboardType(String inputType) {
    return switch (inputType) {
      'number' => const TextInputType.numberWithOptions(decimal: true),
      'phone' => TextInputType.phone,
      'email' => TextInputType.emailAddress,
      'url' => TextInputType.url,
      _ => TextInputType.text,
    };
  }
}
