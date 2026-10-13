import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'media/media_service.dart';
import 'danmaku/service.dart';
import 'settings/registry.dart';
import 'mesh/runtime.dart';
import '../security/credential_vault.dart';
import 'capabilities/family_descriptions.dart';

final class AppCapabilities implements Capability {
  AppCapabilities(
      {required this.host,
      required this.catalog,
      required this.media,
      required this.danmaku,
      required this.settings,
      required this.vault,
      required this.programEnabled,
      this.subtitleProbeReady});
  final String host;
  final Iterable<ActionSpec> Function() catalog;
  final MediaService media;
  final DanmakuService danmaku;
  final SettingsRegistry settings;
  final CredentialVault vault;
  final bool Function() programEnabled;
  final bool Function()? subtitleProbeReady;
  Future<(bool, String?)> _credentialState(CredentialRef ref) async {
    try {
      final secret = await vault.read(ref);
      return secret != null && secret.isNotEmpty
          ? (true, null)
          : (false, 'Host vault credential is missing.');
    } on StateError {
      return (
        false,
        'Host vault is unavailable; inspect credentials.status or host vault permissions.'
      );
    }
  }

  Future<JsonMap> facts() async {
    final ddp = await _credentialState(
        const CredentialRef('preferences', 'dandanplay_token'));
    final tmdb =
        await _credentialState(const CredentialRef('metadata', 'tmdb'));
    JsonMap provider(String id, bool ready, CredentialRef? ref,
            [String? reason]) =>
        {
          'id': id,
          'supported': media.providers.containsKey(id),
          'available': media.providers.containsKey(id) && ready,
          'reason': !media.providers.containsKey(id)
              ? 'Provider is not installed in this host.'
              : ready
                  ? null
                  : reason,
          'credentialRef': ref?.toJson(),
          'requiredHostSetup': ref == null
              ? <String>[]
              : [
                  'Enroll ${ref.namespace}/${ref.key} in the host vault; no Action accepts this secret.'
                ],
        };
    final providers = [
      provider('bangumi', true, null),
      provider('dandanplay', ddp.$1,
          const CredentialRef('preferences', 'dandanplay_token'), ddp.$2),
      provider(
          'tmdb', tmdb.$1, const CredentialRef('metadata', 'tmdb'), tmdb.$2)
    ];
    final specs = catalog().toList();
    JsonMap feature(
            String id, bool supported, String reason, List<String> setup) =>
        {
          'id': id,
          'supported': supported,
          'reason': supported ? null : reason,
          'requiredHostSetup': supported ? <String>[] : setup
        };
    final gui = host == 'gui';
    return {
      'host': host,
      'platform': Platform.operatingSystem,
      'families': familyFacts,
      'network': {
        'systemProxySettings': gui,
        'processProxyEnvironment': true,
        'requiredHostSetup': gui
            ? <String>[]
            : [
                'Provide the host network/proxy environment needed to reach providers; GUI system proxy settings are not inherited. Keep loopback in NO_PROXY.'
              ]
      },
      'readinessScope':
          'hostPrerequisites; network availability is observed by each request',
      'features': [
        feature('online.metadata', media.providers.isNotEmpty,
            'No metadata provider.', []),
        {
          ...feature(
              'online.hashMatch',
              media.providers.containsKey('dandanplay'),
              'Dandanplay provider is absent.', []),
          'available': media.providers.containsKey('dandanplay') && ddp.$1,
          'reason': media.providers.containsKey('dandanplay')
              ? ddp.$2
              : 'Dandanplay provider is absent.',
          'requiredHostSetup': [
            'Enroll preferences/dandanplay_token in host vault.'
          ]
        },
        {
          ...feature(
              'online.danmaku',
              danmaku.sources.containsKey('dandanplay'),
              'Dandanplay source is absent.', []),
          'available': danmaku.sources.containsKey('dandanplay') && ddp.$1,
          'reason': danmaku.sources.containsKey('dandanplay')
              ? ddp.$2
              : 'Dandanplay source is absent.',
          'requiredHostSetup': [
            'Enroll preferences/dandanplay_token in host vault.'
          ]
        },
        for (final family in [
          'playback',
          'window',
          'accounts',
          'discover',
          'media.sources',
          'sync',
          'backup',
          'plugins',
          'diagnostics'
        ])
          feature(
              family,
              specs.any((s) => s.id.startsWith('$family.')),
              'This host has no ${gui ? 'mounted implementation' : 'Classic service/player/widget host'} for $family.',
              [
                'Use a GUI host for $family; headless media metadata and danmaku providers do not need it.'
              ]),
        feature(
            'classic.history',
            gui,
            'Headless stores Next facts without a Classic history database.',
            ['Use a GUI host for Classic history.']),
        {
          'id': 'subtitle.embeddedProbe',
          'supported': true,
          'available': subtitleProbeReady?.call() ?? gui,
          'reason': (subtitleProbeReady?.call() ?? gui)
              ? null
              : 'Headless ffprobe is not configured.',
          'requiredHostSetup':
              gui ? <String>[] : ['Provide the host ffprobe executable.']
        },
        {
          ...feature(
              'program.execution',
              specs.any((s) => s.id == 'program.run'),
              'Program runtime is absent.', []),
          'available': programEnabled(),
          'reason':
              programEnabled() ? null : 'Host program permission is disabled.',
          'requiredHostSetup': [
            'Set enabled in this device\'s program.json and restart.'
          ]
        },
      ],
      'providers': providers,
      'sources': [
        for (final source in danmaku.sources.values)
          {
            ...source.describe.toJson(),
            'available': source.describe.id != 'dandanplay' || ddp.$1,
            'reason': source.describe.id == 'dandanplay' ? ddp.$2 : null,
            'requiredHostSetup': source.describe.id == 'dandanplay'
                ? ['Enroll preferences/dandanplay_token in host vault.']
                : <String>[],
          }
      ],
      'settingsKeys': [
        for (final entry in settings.entries)
          if (entry.visible()) entry.key
      ],
      'semantics': gui
          ? {'history': 'Classic and Next share projected matches'}
          : {
              'media.library.roots.remove':
                  'unregisterOnly; preserves indexed facts and files',
              'download.import':
                  'indexVerifiedFiles; no automatic identification',
              'mediaReadOnlyScope': ['indexing', 'downloadDestination'],
              'media.mesh_files':
                  'processPermissions; delete/overwrite use NeedsDecision',
              'danmaku': 'persistent preparation; no player mounting',
            },
      'actions': [
        for (final spec in specs)
          {
            'id': spec.id,
            'registered': true,
            'effect': spec.effect.name,
            'available': spec.id == 'media.hash.match'
                ? media.providers.containsKey('dandanplay') && ddp.$1
                : spec.id == 'program.run' || spec.id == 'program.repository.receive'
                    ? programEnabled()
                    : spec.id == 'danmaku.align'
                        ? false
                        : true,
            'availabilityScope': spec.id.startsWith('media.metadata.') ||
                    spec.id.startsWith('danmaku.')
                ? 'provider/source and input dependent; see providers/sources'
                : 'hostPrerequisites',
            'requiredHostSetup': spec.id == 'media.hash.match'
                ? ['Enroll preferences/dandanplay_token in host vault.']
                : spec.id == 'program.run' || spec.id == 'program.repository.receive'
                    ? ['Enable this host\'s program.json and restart.']
                    : <String>[],
            'remoteCallable': meshActionAllowed(spec.id),
            'reason': meshActionRestriction(spec.id),
            'availabilityReason': spec.id == 'media.hash.match'
                ? ddp.$2
                : (spec.id == 'program.run' || spec.id == 'program.repository.receive') && !programEnabled()
                    ? 'Host program permission is disabled.'
                    : spec.id == 'danmaku.align'
                        ? 'Retired; only existing requestId recovery is supported.'
                        : null,
            'requiredUserPresence': spec.id == 'accounts.login' ||
                spec.id == 'media.sources.login' ||
                spec.id == 'credentials.retry' ||
                spec.id == 'playback.authorize_directory',
            if (spec.id == 'accounts.login' || spec.id == 'media.sources.login')
              'userPresenceCondition':
                  'when no voluntarily supplied credential is present',
            if (!gui && spec.id.startsWith('danmaku.'))
              'inputConstraints':
                  'Use entityId/path; current playback is unavailable. Exports must remain under data/exports.',
            if (spec.id.startsWith('danmaku.align'))
              'lifecycle': 'legacyRecovery',
            if (spec.id.startsWith('danmaku.align'))
              'replacement': ['danmaku.analyze_alignment', 'danmaku.update'],
          }
      ],
    };
  }

  @override
  List<Action> get actions => [_AppAction(this)];
}

final class _Value implements JsonEncodable {
  const _Value(this.json);
  final JsonMap json;
  @override
  JsonMap toJson() => json;
}

final class _AppAction extends Action<_Value, _Value> {
  const _AppAction(this.host);
  final AppCapabilities host;
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'app.capabilities',
      title: 'Read host capability facts',
      description: appFamilyDescription,
      effect: Effect.read,
      input: ObjectSchema({}),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  _Value decodeInput(JsonMap json) => _Value(json);
  @override
  Future<Outcome<_Value>> run(_Value input, Invocation invocation) async =>
      Completed(_Value(await host.facts()));
}
