import 'package:flutter/services.dart';

enum NipaplayLargeScreenInputCommand {
  toggleMenu,
  navigateUp,
  navigateDown,
  activate,
}

class NipaplayLargeScreenInputControls {
  const NipaplayLargeScreenInputControls._();

  static final Set<LogicalKeyboardKey> _toggleMenuKeys = {
    LogicalKeyboardKey.escape,
    LogicalKeyboardKey.gameButtonSelect,
    LogicalKeyboardKey.gameButtonStart,
  };

  static final Set<LogicalKeyboardKey> _navigateUpKeys = {
    LogicalKeyboardKey.arrowUp,
  };

  static final Set<LogicalKeyboardKey> _navigateDownKeys = {
    LogicalKeyboardKey.arrowDown,
  };

  static final Set<LogicalKeyboardKey> _activateKeys = {
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.gameButtonA,
  };

  static NipaplayLargeScreenInputCommand? fromKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return null;
    }

    final key = event.logicalKey;
    if (_toggleMenuKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.toggleMenu;
    }
    if (_navigateUpKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.navigateUp;
    }
    if (_navigateDownKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.navigateDown;
    }
    if (_activateKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.activate;
    }
    return null;
  }
}
