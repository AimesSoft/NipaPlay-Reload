import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/services/smb_service.dart';

class CupertinoSmbConnectionDialog {
  static Future<bool?> show(
    BuildContext context, {
    SMBConnection? editConnection,
    Future<bool> Function(SMBConnection)? onSave,
  }) {
    final title = editConnection == null
        ? context.l10n.smbAddServer
        : context.l10n.smbEditServer;
    return CupertinoBottomSheet.show<bool>(
      context: context,
      title: title,
      floatingTitle: true,
      child: _CupertinoSmbConnectionSheet(
        editConnection: editConnection,
        onSave: onSave,
      ),
    );
  }
}

class _CupertinoSmbConnectionSheet extends StatefulWidget {
  const _CupertinoSmbConnectionSheet({
    required this.editConnection,
    required this.onSave,
  });

  final SMBConnection? editConnection;
  final Future<bool> Function(SMBConnection)? onSave;

  @override
  State<_CupertinoSmbConnectionSheet> createState() =>
      _CupertinoSmbConnectionSheetState();
}

class _CupertinoSmbConnectionSheetState
    extends State<_CupertinoSmbConnectionSheet> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final edit = widget.editConnection;
    if (edit != null) {
      _hostController.text = edit.host;
      _portController.text = edit.port.toString();
      _domainController.text = edit.domain;
      _usernameController.text = edit.username;
      _passwordController.text = edit.password;
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _domainController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateInputs() {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      return context.l10n.smbEnterHostOrIp;
    }
    final portText = _portController.text.trim();
    if (portText.isNotEmpty) {
      final port = int.tryParse(portText);
      if (port == null || port <= 0 || port > 65535) {
        return context.l10n.smbInvalidPortRange;
      }
    }
    return null;
  }

  SMBConnection _buildConnection() {
    final host = _hostController.text.trim();
    final portText = _portController.text.trim();
    final port = portText.isEmpty ? 445 : int.parse(portText);
    final domain = _domainController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    final name = widget.editConnection?.name ??
        (port == 445 ? host : '$host:$port');

    return SMBConnection(
      name: name,
      host: host,
      port: port,
      username: username,
      password: password,
      domain: domain,
    );
  }

  Future<void> _handleSave() async {
    if (_isSaving) return;
    final validation = _validateInputs();
    if (validation != null) {
      setState(() {
        _errorMessage = validation;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final connection = _buildConnection();
    bool success = false;
    try {
      if (widget.onSave != null) {
        success = await widget.onSave!(connection);
      } else if (widget.editConnection != null) {
        success = await SMBService.instance
            .updateConnection(widget.editConnection!.name, connection);
      } else {
        success = await SMBService.instance.addConnection(connection);
      }
    } catch (e) {
      success = false;
      if (mounted) {
        AdaptiveSnackBar.show(
          context,
          message: context.l10n.saveFailedWithError('$e'),
          type: AdaptiveSnackBarType.error,
        );
      }
    }

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _isSaving = false;
        _errorMessage = context.l10n.connectFailedCheckCredentials;
      });
    }
  }

  Widget _buildField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? placeholder,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool obscureText = false,
  }) {
    final Color fillColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemGrey5, context);
    final Color labelColor =
        CupertinoDynamicColor.resolve(CupertinoColors.label, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          obscureText: obscureText,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final Color secondaryLabel =
        CupertinoDynamicColor.resolve(CupertinoColors.secondaryLabel, context);
    final Color errorColor =
        CupertinoDynamicColor.resolve(CupertinoColors.systemRed, context);

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) {
        return [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topSpacing + 8, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.smbAnonymousHint,
                    style: TextStyle(fontSize: 13, color: secondaryLabel),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      style: TextStyle(fontSize: 12, color: errorColor),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    context,
                    label: context.l10n.smbHostOrIp,
                    controller: _hostController,
                    placeholder: context.l10n.smbHostOrIpPlaceholder,
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: context.l10n.smbPort,
                    controller: _portController,
                    placeholder: context.l10n.smbDefaultPort445,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: context.l10n.smbDomainOptional,
                    controller: _domainController,
                    placeholder: context.l10n.smbDomainPlaceholder,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: context.l10n.usernameOptional,
                    controller: _usernameController,
                    placeholder: context.l10n.canBeEmpty,
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    context,
                    label: context.l10n.passwordOptional,
                    controller: _passwordController,
                    placeholder: context.l10n.canBeEmpty,
                    obscureText: true,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: CupertinoButton.filled(
                onPressed: _isSaving ? null : _handleSave,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _isSaving
                    ? const CupertinoActivityIndicator(radius: 8)
                    : Text(context.l10n.save),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(height: 16 + bottomPadding),
          ),
        ];
      },
    );
  }
}
