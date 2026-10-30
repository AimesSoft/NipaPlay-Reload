import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:provider/provider.dart';

import '../../body/next_body.dart';
import '../../mesh/nipa_peers.dart';
import '../../next_runtime.dart';
import '../../ui_data/library.dart';
import '../../ui_data/ui_data.dart';
import '../conversation/chat_port.dart';
import '../conversation/mesh_chat_port.dart';
import '../dev/dev_services.dart';
import 'core_connect.dart';
import 'core_manage.dart';
import 'core_settings.dart';
import 'background.dart';
import 'batch_manage.dart';
import 'collections.dart';
import 'discover.dart';
import 'downloaders.dart';
import 'downloads.dart';
import 'gui_calls.dart';
import 'history.dart';
import 'login_requests.dart';
import 'search.dart';
import 'settings_data.dart';
import 'ui_actions.dart';
import 'work_manage.dart';
import 'upkeep.dart';

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
    required this.settings,
    LoginRequests? logins,
    this.manage,
    this.peers,
    this.downloaders,
    GuiCalls? calls,
    this.onDispose,
  })  : logins = logins ?? LoginRequests(),
        calls = calls ?? GuiCalls.none();

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
  /// The settings page: the registry, accounts, sources, memory and what
  /// only this device's person may change.
  final NextSettingsData settings;

  /// Logins the agent asked for, waiting for the user's window.
  final LoginRequests logins;

  /// Managing a work and its episodes from the detail page; none where
  /// the shell is shown without it (tests).
  final NextWorkManage? manage;

  /// Where Nipa comes from on a device that cannot run her (an iPad): the
  /// device chosen in its settings. Null where Nipa runs on the device.
  final NipaPeers? peers;

  /// The qBittorrents of 设置 › 下载; none where downloads are not run on
  /// this device or the shell is shown without them (tests).
  final NextDownloaders? downloaders;

  /// Actions the pages call as the person, and what reads them.
  final GuiCalls calls;
  late final downloads = NextDownloads(calls);
  late final background = NextBackground(calls);
  late final history = NextHistory(calls);
  late final collections = NextCollections(calls);
  late final upkeep = NextUpkeep(calls);
  late final plugins = NextPlugins(calls);
  late final sync = NextSync(calls);
  late final folders = NextFolders(calls);
  late final batch = NextBatch(calls, data);
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
    final library = CoreLibrary(core);
    final settings =
        CoreSettingsData(core, runtime, logins, host: runtime.hostSettings);
    final detach = attachCoreLogins(core, logins);
    final peers = NextBody.bodyOnly ? NipaPeers(
            root: core.mesh.root,
            devices: core.mesh.agentDevices,
            hostChanges: core.mesh.hostChanges) : null;
    return NextUiServices(
      data: data,
      actions: coreUiActions(core, runtime),
      chat: peers == null
          ? ChatHostPort(runtime)
          : MeshChatPort(
              call: core.mesh.rpc,
              hostChanges: core.mesh.hostChanges,
              peers: peers,
              playback: runtime.playbackFacts),
      peers: peers,
      downloaders: NextBody.bodyOnly ? null : CoreDownloaders(core),
      discover: CoreDiscover(runtime),
      library: library,
      libraryActions: library,
      search: CoreSearch(() => runtime.harnessReady),
      settings: settings,
      logins: logins,
      manage: CoreWorkManage(() => runtime.harnessReady, data),
      calls: GuiCalls(() => runtime.harnessReady),
      onDispose: () {
        detach();
        settings.dispose();
      },
    );
  }
}
