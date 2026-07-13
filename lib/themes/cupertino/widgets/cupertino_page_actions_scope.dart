import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

class CupertinoPageAction {
  const CupertinoPageAction({
    required this.id,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
}

class CupertinoPageActionsController extends ChangeNotifier {
  Object? _owner;
  List<CupertinoPageAction> _actions = const [];

  List<CupertinoPageAction> get actions => _actions;

  void setActions(Object owner, List<CupertinoPageAction> actions) {
    if (identical(_owner, owner) && _sameActions(_actions, actions)) return;
    _owner = owner;
    _actions = List.unmodifiable(actions);
    notifyListeners();
  }

  void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _actions = const [];
    notifyListeners();
  }

  void reset() {
    if (_owner == null && _actions.isEmpty) return;
    _owner = null;
    _actions = const [];
    notifyListeners();
  }

  bool _sameActions(
    List<CupertinoPageAction> first,
    List<CupertinoPageAction> second,
  ) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index].id != second[index].id ||
          first[index].label != second[index].label ||
          first[index].icon != second[index].icon ||
          first[index].onPressed != second[index].onPressed) {
        return false;
      }
    }
    return true;
  }
}

class CupertinoPageActionsScope
    extends InheritedNotifier<CupertinoPageActionsController> {
  const CupertinoPageActionsScope({
    super.key,
    required CupertinoPageActionsController controller,
    required super.child,
  }) : super(notifier: controller);

  static CupertinoPageActionsController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CupertinoPageActionsScope>()
        ?.notifier;
  }
}
