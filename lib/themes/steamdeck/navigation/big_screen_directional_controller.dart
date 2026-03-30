import 'package:flutter/services.dart';

class BigScreenDirectionalController {
  BigScreenDirectionalController({required int sectionCount})
      : _selectedIndexes = List<int>.filled(sectionCount, 0);

  final List<int> _selectedIndexes;
  int _activeSection = 0;

  int get activeSection => _activeSection;

  int selectedIndex(int section) {
    if (section < 0 || section >= _selectedIndexes.length) {
      return 0;
    }
    return _selectedIndexes[section];
  }

  void setSelectedIndex(int section, int index) {
    if (section < 0 || section >= _selectedIndexes.length) {
      return;
    }
    _selectedIndexes[section] = index < 0 ? 0 : index;
  }

  void clampToSectionLengths(List<int> sectionLengths) {
    if (sectionLengths.isEmpty) {
      _activeSection = 0;
      for (var i = 0; i < _selectedIndexes.length; i++) {
        _selectedIndexes[i] = 0;
      }
      return;
    }

    if (_activeSection >= sectionLengths.length) {
      _activeSection = sectionLengths.length - 1;
    }
    if (_activeSection < 0) {
      _activeSection = 0;
    }

    for (var i = 0; i < _selectedIndexes.length; i++) {
      final sectionLength = i < sectionLengths.length ? sectionLengths[i] : 0;
      if (sectionLength <= 0) {
        _selectedIndexes[i] = 0;
        continue;
      }
      final maxIndex = sectionLength - 1;
      final current = _selectedIndexes[i];
      if (current < 0) {
        _selectedIndexes[i] = 0;
      } else if (current > maxIndex) {
        _selectedIndexes[i] = maxIndex;
      }
    }

    if (sectionLengths[_activeSection] <= 0) {
      final firstNonEmpty = sectionLengths.indexWhere((length) => length > 0);
      if (firstNonEmpty >= 0) {
        _activeSection = firstNonEmpty;
      }
    }
  }

  bool handleArrow(
    LogicalKeyboardKey key,
    List<int> sectionLengths,
  ) {
    clampToSectionLengths(sectionLengths);

    if (key == LogicalKeyboardKey.arrowLeft) {
      return _moveHorizontal(-1, sectionLengths);
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      return _moveHorizontal(1, sectionLengths);
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      return _moveVertical(-1, sectionLengths);
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      return _moveVertical(1, sectionLengths);
    }
    return false;
  }

  bool _moveHorizontal(int delta, List<int> sectionLengths) {
    if (_activeSection >= sectionLengths.length) {
      return false;
    }
    final sectionLength = sectionLengths[_activeSection];
    if (sectionLength <= 0) {
      return false;
    }

    final current = _selectedIndexes[_activeSection];
    final next = (current + delta).clamp(0, sectionLength - 1);
    if (next == current) {
      return false;
    }
    _selectedIndexes[_activeSection] = next;
    return true;
  }

  bool _moveVertical(int delta, List<int> sectionLengths) {
    if (sectionLengths.isEmpty) {
      return false;
    }

    var target = _activeSection + delta;
    while (target >= 0 && target < sectionLengths.length) {
      if (sectionLengths[target] > 0) {
        if (target == _activeSection) {
          return false;
        }
        _activeSection = target;
        return true;
      }
      target += delta;
    }
    return false;
  }
}
