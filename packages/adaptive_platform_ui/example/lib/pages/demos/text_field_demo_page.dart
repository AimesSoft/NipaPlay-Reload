import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class TextFieldDemoPage extends StatefulWidget {
  const TextFieldDemoPage({super.key});

  @override
  State<TextFieldDemoPage> createState() => _TextFieldDemoPageState();
}

class _TextFieldDemoPageState extends State<TextFieldDemoPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _bioController = TextEditingController();

  String? _savedName;
  String? _savedEmail;
  String? _savedPassword;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = PlatformInfo.isIOS
        ? MediaQuery.platformBrightnessOf(context) == Brightness.dark
        : Theme.of(context).brightness == Brightness.dark;

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(title: 'Text Field'),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 100),
            _buildInfoCard(context, isDark),
            const SizedBox(height: 24),
            _buildSection(
              context,
              isDark,
              title: 'Basic Text Fields',
              children: [
                const Text(
                  'Name',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                AdaptiveTextField(
                  placeholder: 'Enter your name',
                  prefixIcon: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.person : Icons.person,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Email',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                AdaptiveTextField(
                  placeholder: 'Enter your email',
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.mail : Icons.email,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Password',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                AdaptiveTextField(
                  placeholder: 'Enter your password',
                  obscureText: true,
                  prefixIcon: Icon(
                    PlatformInfo.isIOS ? CupertinoIcons.lock : Icons.lock,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              isDark,
              title: 'Multiline Text Field',
              children: [
                const Text(
                  'Bio',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                AdaptiveTextField(
                  controller: _bioController,
                  placeholder: 'Tell us about yourself',
                  maxLines: 5,
                  minLines: 3,
                  keyboardType: TextInputType.multiline,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              isDark,
              title: 'Text Field with Character Limit',
              children: [
                const Text(
                  'Username (max 20 characters)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                AdaptiveTextField(
                  placeholder: 'Enter username',
                  maxLength: 20,
                  prefixIcon: Icon(
                    PlatformInfo.isIOS
                        ? CupertinoIcons.at
                        : Icons.alternate_email,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSection(
              context,
              isDark,
              title: 'Form with Validation',
              children: [
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Name *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AdaptiveTextFormField(
                        controller: _nameController,
                        placeholder: 'Enter your name',
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your name';
                          }
                          return null;
                        },
                        prefixIcon: Icon(
                          PlatformInfo.isIOS
                              ? CupertinoIcons.person
                              : Icons.person,
                        ),
                        suffixIcon: SizedBox(
                          height: 40,
                          width: 40,
                          child: AdaptiveButton.icon(
                            style: PlatformInfo.isIOS26OrHigher()
                                ? AdaptiveButtonStyle.prominentGlass
                                : AdaptiveButtonStyle.filled,
                            icon: PlatformInfo.isIOS
                                ? CupertinoIcons.clear_circled
                                : Icons.clear,
                            iconColor: Colors.white,
                            onPressed: () {
                              _nameController.clear();
                            },
                          ),
                        ),
                        onSaved: (value) => _savedName = value,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Email *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AdaptiveTextFormField(
                        controller: _emailController,
                        placeholder: 'Enter your email',
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                        prefixIcon: Icon(
                          PlatformInfo.isIOS
                              ? CupertinoIcons.mail
                              : Icons.email,
                        ),
                        onSaved: (value) => _savedEmail = value,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Password *',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AdaptiveTextFormField(
                        controller: _passwordController,
                        placeholder: 'Enter your password',
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          if (value.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                        prefixIcon: Icon(
                          PlatformInfo.isIOS ? CupertinoIcons.lock : Icons.lock,
                        ),
                        onSaved: (value) => _savedPassword = value,
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: AdaptiveButton(
                          onPressed: _submitForm,
                          label: 'Submit Form',
                          style: AdaptiveButtonStyle.filled,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_savedName != null) ...[
              const SizedBox(height: 24),
              AdaptiveCard(
                padding: const EdgeInsets.all(16),
                color: isDark
                    ? (PlatformInfo.isIOS
                          ? CupertinoColors.systemGreen.darkColor.withValues(
                              alpha: 0.2,
                            )
                          : Colors.green.shade900.withValues(alpha: 0.3))
                    : (PlatformInfo.isIOS
                          ? CupertinoColors.systemGreen.color.withValues(
                              alpha: 0.1,
                            )
                          : Colors.green.shade50),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          PlatformInfo.isIOS
                              ? CupertinoIcons.check_mark_circled_solid
                              : Icons.check_circle,
                          color: PlatformInfo.isIOS
                              ? CupertinoColors.systemGreen
                              : Colors.green.shade700,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Form Submitted',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                            color: isDark
                                ? (PlatformInfo.isIOS
                                      ? CupertinoColors.white
                                      : Colors.white)
                                : (PlatformInfo.isIOS
                                      ? CupertinoColors.black
                                      : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Name: $_savedName'),
                    Text('Email: $_savedEmail'),
                    Text(
                      'Password: ${_savedPassword?.replaceAll(RegExp('.'), '•')}',
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() {});
      AdaptiveSnackBar.show(
        context,
        message: 'Form submitted successfully!',
        type: AdaptiveSnackBarType.success,
      );
    }
  }

  Widget _buildInfoCard(BuildContext context, bool isDark) {
    return AdaptiveCard(
      padding: const EdgeInsets.all(16),
      color: isDark
          ? (PlatformInfo.isIOS
                ? CupertinoColors.systemBlue.darkColor.withValues(alpha: 0.2)
                : Colors.blue.shade900.withValues(alpha: 0.3))
          : (PlatformInfo.isIOS
                ? CupertinoColors.systemBlue.color.withValues(alpha: 0.1)
                : Colors.blue.shade50),
      child: Row(
        children: [
          Icon(
            PlatformInfo.isIOS ? CupertinoIcons.info_circle_fill : Icons.info,
            color: PlatformInfo.isIOS
                ? CupertinoColors.systemBlue
                : Colors.blue.shade700,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              PlatformInfo.isIOS
                  ? 'iOS uses CupertinoTextField and CupertinoTextFormFieldRow'
                  : 'Android uses Material TextField and TextFormField',
              style: TextStyle(
                fontSize: 14,
                color: isDark
                    ? (PlatformInfo.isIOS
                          ? CupertinoColors.white
                          : Colors.white)
                    : (PlatformInfo.isIOS
                          ? CupertinoColors.black
                          : Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    bool isDark, {
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? (PlatformInfo.isIOS ? CupertinoColors.white : Colors.white)
                  : (PlatformInfo.isIOS
                        ? CupertinoColors.black
                        : Colors.black87),
            ),
          ),
        ),
        AdaptiveCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}
