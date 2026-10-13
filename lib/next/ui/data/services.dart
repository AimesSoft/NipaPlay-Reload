import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:provider/provider.dart';

import '../../next_runtime.dart';
import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import '../conversation/chat_port.dart';
import '../dev/dev_services.dart';
import 'core_connect.dart';
import 'discover.dart';
import 'login_requests.dart';
import 'search.dart';
import 'ui_actions.dart';

/// Everything the Next shell talks to.
final class NextUiServices {
  NextUiServices({
    required this.data,
    required this.actions,
    required this.chat,
    required this.discover,
    required this.library,
    required this.libraryActions,
    required this.search,
    LoginRequests? logins,
    this.onDispose,
  }) : logins = logins ?? LoginRequests();

  final NextUiData data;
  final NextUiActions actions;
  final ChatPort chat;

  /// The 发现 page's calendar and rankings.
  final NextDiscoverData discover;

  /// The 片库 page's sources and categories, and what the viewer changes
  /// in them directly.
  final NextLibraryData library;
  final NextLibraryActions libraryActions;

  /// The search panel's groups.
  final NextSearchData search;

  /// Logins the agent asked for, waiting for the user's window.
  final LoginRequests logins;
  final VoidCallback? onDispose;

  void dispose() {
    chat.dispose();
    onDispose?.call();
    logins.dispose();
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
    final logins = LoginRequests();
    final data = coreUiData(core);
    final library = CoreLocalLibrary(data);
    return NextUiServices(
      data: data,
      actions: coreUiActions(core, runtime),
      chat: ChatHostPort(runtime),
      discover: CoreDiscover(runtime),
      library: library,
      libraryActions: library,
      search: CoreSearch(() => runtime.harness),
      logins: logins,
      onDispose: attachCoreLogins(core, logins),
    );
  }
}
