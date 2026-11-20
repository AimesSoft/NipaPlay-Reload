import { randomUUID } from 'node:crypto';

const append = { surfaceOp: 'append' };
const text = (value) => ({ type: 'text', text: value });

export function validateHandover(turns) {
  if (!Array.isArray(turns) || Buffer.byteLength(JSON.stringify(turns)) > 16384) {
    throw new Error('Invalid conversation handover batch');
  }
  const seen = new Set();
  return turns.map((items) => {
    if (!Array.isArray(items) || !items.length) throw new Error('Invalid conversation turn');
    const pending = new Set();
    const segments = [];
    let step;
    const nextStep = () => {
      if (pending.size) throw new Error('Unpaired conversation tool call');
      step = { content: [], calls: [], results: [] };
      segments.push(step);
    };
    for (const item of items) {
      switch (item?.type) {
        case 'message': {
          const { role, content } = item;
          if (!['user', 'assistant'].includes(role) || !Array.isArray(content) || !content.length ||
              content.some((part) => part?.type !== (role === 'user' ? 'input_text' : 'output_text') || typeof part.text !== 'string')) {
            throw new Error('Invalid conversation message');
          }
          if (role === 'user') {
            if (pending.size) throw new Error('Unpaired conversation tool call');
            segments.push({ user: content.map((part) => text(part.text)) });
            step = undefined;
          } else {
            if (!step || step.calls.length) nextStep();
            step.content.push(...content.map((part) => text(part.text)));
          }
          break;
        }
        case 'function_call': {
          if (typeof item.call_id !== 'string' || !item.call_id || seen.has(item.call_id) ||
              typeof item.name !== 'string' || !item.name || typeof item.arguments !== 'string') {
            throw new Error('Invalid conversation tool call');
          }
          JSON.parse(item.arguments);
          if (!step || step.results.length) nextStep();
          seen.add(item.call_id);
          pending.add(item.call_id);
          const call = { id: item.call_id, name: item.name, arguments: item.arguments };
          step.calls.push(call);
          step.content.push({ type: 'tool-call', ...call });
          break;
        }
        case 'function_call_output':
          if (!pending.delete(item.call_id) || typeof item.output !== 'string') throw new Error('Invalid conversation tool result');
          step.results.push(item);
          break;
        default:
          throw new Error('Unsupported conversation item');
      }
    }
    if (pending.size) throw new Error('Unpaired conversation tool call');
    return segments;
  });
}

export function appendHandover(session, turns, provider, model) {
  const message = (role, content, source) => ({ role, id: randomUUID(), content, source });
  for (const [index, segments] of turns.entries()) {
    const turn = index + 1;
    let step = 0;
    session.append('turn/start', { turn });
    for (const segment of segments) {
      if (segment.user) {
        session.append('user/message', message('user', segment.user, { kind: 'user' }), append);
        continue;
      }
      step++;
      session.append('step/start', { turn, step });
      session.append('assistant/message', { turn, step, stream: [],
        message: message('assistant', segment.content, { kind: 'model', provider, model }) }, append);
      const calls = new Map();
      for (const { id, name, arguments: args } of segment.calls) {
        calls.set(id, session.append('tool/call', { turn, step, callId: id, name, arguments: args }).seq);
      }
      for (const result of segment.results) {
        const callId = result.call_id;
        session.append('tool/result', { turn, step, message: {
          ...message('tool', [text(result.output)], { kind: 'tool', callId }),
          toolCallId: callId, isError: result.failed === true,
        } }, { ...append, sourceEventSeqs: [calls.get(callId)] });
      }
      session.append('step/end', { turn, step });
    }
    session.append('turn/end', { turn, reason: { kind: 'completed' } });
  }
}
