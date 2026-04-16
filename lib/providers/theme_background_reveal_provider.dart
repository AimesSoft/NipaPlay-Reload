import 'package:flutter/material.dart';

class ThemeBackgroundRevealProvider with ChangeNotifier {
  bool _isActive = false;
  int _epoch = 0;
  Offset _origin = Offset.zero;
  double _maxRadius = 0;
  Color _color = Colors.transparent;
  bool _reverse = false;
  bool _themeUpdated = false;
  bool _animationCompleted = false;
  bool _finishScheduled = false;

  bool get isActive => _isActive;
  int get epoch => _epoch;
  Offset get origin => _origin;
  double get maxRadius => _maxRadius;
  Color get color => _color;
  bool get reverse => _reverse;

  static const Duration duration = Duration(milliseconds: 420);

  bool startReveal({
    required Offset origin,
    required double maxRadius,
    required Color color,
    required bool reverse,
  }) {
    if (_isActive) {
      return false;
    }
    _isActive = true;
    _origin = origin;
    _maxRadius = maxRadius;
    _color = color;
    _reverse = reverse;
    _themeUpdated = false;
    _animationCompleted = false;
    _finishScheduled = false;
    _epoch += 1;
    notifyListeners();
    return true;
  }

  void markThemeUpdated(int epoch) {
    if (!_isActive || epoch != _epoch) {
      return;
    }
    _themeUpdated = true;
    _tryFinish(epoch);
  }

  void markAnimationCompleted(int epoch) {
    if (!_isActive || epoch != _epoch) {
      return;
    }
    _animationCompleted = true;
    _tryFinish(epoch);
  }

  void _tryFinish(int epoch) {
    if (!_isActive || epoch != _epoch) {
      return;
    }
    if (!_themeUpdated || !_animationCompleted) {
      return;
    }
    if (_finishScheduled) {
      return;
    }
    _finishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 16), () {
        if (!_isActive || epoch != _epoch) {
          _finishScheduled = false;
          return;
        }
        _isActive = false;
        _finishScheduled = false;
        notifyListeners();
      });
    });
  }
}
