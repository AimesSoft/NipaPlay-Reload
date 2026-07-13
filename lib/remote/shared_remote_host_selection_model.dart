import 'package:flutter/foundation.dart';

enum SharedRemoteHostSelectionActionKind {
  scanLan,
  scanQr,
  addManually,
}

class SharedRemoteHostSelectionItem {
  const SharedRemoteHostSelectionItem({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.isOnline,
    required this.isActive,
    required this.lastConnectedLabel,
    required this.onSelect,
    this.errorMessage,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final bool isOnline;
  final bool isActive;
  final String lastConnectedLabel;
  final String? errorMessage;
  final AsyncCallback onSelect;
}

class SharedRemoteHostSelectionAction {
  const SharedRemoteHostSelectionAction({
    required this.kind,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final SharedRemoteHostSelectionActionKind kind;
  final String label;
  final AsyncCallback onPressed;
  final bool enabled;
}

class SharedRemoteHostSelectionViewModel {
  const SharedRemoteHostSelectionViewModel({
    required this.items,
    required this.actions,
  });

  static const String title = '选择共享客户端';
  static const String description = '选择已开启远程访问的 NipaPlay 客户端，随后即可浏览它的媒体库。';

  final List<SharedRemoteHostSelectionItem> items;
  final List<SharedRemoteHostSelectionAction> actions;
}
