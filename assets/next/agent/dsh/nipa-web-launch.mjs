import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [cli, pnpm, data, registry] = process.argv.splice(2, 4);
process.argv[1] = cli;
const { runCli } = await import(pathToFileURL(cli).href);
await runCli({
  packageManager: {
    command: process.execPath,
    args: [pnpm],
    env: {
      npm_config_registry: registry,
      npm_config_cache: join(data, 'cache'),
      npm_config_cache_dir: join(data, 'cache'),
      npm_config_store_dir: join(data, 'store'),
      npm_config_state_dir: join(data, 'state'),
      npm_config_manage_package_manager_versions: 'false',
      npm_config_update_notifier: 'false',
    },
  },
});
