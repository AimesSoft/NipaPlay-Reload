import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:provider/provider.dart';

import '../../next_runtime.dart';
import '../../ui_data/ui_data.dart';
import '../conversation/chat_port.dart';
import '../dev/dev_services.dart';
import 'core_connect.dart';
import 'ui_actions.dart';

/// Everything the Next shell talks to.
final class NextUiServices {
  NextUiServices({
    required this.data,
    required this.actions,
    required this.chat,
    this.onDispose,
  });

  final NextUiData data;
  final NextUiActions actions;
  final ChatPort chat;
  final VoidCallback? onDispose;

  void dispose() {
    chat.dispose();
    onDispose?.call();
  }

  /// Production: NextCore's data and the embedded chat host. Debug lab
  /// profiles may opt into scripted data for screenshots; release builds
  /// never reach that branch.
  static NextUiServices resolve(BuildContext context) {
    if (kDebugMode) {
      final dev = NextUiDev.services(context);
      if (dev != null) return dev;
    }
    final core = ServiceProvider.nextCore;
    final runtime = context.read<NextRuntime>();
    return NextUiServices(
      data: coreUiData(core),
      actions: coreUiActions(core, runtime),
      chat: ChatHostPort(runtime),
    );
  }
}
