import { randomUUID } from 'node:crypto';
import { readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { zstdCompressSync, zstdDecompressSync } from 'node:zlib';

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
    // Another runtime may reuse short call ids across turns; keep them unique.
    const renamed = new Map();
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
          if (typeof item.call_id !== 'string' || !item.call_id || renamed.has(item.call_id) ||
              typeof item.name !== 'string' || !item.name || typeof item.arguments !== 'string') {
            throw new Error('Invalid conversation tool call');
          }
          let args = item.arguments;
          try {
            JSON.parse(args);
          } catch {
            // Keep a call whose arguments were not valid JSON as recorded text.
            args = JSON.stringify({ arguments: args });
          }
          let id = item.call_id;
          for (let n = 2; seen.has(id); n++) id = `${item.call_id}~${n}`;
          renamed.set(item.call_id, id);
          if (!step || step.results.length) nextStep();
          seen.add(id);
          pending.add(id);
          const call = { id, name: item.name, arguments: args };
          step.calls.push(call);
          step.content.push({ type: 'tool-call', ...call });
          break;
        }
        case 'function_call_output':
          if (!pending.delete(renamed.get(item.call_id)) || typeof item.output !== 'string') {
            throw new Error('Invalid conversation tool result');
          }
          step.results.push({ ...item, call_id: renamed.get(item.call_id) });
          break;
        default:
          throw new Error('Unsupported conversation item');
      }
    }
    if (pending.size) throw new Error('Unpaired conversation tool call');
    return segments;
  });
}

// DSH's first system prompt, even empty, is surface node 0: its first step
// replaces it or appends the rendered prompt after the history. History
// ahead of it makes the stored log unreadable ("system/message requires a
// protected first surface head"). Step 1 of turn 1 holds it.
function systemHead() {
  return [
    ['step/start', { turn: 1, step: 1 }],
    ['system/message', { turn: 1, step: 1, message: { role: 'system', id: randomUUID(), content: [],
      source: { kind: 'system-prompt' } } }, append],
    ['step/end', { turn: 1, step: 1 }],
  ];
}

export function appendHandover(session, turns, provider, model) {
  const message = (role, content, source) => ({ role, id: randomUUID(), content, source });
  for (const [index, segments] of turns.entries()) {
    const turn = index + 1;
    let step = 0;
    session.append('turn/start', { turn });
    if (index === 0) {
      for (const [type, data, intent] of systemHead()) session.append(type, data, intent);
      step = 1;
    }
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

const surfaceTypes = new Set(['system/message', 'developer/message', 'user/message', 'assistant/message', 'tool/result']);

/**
 * The events of a log an earlier build handed over without the system head
 * (handed-over history first, the runtime's first system prompt after it),
 * with the head put where a handover now writes it. undefined for any other
 * log. Events are dense (seq is the index); the three inserted events move
 * every later seq and every reference to one (fields named *Seq / *Seqs),
 * and the steps of turn 1 after the head.
 */
export function repairHandoverHead(events) {
  const first = events.findIndex((event) => surfaceTypes.has(event.type));
  if (first < 0 || events[first].type === 'system/message' ||
      !events.slice(first).some((event) => event.type === 'system/message')) return undefined;
  const open = events.findIndex((event) => event.type === 'turn/start');
  if (open < 0 || open > first || events[open].data?.turn !== 1 ||
      events.some((event, index) => event.seq !== index)) return undefined;
  const at = open + 1;
  const count = systemHead().length;
  const moved = (seq) => (Number.isSafeInteger(seq) && seq >= at ? seq + count : seq);
  const remap = (value) => {
    if (Array.isArray(value)) return value.map(remap);
    if (value === null || typeof value !== 'object') return value;
    return Object.fromEntries(Object.entries(value).map(([key, field]) => [key,
      /[a-z]Seq$/.test(key) ? moved(field)
        : /[a-z]Seqs$/.test(key) && Array.isArray(field) ? field.map(moved)
          : remap(field)]));
  };
  const { time } = events[open];
  const head = systemHead().map(([type, data, intent], index) => ({
    type, seq: at + index, time, data, ...(intent ?? {}),
  }));
  let firstTurn = true;
  const rest = events.slice(at).map((event) => {
    const next = remap({ ...event, seq: event.seq + count });
    if (firstTurn && next.data?.turn === 1 && Number.isSafeInteger(next.data.step)) {
      next.data = { ...next.data, step: next.data.step + 1 };
    }
    if (event.type === 'turn/end' && event.data?.turn === 1) firstTurn = false;
    return next;
  });
  return [...events.slice(0, at), ...head, ...rest];
}

/**
 * Rewrites the stored log at [path] (DSH's zstd layout: the header in its
 * own frame, then the events) when [repairHandoverHead] applies, and drops
 * the session's projection cache, which counts the old seqs. Returns how to
 * put the original back, or undefined when the log is not one to repair.
 */
export async function repairHandoverLog(path, { home, id }) {
  const original = await readFile(path);
  const [header, ...events] = zstdDecompressSync(original).toString('utf8')
    .split('\n').filter((line) => line.length > 0).map((line) => JSON.parse(line));
  const repaired = repairHandoverHead(events);
  if (!repaired) return undefined;
  const frame = (lines) => zstdCompressSync(Buffer.from(lines.map((line) => `${JSON.stringify(line)}\n`).join('')));
  const staging = join(dirname(path), 'session.repair.tmp');
  // As private as the log it replaces.
  const { mode } = await stat(path);
  await writeFile(staging, Buffer.concat([frame([header]), frame(repaired)]), { mode: mode & 0o777 });
  await rename(staging, path);
  await rm(join(home, 'storages', 'session_projcache', 'sessions', `${id}.json`), { force: true });
  return () => writeFile(path, original);
}
