import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoPaneBackButton extends StatelessWidget {
  const CupertinoPaneBackButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: CupertinoButton.filled(
          onPressed: onPressed,
          child: const Text('返回'),
        ),
      ),
    );
  }
}
