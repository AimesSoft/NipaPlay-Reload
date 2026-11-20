import 'dart:io';

import 'package:path/path.dart' as p;

const _modules = {
  'webserver': 'host-webserver',
  'connection': 'client-connection',
  'modules': 'client-modules',
  'cordis-client-runner': 'cordis-client-runner',
  'ui-renderer': 'client-ui-renderer',
  'api-remotes': 'api-remotes',
  'ui-theme': 'client-ui-theme',
  'locale': 'client-locale',
  'ui-settings': 'client-ui-settings',
  'shortcuts': 'client-shortcuts',
  'ui-settings-plugins': 'client-ui-settings-plugins',
  'ui-settings-plugin-inventory': 'client-ui-settings-plugin-inventory',
  'ui-agent-preset': 'client-ui-agent-preset',
  'session-controller': 'api-session-controller',
  'file-upload': 'client-file-upload',
  'ui-conversation': 'client-ui-conversation',
  'ui-layout': 'client-ui-layout',
  'ui-session': 'client-ui-session',
  'ui-workspace': 'client-ui-workspace',
  'workspace-controller': 'api-workspace-controller',
  'ui-sidebar': 'client-ui-sidebar',
  'ui-plugin-manager': 'client-ui-plugin-manager',
  'plugin-inventory': 'host-plugin-inventory',
  'settings-controller': 'api-settings-controller',
  'workspace': 'workspace',
  'ui-settings-general': 'client-ui-settings-general',
  'frontend-static': 'host-frontend-static',
};

Future<List<Map<String, Object?>>> dshWebRows(String bin) async {
  final scope = File(bin).parent.parent.parent.path;
  final index = p.join(scope, 'dsh-web-frontend', 'dist', 'index.html');
  final rows = [
    for (final entry in _modules.entries)
      <String, Object?>{
        'id': entry.key,
        'name': p.join(scope, 'dsh-${entry.value}', 'lib', 'index.js'),
        if (entry.key == 'webserver')
          'config': {'host': '127.0.0.1', 'port': 0},
        if (entry.key == 'frontend-static') 'config': {'distIndex': index},
      },
  ];
  for (final path in [index, ...rows.map((row) => row['name'] as String)]) {
    if (!await File(path).exists()) throw StateError('DSH Web 安装不完整。');
  }
  return rows;
}
