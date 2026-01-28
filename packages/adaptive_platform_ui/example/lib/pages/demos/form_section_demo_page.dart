import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Demo page showcasing the AdaptiveFormSection widget.
///
/// Demonstrates different form section styles including:
/// - Basic form sections with headers and footers
/// - Inset grouped style sections
/// - Various form field types using adaptive components
/// - Color customization
class FormSectionDemoPage extends StatefulWidget {
  const FormSectionDemoPage({super.key});

  @override
  State<FormSectionDemoPage> createState() => _FormSectionDemoPageState();
}

class _FormSectionDemoPageState extends State<FormSectionDemoPage> {
  // Form controllers
  final TextEditingController _nameController = TextEditingController(
    text: 'John Doe',
  );
  final TextEditingController _emailController = TextEditingController(
    text: 'john.doe@example.com',
  );
  final TextEditingController _phoneController = TextEditingController(
    text: '+1 (555) 123-4567',
  );
  final TextEditingController _bioController = TextEditingController(
    text: 'Software developer passionate about mobile apps.',
  );

  // Settings
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _autoSaveEnabled = true;
  String _selectedLanguage = 'English';
  double _fontSize = 14.0;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = PlatformInfo.isIOS;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AdaptiveScaffold(
        appBar: AdaptiveAppBar(
          title: 'Form Section Demo',
          actions: [
            AdaptiveAppBarAction(
              onPressed: _saveForm,
              iosSymbol: 'checkmark.circle.fill',
              icon: Icons.check_circle,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(0),
            children: [
              const SizedBox(height: 60),

              // Section 1: Account Details with Text Fields (Default Style)
              AdaptiveFormSection(
                header: const Text('ACCOUNT DETAILS'),
                footer: const Text('Your personal account information.'),
                children: [
                  _buildTextFieldRow(
                    context,
                    prefix: 'Name',
                    controller: _nameController,
                    placeholder: 'Enter your name',
                  ),
                  _buildTextFieldRow(
                    context,
                    prefix: 'Email',
                    controller: _emailController,
                    placeholder: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _buildTextFieldRow(
                    context,
                    prefix: 'Phone',
                    controller: _phoneController,
                    placeholder: 'Enter your phone',
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Section 2: Bio (Inset Grouped with multiline)
              AdaptiveFormSection.insetGrouped(
                header: const Text('BIO'),
                footer: const Text('Tell us about yourself.'),
                children: [
                  _buildTextFieldRow(
                    context,
                    prefix: 'About',
                    controller: _bioController,
                    placeholder: 'Enter your bio',
                    maxLines: 3,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Section 3: Settings with Switches (Inset Grouped Style)
              AdaptiveFormSection.insetGrouped(
                header: const Text('SETTINGS'),
                footer: const Text('Configure your app preferences.'),
                children: [
                  _buildSwitchRow(
                    context,
                    prefix: 'Notifications',
                    value: _notificationsEnabled,
                    onChanged: (value) {
                      setState(() {
                        _notificationsEnabled = value;
                      });
                    },
                  ),
                  _buildSwitchRow(
                    context,
                    prefix: 'Dark Mode',
                    value: _darkModeEnabled,
                    onChanged: (value) {
                      setState(() {
                        _darkModeEnabled = value;
                      });
                    },
                  ),
                  _buildSwitchRow(
                    context,
                    prefix: 'Auto-save',
                    value: _autoSaveEnabled,
                    onChanged: (value) {
                      setState(() {
                        _autoSaveEnabled = value;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Section 4: Language Selection (Inset Grouped with Custom Color)
              AdaptiveFormSection.insetGrouped(
                header: const Text('LANGUAGE'),
                footer: const Text('Select your preferred language.'),
                backgroundColor: isIOS
                    ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
                children: [
                  _buildFormRow(
                    context,
                    prefix: 'Language',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedLanguage,
                          style: TextStyle(
                            color: isIOS
                                ? CupertinoColors.systemGrey
                                : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isIOS
                              ? CupertinoIcons.chevron_forward
                              : Icons.chevron_right,
                          size: 20,
                          color: isIOS
                              ? CupertinoColors.systemGrey
                              : Colors.grey[600],
                        ),
                      ],
                    ),
                    onTap: () => _showLanguagePicker(context),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Section 5: Font Size with Slider (Inset Grouped)
              AdaptiveFormSection.insetGrouped(
                header: const Text('APPEARANCE'),
                footer: Text(
                  'Current font size: ${_fontSize.toStringAsFixed(0)}pt',
                ),
                children: [
                  _buildSliderRow(
                    context,
                    prefix: 'Font Size',
                    value: _fontSize,
                    min: 12.0,
                    max: 24.0,
                    onChanged: (value) {
                      setState(() {
                        _fontSize = value;
                      });
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Section 6: About (Default Style)
              AdaptiveFormSection(
                header: const Text('ABOUT'),
                children: [
                  _buildFormRow(
                    context,
                    prefix: 'Version',
                    child: const Text('1.0.0'),
                  ),
                  _buildFormRow(
                    context,
                    prefix: 'Build',
                    child: const Text('100'),
                  ),
                  _buildFormRow(
                    context,
                    prefix: 'License',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View',
                          style: TextStyle(
                            color: isIOS
                                ? CupertinoColors.activeBlue
                                : Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isIOS
                              ? CupertinoIcons.chevron_forward
                              : Icons.chevron_right,
                          size: 20,
                          color: isIOS
                              ? CupertinoColors.systemGrey
                              : Colors.grey[600],
                        ),
                      ],
                    ),
                    onTap: () {
                      _showLicenseDialog(context);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Section 7: Danger Zone (Inset Grouped with Red Background)
              AdaptiveFormSection.insetGrouped(
                header: const Text('DANGER ZONE'),
                footer: const Text('Proceed with caution.'),
                backgroundColor: isIOS
                    ? CupertinoColors.systemRed.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                children: [
                  _buildFormRow(
                    context,
                    prefix: 'Delete Account',
                    child: Icon(
                      isIOS
                          ? CupertinoIcons.chevron_forward
                          : Icons.chevron_right,
                      size: 20,
                      color: isIOS ? CupertinoColors.systemRed : Colors.red,
                    ),
                    onTap: () {
                      _showDeleteConfirmation(context);
                    },
                  ),
                ],
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextFieldRow(
    BuildContext context, {
    required String prefix,
    required TextEditingController controller,
    required String placeholder,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    if (PlatformInfo.isIOS) {
      return CupertinoFormRow(
        prefix: Text(prefix),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: AdaptiveTextField(
          controller: controller,
          placeholder: placeholder,
          keyboardType: keyboardType,
          maxLines: maxLines,
          textAlign: TextAlign.end,
        ),
      );
    }

    // Android implementation
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prefix,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          AdaptiveTextField(
            controller: controller,
            placeholder: placeholder,
            keyboardType: keyboardType,
            maxLines: maxLines,
          ),
        ],
      ),
    );
  }

  Widget _buildFormRow(
    BuildContext context, {
    required String prefix,
    required Widget child,
    VoidCallback? onTap,
  }) {
    if (PlatformInfo.isIOS) {
      return CupertinoFormRow(
        prefix: Text(prefix),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        helper: onTap != null ? const SizedBox.shrink() : null,
        child: GestureDetector(onTap: onTap, child: child),
      );
    }

    // Android implementation
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              prefix,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required String prefix,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    if (PlatformInfo.isIOS) {
      return CupertinoFormRow(
        prefix: Text(prefix),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: AdaptiveSwitch(value: value, onChanged: onChanged),
      );
    }

    // Android implementation
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            prefix,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          AdaptiveSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    BuildContext context, {
    required String prefix,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    if (PlatformInfo.isIOS) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prefix, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: AdaptiveSlider(
                value: value,
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      );
    }

    // Android implementation
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prefix,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          AdaptiveSlider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final languages = ['English', 'Spanish', 'French', 'German', 'Japanese'];

    if (PlatformInfo.isIOS) {
      showCupertinoModalPopup<void>(
        context: context,
        builder: (BuildContext context) {
          return Container(
            height: 250,
            color: CupertinoColors.systemBackground.resolveFrom(context),
            child: CupertinoPicker(
              itemExtent: 40,
              onSelectedItemChanged: (int index) {
                setState(() {
                  _selectedLanguage = languages[index];
                });
              },
              children: languages
                  .map((lang) => Center(child: Text(lang)))
                  .toList(),
            ),
          );
        },
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Select Language'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: languages.map((lang) {
                return ListTile(
                  title: Text(lang),
                  selected: lang == _selectedLanguage,
                  onTap: () {
                    setState(() {
                      _selectedLanguage = lang;
                    });
                    Navigator.of(context).pop();
                  },
                );
              }).toList(),
            ),
          );
        },
      );
    }
  }

  void _showLicenseDialog(BuildContext context) {
    AdaptiveAlertDialog.show(
      context: context,
      title: 'License',
      message:
          'MIT License\n\nCopyright (c) 2025\n\nPermission is hereby '
          'granted, free of charge, to any person obtaining a copy...',
      actions: [
        AlertAction(
          title: 'Close',
          onPressed: () {},
          style: AlertActionStyle.defaultAction,
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    AdaptiveAlertDialog.show(
      context: context,
      title: 'Delete Account',
      message:
          'Are you sure you want to delete your account? '
          'This action cannot be undone.',
      actions: [
        AlertAction(
          title: 'Cancel',
          onPressed: () {},
          style: AlertActionStyle.cancel,
        ),
        AlertAction(
          title: 'Delete',
          onPressed: () {
            // Show confirmation snackbar
            AdaptiveSnackBar.show(
              context,
              message: 'Account deletion cancelled',
              type: AdaptiveSnackBarType.info,
            );
          },
          style: AlertActionStyle.destructive,
        ),
      ],
    );
  }

  void _saveForm() {
    AdaptiveSnackBar.show(
      context,
      message: 'Form saved successfully!',
      type: AdaptiveSnackBarType.success,
    );
  }
}
