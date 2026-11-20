import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { cp, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import { test } from 'node:test';

const plugin = 'fixture/plugin';

if (process.argv[2] === 'bridge-fixture') {
  const { apply } = await import(process.env.NIPA_TEST_BRIDGE);
  const listeners = new Map();
  let turn = 0;
  let route;
  const ctx = {
    on: (name, fn) => listeners.set(name, fn),
    get: () => undefined,
    effect: (fn) => fn(),
    inject: () => {},
    llm: {
      listProviders: () => [{ id: 'nipaplay' }, { id: plugin }],
      listModels: async () => [{ id: 'same-model' }],
    },
    agents: {
      get: (id) => id === 'thread' ? agent : undefined,
    },
  };
  const agent = {
    ctx: { install: (selection) => { route = selection; } },
    followup(message) {
      const provider = route?.current.provider ?? 'nipaplay';
      process.stdout.write(`${JSON.stringify({ provider })}\n`);
      listeners.get('agent/inbox/claimed')({ message, turn: ++turn });
    },
  };
  apply(ctx, { provider: 'nipaplay', model: 'same-model' });
} else {
  test('turn/start routes the same model ID through the selected DSH adapter', { timeout: 5000 }, async () => {
    const root = await mkdtemp(join(tmpdir(), 'dsh-model-route-'));
    const sdk = join(root, 'node_modules', '@deepseek-ai', 'dsh-agent');
    const fixture = join(root, 'fixture.mjs');
    let child;
    try {
      await mkdir(sdk, { recursive: true });
      await writeFile(join(sdk, 'package.json'), '{"main":"index.mjs"}');
      await writeFile(join(sdk, 'index.mjs'), 'export const installModelSelection = (ctx, selection) => ctx.install(selection);');
      await cp(new URL(import.meta.url), fixture);
      child = spawn(process.execPath, [fixture, 'bridge-fixture'], {
        env: {
          ...process.env,
          DSH_HOME: root,
          NIPA_TEST_BRIDGE: process.env.NIPA_TEST_BRIDGE ?? new URL(
            '../../assets/next/agent/dsh/nipa-app-server.mjs', import.meta.url,
          ).href,
        },
      });
      const exit = once(child, 'exit');
      let stderr = '';
      child.stderr.setEncoding('utf8').on('data', (chunk) => { stderr += chunk; });
      const lines = createInterface({ input: child.stdout })[Symbol.asyncIterator]();
      const send = (id, modelProvider) => child.stdin.write(`${JSON.stringify({
        id, method: 'turn/start', params: { threadId: 'thread', model: 'same-model', modelProvider,
          input: [{ type: 'text', text: 'fixture' }] },
      })}\n`);
      const read = async () => {
        const line = await lines.next();
        assert.equal(line.done, false, stderr);
        return JSON.parse(line.value);
      };
      try {
        send(1, plugin);
        assert.deepEqual(await read(), { provider: plugin });
        assert.equal((await read()).result.turn.status, 'inProgress');
        send(2, 'nipaplay');
        assert.deepEqual(await read(), { provider: 'nipaplay' });
        assert.equal((await read()).result.turn.status, 'inProgress');
      } finally {
        child.kill();
        await exit;
      }
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
}
