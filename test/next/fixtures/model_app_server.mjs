import { createInterface } from 'node:readline';

const config = JSON.parse(process.env.NIPA_TEST_MODEL_CONFIG);
const send = (message) => console.log(JSON.stringify(message));
let threads = 0;
let turns = 0;
for await (const line of createInterface({ input: process.stdin })) {
  const { id, method, params } = JSON.parse(line);
  if (id == null) continue;
  let result;
  switch (method) {
    case 'initialize':
    case 'thread/name/set':
      result = {};
      break;
    case 'hooks/list':
      result = { data: [] };
      break;
    case 'config/read':
      result = { config };
      break;
    case 'account/read':
      result = { account: process.env.NIPA_TEST_ACCOUNT === 'chatgpt' ? { type: 'chatgpt' } : null };
      break;
    case 'model/list':
      if (process.env.NIPA_TEST_NO_CATALOG === '1') {
        send({ id, error: { code: -32600, message: 'Unexpected model/list' } });
        continue;
      }
      result = { data: [{ model: 'catalog-model', isDefault: true, defaultReasoningEffort: 'low' }] };
      break;
    case 'thread/start':
    case 'thread/resume':
      result = {
        thread: { id: params.threadId ?? `thread-${process.pid}-${++threads}`, turns: [] },
        model: config.model ?? 'catalog-model', modelProvider: config.model_provider ?? 'openai',
      };
      break;
    case 'turn/start': {
      const turn = { id: `turn-${++turns}`, status: 'completed', items: [] };
      send({ method: 'turn/completed', params: { threadId: params.threadId, turn } });
      result = { turn, wire: params };
      break;
    }
    default:
      send({ id, error: { code: -32601, message: method } });
      continue;
  }
  send({ id, result });
}
