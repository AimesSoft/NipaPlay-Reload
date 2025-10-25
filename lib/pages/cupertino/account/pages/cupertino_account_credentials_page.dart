import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoCredentialField {
  final String label;
  final TextEditingController controller;
  final String placeholder;
  final bool obscureText;

  const CupertinoCredentialField({
    required this.label,
    required this.controller,
    required this.placeholder,
    this.obscureText = false,
  });
}

class CupertinoAccountCredentialsPage extends StatefulWidget {
  final String title;
  final String actionLabel;
  final List<CupertinoCredentialField> fields;
  final Future<bool> Function() onSubmit;
  final Widget? footer;

  const CupertinoAccountCredentialsPage({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.fields,
    required this.onSubmit,
    this.footer,
  });

  @override
  State<CupertinoAccountCredentialsPage> createState() =>
      _CupertinoAccountCredentialsPageState();
}

class _CupertinoAccountCredentialsPageState
    extends State<CupertinoAccountCredentialsPage> {
  bool _isSubmitting = false;

  Future<void> _handleSubmit() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    final success = await widget.onSubmit();

    if (mounted) {
      setState(() {
        _isSubmitting = false;
      });
    }

    if (success && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: widget.title,
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
            children: [
              AdaptiveFormSection.insetGrouped(
                backgroundColor: sectionBackground,
                children: [
                  for (final field in widget.fields)
                    CupertinoFormRow(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      prefix: Text(field.label),
                      child: AdaptiveTextField(
                        controller: field.controller,
                        placeholder: field.placeholder,
                        obscureText: field.obscureText,
                      ),
                    ),
                ],
              ),
              if (widget.footer != null) ...[
                const SizedBox(height: 20),
                widget.footer!,
              ],
              const SizedBox(height: 32),
              AdaptiveButton.child(
                onPressed: _isSubmitting ? null : _handleSubmit,
                style: AdaptiveButtonStyle.filled,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isSubmitting)
                      const CupertinoActivityIndicator(radius: 9)
                    else
                      const Icon(CupertinoIcons.check_mark_circled_solid, size: 18),
                    const SizedBox(width: 8),
                    Text(widget.actionLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
