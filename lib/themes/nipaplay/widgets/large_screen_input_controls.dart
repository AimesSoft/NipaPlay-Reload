import 'package:flutter/services.dart';

enum NipaplayLargeScreenInputCommand {
  toggleMenu,
  navigateUp,
  navigateDown,
  navigateLeft,
  navigateRight,
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

  static final Set<LogicalKeyboardKey> _navigateLeftKeys = {
    LogicalKeyboardKey.arrowLeft,
  };

  static final Set<LogicalKeyboardKey> _navigateRightKeys = {
    LogicalKeyboardKey.arrowRight,
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
    if (_navigateLeftKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.navigateLeft;
    }
    if (_navigateRightKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.navigateRight;
    }
    if (_activateKeys.contains(key)) {
      return NipaplayLargeScreenInputCommand.activate;
    }
    return null;
  }
}
