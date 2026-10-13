import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/lab_profile.dart';
import 'package:provider/provider.dart';

import '../../next_runtime.dart';
import '../conversation/chat_port.dart';
import '../data/gui_calls.dart';
import '../data/services.dart';
import '../theme/tokens.dart';
import 'fake_settings.dart';
import 'fake_world.dart';

/// Development and screenshot switches. Only read in Debug lab profiles:
///
/// - `NIPAPLAY_NEXT_UI_FAKE=<dir>`: scripted data from a TMDB sample
///   directory with `meta.json` (e.g. `/tmp/nipa-next/visual/tmdb`).
/// - `NIPAPLAY_NEXT_UI_FAKE_CHAT=1`: scripted conversation instead of the
///   embedded chat host.
/// - `NIPAPLAY_NEXT_UI_FAKE_TASKS=0`: no background task.
/// - `NIPAPLAY_NEXT_UI_FAKE_FOLLOWUP=<seconds>`: Nipa wakes up on its own.
/// - `NIPAPLAY_NEXT_UI_REDUCE_MOTION=1`: force the reduced motion path.
abstract final class NextUiDev {
  static bool get enabled => kDebugMode && LabProfile.active;

  static NextUiServices? services(BuildContext context) {
    if (!enabled) return null;
    final env = Platform.environment;
    if (env['NIPAPLAY_NEXT_UI_REDUCE_MOTION'] == '1') {
      NextMotion.forceReduced = true;
    }
    final dir = env['NIPAPLAY_NEXT_UI_FAKE'];
    if (dir == null || dir.isEmpty) return null;
    final world = FakeWorld.load(
      dir,
      tasks: env['NIPAPLAY_NEXT_UI_FAKE_TASKS'] != '0',
      followupAfter: int.tryParse(env['NIPAPLAY_NEXT_UI_FAKE_FOLLOWUP'] ?? ''),
    );
    if (world == null) return null;
    final runtime = context.read<NextRuntime>();
    final ChatPort chat = env['NIPAPLAY_NEXT_UI_FAKE_CHAT'] == '1'
        ? FakeChatPort(world)
        : ChatHostPort(runtime);
    // The registry's real contracts, read only; values stay in the script.
    final settings = FakeSettings(describe: () async {
      final outcome = await runtime.harness.invokeJson(
          'settings.describe', {'limit': 1000}, Invocation(origin: 'gui'));
      if (outcome case Completed(:final value)) {
        return (value.toJson()['settings'] as List).cast<Map>();
      }
      throw StateError('settings.describe');
    });
    world.calls.accounts = () async =>
        {for (final a in await settings.accounts()) a.provider: a.loggedIn};
    return NextUiServices(
      data: world,
      actions: world,
      chat: chat,
      discover: world,
      library: world.catalog,
      libraryActions: world.catalog,
      search: world.search,
      settings: settings,
      calls: GuiCalls(() async => world.calls.harness),
      onDispose: () {
        world.dispose();
        settings.dispose();
      },
    );
  }
}
