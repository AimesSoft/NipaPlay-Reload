import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'buttons.dart';

/// A few choices side by side in one quiet pill, the chosen one lit (the
/// library's form and arrangement).
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;

  /// Each choice: its value, what it is called, and how it looks in a
  /// colour.
  final List<(T, String, Widget Function(Color color))> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: const Color(0x0FFFFFFF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: NextColors.line),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (option, label, look) in options)
            Pressable(
              onTap: option == value ? null : () => onChanged(option),
              semanticLabel: label,
              pressScale: 0.96,
              builder: (context, hovered) {
                final on = option == value;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on
                        ? const Color(0x24FFFFFF)
                        : (hovered
                            ? const Color(0x0FFFFFFF)
                            : const Color(0x00FFFFFF)),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: look(on || hovered ? NextColors.paper : NextColors.p3),
                );
              },
            ),
        ]),
      );
}
