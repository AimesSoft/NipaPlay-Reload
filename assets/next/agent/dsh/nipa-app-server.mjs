// NipaPlay's embedded chat host speaks a subset of the Codex app-server
// protocol (JSON-RPC lines on stdio). This DeepSeek Harness (DSH) plugin
// serves that subset from DSH's own agents, sessions and subagents, so the
// Dart host, followups, helpers and session store keep their semantics when
// Nipa runs on DSH instead of Codex.
//
// It takes the place of DSH's SDK JSON-RPC server in the composition. Nothing
// here re-implements the agent loop: turns, tools, steering, cancellation,
// compaction, persistence and subagent delivery are DSH's. This file names
// DSH facts the way the host already understands them.
import { randomUUID } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';

export const name = 'nipa-app-server';
export const inject = ['agents', 'sessions'];

/** Message sources that are context, not something said in the conversation. */
const HIDDEN_SOURCES = new Set(['runtime-context', 'agent-instructions', 'compact-checkpoint', 'tool-registry']);
/** How long a subagent's turn end waits for DSH to hand its result to the parent. */
const SETTLEMENT_HOLD_MS = 3000;
const CHAT_KEY = Symbol.for('nipaplay.dsh.chatFor');

const seconds = (ms) => (ms === undefined || ms === null ? null : Math.floor(ms / 1000));
const turnIdOf = (threadId, turn) => `${threadId}-t${turn}`;
const blockItemId = (turnId, step, attempt, index) => `${turnId}-s${step}-a${attempt}-b${index}`;

function rpcError(code, message, data) {
  const error = new Error(message);
  error.rpc = { code, message, ...(data === undefined ? {} : { data }) };
  return error;
}

function parseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

function userMessage(input) {
  const content = [];
  for (const part of input ?? []) {
    if (part?.type === 'text' && typeof part.text === 'string') content.push({ type: 'text', text: part.text });
  }
  if (content.length === 0) throw rpcError(-32602, 'Input must contain text.');
  return Object.freeze({ role: 'user', id: randomUUID(), content, source: { kind: 'user' } });
}

function textOf(content) {
  return (content ?? []).filter((block) => block?.type === 'text').map((block) => block.text).join('\n');
}

/** The `[exit code: N]` / `[killed by signal: X]` markers DSH's bash tool appends. */
function exitStatus(text) {
  const signal = /\n?\[killed by signal: ([^\]\n]+)\]$/.exec(text);
  if (signal) return { body: text.slice(0, signal.index), exitCode: null };
  const exit = /\n?\[exit code: (\d+)\]$/.exec(text);
  if (exit) return { body: text.slice(0, exit.index), exitCode: Number(exit[1]) };
  return { body: text, exitCode: 0 };
}

/**
 * Codex's turn-error vocabulary for a DSH LlmFailure. NipaPlay redelivers a
 * followup only after a provider hiccup, which it recognises by HTTP status or
 * by these Codex names; DSH's own message and code are kept.
 */
function turnError(failure) {
  if (!failure) return null;
  const message = String(failure.message ?? failure);
  const parsed = /\((\d{3})\)/.exec(message);
  const status = failure.status ?? (parsed ? Number(parsed[1]) : undefined);
  const code = String(failure.code ?? 'UNKNOWN');
  let info = 'other';
  if (code === 'QUOTA' || code === 'ACCOUNT_QUOTA') {
    info = 'usageLimitExceeded';
  } else if (code === 'RATE_LIMIT' || status === 429) {
    info = { responseTooManyFailedAttempts: { httpStatusCode: status ?? 429 } };
  } else if (code === 'SERVER' || (status !== undefined && status >= 500)) {
    info = { responseTooManyFailedAttempts: { httpStatusCode: status ?? null } };
  } else if (['TRANSPORT', 'TIMEOUT', 'LLM_STREAM_IDLE_TIMEOUT', 'EMPTY_RESPONSE'].includes(code)) {
    info = { responseStreamDisconnected: { httpStatusCode: status ?? null } };
  } else if (code === 'CONTEXT_WINDOW_EXCEEDED') {
    info = 'contextWindowExceeded';
  } else if (code === 'INVALID_CREDENTIAL' || code === 'MISSING_CREDENTIAL') {
    info = 'unauthorized';
  } else if (code === 'INVALID_REQUEST') {
    info = 'badRequest';
  }
  return { message, codexErrorInfo: info, additionalDetails: code };
}

function turnStatus(reason) {
  switch (reason?.kind) {
    case 'aborted':
    case 'interrupted':
    case 'forked':
      return 'interrupted';
    case 'error':
      return 'failed';
    default:
      return 'completed';
  }
}

/** The Codex thread item for one DSH tool call, before its result. */
function toolItem(threadId, call, cwd) {
  const args = parseJson(call.arguments) ?? {};
  const id = String(call.callId);
  const collab = (tool, receivers, prompt) => ({
    type: 'collabAgentToolCall', id, tool, status: 'inProgress', senderThreadId: threadId, receiverThreadIds: receivers,
    prompt: prompt ?? null, model: null, reasoningEffort: null, agentsStates: {},
  });
  switch (call.name) {
    case 'bash':
      return {
        type: 'commandExecution', id, command: String(args.command ?? ''), commandActions: [], cwd: args.workdir ?? cwd,
        status: 'inProgress', aggregatedOutput: null, exitCode: null, durationMs: null, processId: null,
      };
    case 'subagent':
    case 'subagent_fork':
      return collab('spawnAgent', [], args.prompt);
    case 'send_message':
      return collab('sendInput', args.agent_id ? [String(args.agent_id)] : [], args.message);
    case 'web_search': {
      const queries = Array.isArray(args.queries) ? args.queries.map(String) : args.query ? [String(args.query)] : [];
      return { type: 'webSearch', id, query: queries[0] ?? '', action: { type: 'search', query: queries[0] ?? null, queries } };
    }
    case 'web_fetch':
      return { type: 'webSearch', id, query: String(args.url ?? ''), action: { type: 'openPage', url: args.url ?? null } };
    default:
      return {
        type: 'dynamicToolCall', id, tool: String(call.name), namespace: null, arguments: args, status: 'inProgress',
        contentItems: null, success: null, durationMs: null,
      };
  }
}

/** The same item once DSH recorded the call's result. */
function completeToolItem(item, result, startedAt, endedAt) {
  const text = textOf(result.message?.content);
  const failed = result.message?.isError === true;
  const durationMs = startedAt !== undefined && endedAt !== undefined ? Math.max(0, endedAt - startedAt) : null;
  switch (item.type) {
    case 'commandExecution': {
      const status = exitStatus(text);
      const exitCode = failed && status.exitCode === 0 ? null : status.exitCode;
      return { ...item, aggregatedOutput: status.body, exitCode, status: exitCode === 0 ? 'completed' : 'failed', durationMs };
    }
    case 'collabAgentToolCall': {
      if (item.tool !== 'spawnAgent') return { ...item, status: failed ? 'failed' : 'completed' };
      const child = failed ? undefined : /started subagent (\S+)/.exec(text)?.[1];
      return {
        ...item, status: child ? 'completed' : 'failed', receiverThreadIds: child ? [child] : [],
        agentsStates: child ? { [child]: { status: 'pendingInit', message: null } } : {},
      };
    }
    case 'webSearch':
      return item;
    default:
      return {
        ...item, status: failed ? 'failed' : 'completed', success: !failed,
        contentItems: text ? [{ type: 'inputText', text }] : [], durationMs,
      };
  }
}

/**
 * What a subagent delivered into this conversation. DSH sends a settled
 * child's closing reply to its parent as a notice; the host knows that as a
 * completed `wait`, whose state carries the child's final reply.
 */
function deliveredItem(threadId, message) {
  const source = message.source ?? {};
  const sender = source.senderSessionId === undefined ? undefined : String(source.senderSessionId);
  if (!sender) return undefined;
  if (source.kind === 'subagent-settled') {
    const blocks = (message.content ?? []).filter((block) => block?.type === 'text');
    const marker = blocks.findIndex((block) => block.text === 'Its closing message:');
    const closing = marker < 0 ? [] : blocks.slice(marker + 1).map((block) => block.text);
    // DSH's settlement sentences: "… finished and will …" / "… finished. …",
    // "… was stopped before it finished.", otherwise failed, declined or cut off.
    const summary = String(source.summary ?? blocks[0]?.text ?? '');
    const status = / finished( and |\. )/.test(summary) ? 'completed'
      : / was stopped /.test(summary) ? 'interrupted' : 'errored';
    return {
      type: 'collabAgentToolCall', id: String(message.id), tool: 'wait', status: 'completed', senderThreadId: threadId,
      receiverThreadIds: [sender], prompt: null, model: null, reasoningEffort: null,
      agentsStates: { [sender]: { status, message: closing.length ? closing[closing.length - 1] : null } },
    };
  }
  if (source.kind === 'agent-message') {
    return {
      type: 'collabAgentToolCall', id: String(message.id), tool: 'sendInput', status: 'completed', senderThreadId: sender,
      receiverThreadIds: [threadId], prompt: textOf(message.content), model: null, reasoningEffort: null, agentsStates: {},
    };
  }
  return undefined;
}

function userItem(message) {
  return {
    type: 'userMessage', id: String(message.id),
    content: (message.content ?? []).filter((block) => block?.type === 'text')
      .map((block) => ({ type: 'text', text: block.text, text_elements: [] })),
  };
}

/** Codex turns from one DSH session log; ids match the live notifications. */
function historyTurns(threadId, events, cwd, liveOpen) {
  const turns = [];
  const calls = new Map();
  const attempts = new Map();
  let current;
  for (const event of events) {
    const data = event.data ?? {};
    switch (event.type) {
      case 'turn/start':
        current = {
          id: turnIdOf(threadId, data.turn), items: [], status: 'inProgress', error: null,
          startedAt: seconds(event.time), completedAt: null, durationMs: null, startedAtMs: event.time,
        };
        turns.push(current);
        break;
      case 'user/message': {
        if (!current) break;
        if (data.source?.kind === 'user') current.items.push(userItem(data));
        else {
          const item = deliveredItem(threadId, data);
          if (item) current.items.push(item);
        }
        break;
      }
      case 'assistant/attempt': {
        const key = `${data.turn}:${data.step}`;
        attempts.set(key, (attempts.get(key) ?? 0) + 1);
        break;
      }
      case 'assistant/message': {
        if (!current) break;
        const key = `${data.turn}:${data.step}`;
        const attempt = (attempts.get(key) ?? 0) + 1;
        attempts.set(key, attempt);
        (data.message?.content ?? []).forEach((block, index) => {
          const id = blockItemId(current.id, data.step, attempt, index);
          if (block.type === 'text' && block.text) current.items.push({ type: 'agentMessage', id, text: block.text, phase: null });
          if (block.type === 'reasoning' && block.text) current.items.push({ type: 'reasoning', id, summary: [], content: [block.text] });
        });
        break;
      }
      case 'tool/call': {
        if (!current) break;
        const item = toolItem(threadId, data, cwd);
        calls.set(String(data.callId), { item, index: current.items.length, turn: current, startedAt: event.time });
        current.items.push(item);
        break;
      }
      case 'tool/result': {
        const callId = String(data.message?.toolCallId ?? data.message?.source?.callId ?? '');
        const call = calls.get(callId);
        if (!call) break;
        call.turn.items[call.index] = completeToolItem(call.item, data, call.startedAt, event.time);
        calls.delete(callId);
        break;
      }
      case 'turn/end':
        if (!current) break;
        current.status = turnStatus(data.reason);
        current.error = data.reason?.kind === 'error' ? turnError(data.reason.error) : null;
        current.completedAt = seconds(event.time);
        current.durationMs = event.time - current.startedAtMs;
        current = undefined;
        break;
      default:
        break;
    }
  }
  // A log whose last turn never ended belongs to a process that stopped.
  if (current && !liveOpen) current.status = 'interrupted';
  for (const call of calls.values()) {
    if (call.turn.status !== 'inProgress') call.turn.items[call.index] = { ...call.item, status: 'failed' };
  }
  return turns.map(({ startedAtMs, ...turn }) => turn);
}

/** Thread names, previews and host-assigned shell identities; DSH keeps the rest. */
class ThreadMeta {
  constructor(file) {
    this.file = file;
    this.rows = {};
    this.timer = undefined;
    if (existsSync(file)) {
      const parsed = parseJson(readFileSync(file, 'utf8'));
      if (parsed && typeof parsed.threads === 'object') this.rows = parsed.threads;
    }
  }

  get(id) {
    return this.rows[id];
  }

  update(id, fields) {
    this.rows[id] = { ...(this.rows[id] ?? {}), ...fields };
    this.timer ??= setTimeout(() => this.flush(), 50);
    return this.rows[id];
  }

  flush() {
    clearTimeout(this.timer);
    this.timer = undefined;
    mkdirSync(dirname(this.file), { recursive: true });
    const staging = `${this.file}.pending`;
    writeFileSync(staging, JSON.stringify({ version: 1, threads: this.rows }));
    renameSync(staging, this.file);
  }
}

/** JSON-RPC lines on stdin/stdout. Stdout carries protocol frames only. */
class Wire {
  constructor(onMessage) {
    this.onMessage = onMessage;
    this.buffer = '';
    this.nextId = 0;
    this.pending = new Map();
    this.closed = false;
    this.input = (chunk) => {
      this.buffer += chunk;
      let newline;
      while ((newline = this.buffer.indexOf('\n')) >= 0) {
        const line = this.buffer.slice(0, newline).trim();
        this.buffer = this.buffer.slice(newline + 1);
        const message = line ? parseJson(line) : undefined;
        if (!message || typeof message !== 'object') continue;
        if (message.method === undefined && this.pending.has(message.id)) {
          const waiter = this.pending.get(message.id);
          this.pending.delete(message.id);
          if (message.error) waiter.reject(Object.assign(new Error(message.error.message ?? 'request failed'), { rpc: message.error }));
          else waiter.resolve(message.result);
          continue;
        }
        this.onMessage(message);
      }
    };
  }

  start() {
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', this.input);
  }

  close() {
    this.closed = true;
    process.stdin.off('data', this.input);
    for (const waiter of this.pending.values()) waiter.reject(new Error('NipaPlay disconnected'));
    this.pending.clear();
  }

  send(message) {
    if (!this.closed) process.stdout.write(`${JSON.stringify(message)}\n`);
  }

  notify(method, params) {
    this.send({ method, params });
  }

  request(method, params, signal) {
    const id = `dsh-${++this.nextId}`;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      signal?.addEventListener('abort', () => {
        if (this.pending.delete(id)) reject(signal.reason ?? new Error('aborted'));
      }, { once: true });
      this.send({ id, method, params });
    });
  }
}

export function apply(ctx, config = {}) {
  const provider = String(config.provider ?? 'nipaplay');
  const model = String(config.model ?? '');
  const agentOptions = {
    provider, model,
    ...(config.reasoningEffort ? { reasoningEffort: config.reasoningEffort } : {}),
    ...(config.maxTokens ? { maxTokens: config.maxTokens } : {}),
  };
  const defaultCwd = config.cwd ?? process.cwd();
  const defaultChat = process.env.NIPAPLAY_CHAT ?? '';
  const home = process.env.DSH_HOME ?? join(process.env.HOME ?? '.', '.dsh');
  const meta = new ThreadMeta(join(home, 'nipaplay', 'threads.json'));
  const version = String(config.dshVersion ?? 'unknown');

  /** Root agents this host created or resumed; DSH's subagent service owns its children. */
  const handles = new Map();
  const opening = new Map();
  const live = new Map();
  const claims = new Map();
  const holds = new Map();
  const activations = new Set();
  const jobCalls = new Map();
  let wire;

  const liveFor = (id) => {
    let state = live.get(id);
    if (!state) {
      state = { openTurn: undefined, turnStartedAt: new Map(), streams: new Map(), attempts: new Map(), calls: new Map() };
      live.set(id, state);
    }
    return state;
  };
  const currentTurnId = (id) => {
    const turn = live.get(id)?.openTurn;
    return turn === undefined ? null : turnIdOf(id, turn);
  };
  const realCwd = (path) => {
    try {
      return realpathSync(path);
    } catch {
      return path;
    }
  };

  /** NIPAPLAY_CHAT for one session's shells: the host's choice, or a subagent's own identity. */
  const chatFor = (sessionId) => {
    if (!sessionId) return defaultChat;
    const id = String(sessionId);
    const row = meta.get(id);
    if (row?.chat) return row.chat;
    if (row?.parentThreadId || ctx.sessions.get(id)?.header?.parentSession !== undefined) return `native-${id}`;
    return defaultChat;
  };
  globalThis[CHAT_KEY] = chatFor;

  const notify = (method, params) => wire?.notify(method, params);
  const itemStarted = (threadId, turnId, item) => notify('item/started', { threadId, turnId, item, startedAtMs: Date.now() });
  const itemCompleted = (threadId, turnId, item) => notify('item/completed', { threadId, turnId, item, completedAtMs: Date.now() });

  function threadObject(id, header, turns) {
    const row = meta.get(id) ?? {};
    const parent = row.parentThreadId ?? (header?.parentSession !== undefined ? String(header.parentSession) : null);
    const agent = ctx.agents.get(id);
    const createdAt = row.createdAt ?? header?.createdAt ?? Date.now();
    return {
      id, sessionId: id, preview: row.preview ?? '', ephemeral: false, modelProvider: provider,
      createdAt: seconds(createdAt), updatedAt: seconds(row.updatedAt ?? createdAt),
      status: !agent ? { type: 'notLoaded' } : agent.status === 'running' ? { type: 'active', activeFlags: [] } : { type: 'idle' },
      path: null, cwd: header?.cwd ?? row.cwd ?? defaultCwd, cliVersion: `dsh-${version}`,
      source: parent ? { subAgent: { thread_spawn: { parent_thread_id: parent, depth: header?.delegationDepth ?? 1 } } } : 'appServer',
      agentNickname: null, agentRole: null, gitInfo: null, name: row.name ?? null, parentThreadId: parent, turns: turns ?? [],
    };
  }

  async function readEvents(id) {
    const session = ctx.sessions.get(id);
    if (session) return { header: session.header, events: session.snapshotEvents(), isLive: true };
    const persistence = ctx.get('sessionPersistence');
    const snapshot = await persistence?.stat(id);
    if (!snapshot) throw rpcError(-32600, `thread not found: ${id}`);
    const handle = await persistence.open(id, 'read');
    try {
      return { header: snapshot.header, events: (await handle.read()).events, isLive: false };
    } finally {
      await handle.close();
    }
  }

  async function threadWithHistory(id, includeTurns = true) {
    const { header, events, isLive } = await readEvents(id);
    const turns = includeTurns ? historyTurns(id, events, header?.cwd ?? defaultCwd, isLive && ctx.agents.get(id) !== undefined) : [];
    return threadObject(id, header, turns);
  }

  async function ensureAgent(id) {
    const existing = ctx.agents.get(id);
    if (existing) return existing;
    if (!opening.has(id)) {
      const task = (async () => {
        const persistence = ctx.get('sessionPersistence');
        if (!(await persistence?.stat(id))) throw rpcError(-32600, `thread not found: ${id}`);
        const handle = await ctx.agents.resume({ resumeSessionId: id, agentOptions });
        handles.set(id, handle);
        return handle.agent;
      })();
      opening.set(id, task);
      task.then(() => opening.delete(id), () => opening.delete(id));
    }
    return opening.get(id);
  }

  function hostChat(params) {
    const configured = params?.config?.['shell_environment_policy.set.NIPAPLAY_CHAT'];
    return typeof configured === 'string' && configured ? configured : undefined;
  }

  function threadResponse(thread) {
    return {
      thread, model, modelProvider: provider, cwd: thread.cwd, approvalPolicy: 'never', approvalsReviewer: 'user',
      sandbox: { type: 'dangerFullAccess' }, reasoningEffort: config.reasoningEffort ?? null, serviceTier: null,
      instructionSources: [],
    };
  }

  async function startThread(params) {
    const id = randomUUID();
    const cwd = params?.cwd ?? defaultCwd;
    const now = Date.now();
    const chat = hostChat(params);
    meta.update(id, { createdAt: now, updatedAt: now, cwd, ...(chat ? { chat } : {}) });
    const handle = await ctx.agents.create({ sessionId: id, meta: { cwd }, agentOptions });
    handles.set(id, handle);
    const thread = threadObject(id, handle.agent.session.header, []);
    notify('thread/started', { thread });
    return threadResponse(thread);
  }

  async function resumeThread(params) {
    const id = String(params?.threadId ?? '');
    const chat = hostChat(params);
    if (chat) meta.update(id, { chat });
    await ensureAgent(id);
    return threadResponse(await threadWithHistory(id));
  }

  async function listThreads(params = {}) {
    const snapshots = (await ctx.get('sessionPersistence')?.list()) ?? [];
    const kinds = Array.isArray(params.sourceKinds) && params.sourceKinds.length ? params.sourceKinds.map(String) : undefined;
    const wantChildren = kinds?.some((kind) => kind.startsWith('subAgent')) ?? false;
    const wantRoots = !kinds || kinds.some((kind) => !kind.startsWith('subAgent'));
    const cwd = typeof params.cwd === 'string' ? params.cwd : undefined;
    const rows = [];
    for (const { header } of snapshots) {
      const child = header.parentSession !== undefined;
      if (child ? !wantChildren : !wantRoots) continue;
      if (cwd && header.cwd && header.cwd !== cwd && realCwd(header.cwd) !== realCwd(cwd)) continue;
      rows.push(threadObject(String(header.id), header, []));
    }
    const key = params.sortKey === 'updated_at' ? 'updatedAt' : 'createdAt';
    rows.sort((a, b) => b[key] - a[key] || (a.id < b.id ? -1 : 1));
    const start = Number.parseInt(params.cursor ?? '0', 10) || 0;
    const limit = Math.max(1, Math.min(Number(params.limit ?? 50), 200));
    return { data: rows.slice(start, start + limit), nextCursor: start + limit < rows.length ? String(start + limit) : null, backwardsCursor: null };
  }

  async function startTurn(params) {
    const id = String(params?.threadId ?? '');
    const agent = await ensureAgent(id);
    const message = userMessage(params.input);
    // The turn exists once DSH claims this message from the agent's inbox.
    const claimed = new Promise((resolve, reject) => claims.set(message.id, { resolve, reject }));
    agent.followup(message);
    const turn = await claimed;
    const started = liveFor(id).turnStartedAt.get(turn) ?? Date.now();
    return {
      turn: { id: turnIdOf(id, turn), items: [], status: 'inProgress', error: null, startedAt: seconds(started), completedAt: null, durationMs: null },
    };
  }

  function steerTurn(params) {
    const id = String(params?.threadId ?? '');
    const agent = ctx.agents.get(id);
    const current = currentTurnId(id);
    if (!agent || current === null || current !== params.expectedTurnId) {
      throw rpcError(-32600, `No active turn ${params.expectedTurnId} on thread ${id}.`);
    }
    // DSH admits steering at the next step boundary of the running turn.
    agent.steer(userMessage(params.input));
    return { turnId: current };
  }

  function interruptTurn(params) {
    // Stop the running turn and clear what was queued behind it.
    ctx.agents.get(String(params?.threadId ?? ''))?.cancel({ kind: 'user' });
    return {};
  }

  async function compactThread(params) {
    const compaction = ctx.get('compaction');
    if (!compaction) throw rpcError(-32603, 'DSH compaction is not mounted.');
    const agent = await ensureAgent(String(params?.threadId ?? ''));
    try {
      await compaction.compactNow(agent, new AbortController().signal);
    } catch (error) {
      throw rpcError(-32603, String(error?.message ?? error));
    }
    return {};
  }

  const handlers = {
    initialize: async () => {
      await ctx.get('loader')?.await?.();
      return { userAgent: `nipaplay-dsh/${version}`, codexHome: home, platformFamily: process.platform, platformOs: process.platform };
    },
    'config/read': async () => ({ config: { model, model_provider: provider, model_reasoning_effort: config.reasoningEffort ?? null }, origins: {}, layers: null }),
    'model/list': async () => ({
      data: [{
        id: model, model, displayName: model, description: '', hidden: false, isDefault: true,
        supportedReasoningEfforts: [], defaultReasoningEffort: config.reasoningEffort ?? 'medium',
      }],
      nextCursor: null,
    }),
    // Nipa's memory arrives through the nipa-memory plugin, not Codex hooks.
    'hooks/list': async (params) => ({ data: (params?.cwds ?? []).map((cwd) => ({ cwd, hooks: [], errors: [], warnings: [] })) }),
    'thread/start': startThread,
    'thread/resume': resumeThread,
    'thread/read': async (params) => ({ thread: await threadWithHistory(String(params?.threadId ?? ''), params?.includeTurns !== false) }),
    'thread/list': listThreads,
    'thread/name/set': async (params) => {
      meta.update(String(params.threadId), { name: String(params.name ?? '') });
      return {};
    },
    'thread/compact/start': compactThread,
    'turn/start': startTurn,
    'turn/steer': async (params) => steerTurn(params),
    'turn/interrupt': async (params) => interruptTurn(params),
  };

  async function onMessage({ id, method, params }) {
    if (method === undefined || id === undefined || id === null) return;
    const handler = handlers[method];
    if (!handler) {
      wire.send({ id, error: { code: -32601, message: `Unsupported method: ${method}` } });
      return;
    }
    try {
      wire.send({ id, result: await handler(params ?? {}) });
    } catch (error) {
      if (!error?.rpc) ctx.logger?.warn?.(`nipa-app-server: ${method} failed: ${error?.stack ?? error}`);
      wire.send({ id, error: error?.rpc ?? { code: -32603, message: String(error?.message ?? error) } });
    }
  }

  // ---- DSH facts as Codex notifications ----

  function releaseHold(childId) {
    const hold = holds.get(childId);
    if (!hold) return;
    holds.delete(childId);
    clearTimeout(hold.timer);
    hold.emit();
  }

  function completeBlock(threadId, turnId, block) {
    if (block.done) return;
    block.done = true;
    if (block.kind === 'text') itemCompleted(threadId, turnId, { type: 'agentMessage', id: block.itemId, text: block.text, phase: null });
    else itemCompleted(threadId, turnId, { type: 'reasoning', id: block.itemId, summary: [], content: block.text ? [block.text] : [] });
  }

  function finishTurn(threadId, event) {
    const state = liveFor(threadId);
    const { turn, reason } = event.data;
    const turnId = turnIdOf(threadId, turn);
    for (const stream of state.streams.values()) {
      if (stream.turn === turn) for (const block of stream.blocks.values()) completeBlock(threadId, turnId, block);
    }
    for (const [callId, call] of state.calls) {
      if (call.turn !== turn) continue;
      itemCompleted(threadId, turnId, { ...call.item, status: 'failed' });
      state.calls.delete(callId);
    }
    if (state.openTurn === turn) state.openTurn = undefined;
    const startedAt = state.turnStartedAt.get(turn);
    state.turnStartedAt.delete(turn);
    meta.update(threadId, { updatedAt: event.time });
    const payload = {
      threadId,
      turn: {
        id: turnId, items: [], status: turnStatus(reason), error: reason?.kind === 'error' ? turnError(reason.error) : null,
        startedAt: seconds(startedAt), completedAt: seconds(event.time), durationMs: startedAt === undefined ? null : event.time - startedAt,
      },
    };
    const emit = () => notify('turn/completed', payload);
    if (activations.has(threadId)) {
      // DSH hands a settled child's reply to its parent right after this turn
      // ends. Report the child's end once that delivery is visible, so
      // NipaPlay's durable return sees DSH's delivery before it acts itself.
      releaseHold(threadId);
      holds.set(threadId, { emit, timer: setTimeout(() => releaseHold(threadId), SETTLEMENT_HOLD_MS) });
    } else {
      emit();
    }
  }

  function onSessionEvent(session, event) {
    const threadId = String(session.id);
    const state = liveFor(threadId);
    const data = event.data ?? {};
    switch (event.type) {
      case 'turn/start':
        releaseHold(threadId);
        state.openTurn = data.turn;
        state.turnStartedAt.set(data.turn, event.time);
        notify('turn/started', {
          threadId,
          turn: { id: turnIdOf(threadId, data.turn), items: [], status: 'inProgress', error: null, startedAt: seconds(event.time), completedAt: null, durationMs: null },
        });
        break;
      case 'user/message': {
        const turnId = currentTurnId(threadId);
        const kind = data.source?.kind;
        if (kind === 'user') {
          if (!meta.get(threadId)?.preview) meta.update(threadId, { preview: textOf(data.content).split('\n')[0].slice(0, 200) });
          if (!turnId) break;
          const item = userItem(data);
          itemStarted(threadId, turnId, item);
          itemCompleted(threadId, turnId, item);
          break;
        }
        if (HIDDEN_SOURCES.has(kind) || !turnId) break;
        const item = deliveredItem(threadId, data);
        if (!item) break;
        itemStarted(threadId, turnId, { ...item, status: 'inProgress' });
        itemCompleted(threadId, turnId, item);
        if (kind === 'subagent-settled') releaseHold(String(data.source.senderSessionId));
        break;
      }
      case 'assistant/message': {
        // Streamed blocks were completed live; a message without live frames
        // in this process is reported whole.
        const key = `${data.turn}:${data.step}`;
        const streamed = [...state.streams.values()].find((stream) => stream.key === key && !stream.committed);
        if (streamed) {
          streamed.committed = true;
          break;
        }
        const turnId = turnIdOf(threadId, data.turn);
        const attempt = (state.attempts.get(key) ?? 0) + 1;
        state.attempts.set(key, attempt);
        (data.message?.content ?? []).forEach((block, index) => {
          if (!block.text || (block.type !== 'text' && block.type !== 'reasoning')) return;
          const done = { kind: block.type, itemId: blockItemId(turnId, data.step, attempt, index), text: block.text, done: false };
          itemStarted(threadId, turnId, block.type === 'text'
            ? { type: 'agentMessage', id: done.itemId, text: '', phase: null }
            : { type: 'reasoning', id: done.itemId, summary: [], content: [] });
          completeBlock(threadId, turnId, done);
        });
        break;
      }
      case 'tool/call': {
        const turnId = turnIdOf(threadId, data.turn);
        const item = toolItem(threadId, data, session.header?.cwd ?? defaultCwd);
        state.calls.set(String(data.callId), { item, turn: data.turn, startedAt: event.time });
        itemStarted(threadId, turnId, item);
        const todos = data.name === 'todo_write' ? parseJson(data.arguments)?.todos : undefined;
        if (Array.isArray(todos)) {
          notify('turn/plan/updated', {
            threadId, turnId, explanation: null,
            plan: todos.map((todo) => ({
              step: String(todo.content ?? todo.title ?? ''),
              status: todo.status === 'in_progress' ? 'inProgress' : todo.status === 'completed' ? 'completed' : 'pending',
            })),
          });
        }
        break;
      }
      case 'tool/result': {
        const callId = String(data.message?.toolCallId ?? data.message?.source?.callId ?? '');
        const call = state.calls.get(callId);
        if (!call) break;
        state.calls.delete(callId);
        itemCompleted(threadId, turnIdOf(threadId, data.turn), completeToolItem(call.item, data, call.startedAt, event.time));
        break;
      }
      case 'job/registered':
        if (data.kind === 'bash' && data.toolCall?.callId !== undefined) {
          jobCalls.set(String(data.jobId), { threadId, callId: String(data.toolCall.callId), owner: data.owner, cursor: 0 });
        }
        break;
      case 'job/settled':
        jobCalls.delete(String(data.jobId));
        break;
      case 'turn/end':
        finishTurn(threadId, event);
        break;
      default:
        break;
    }
  }

  function onStream({ agent, frame }) {
    const threadId = String(agent.session.id);
    const state = liveFor(threadId);
    if (frame.type === 'start') {
      const key = `${frame.turn}:${frame.step}`;
      const attempt = (state.attempts.get(key) ?? 0) + 1;
      state.attempts.set(key, attempt);
      state.streams.set(frame.attemptId, { key, turn: frame.turn, step: frame.step, attempt, blocks: new Map(), committed: false });
      return;
    }
    const stream = state.streams.get(frame.attemptId);
    if (!stream) return;
    const turnId = turnIdOf(threadId, stream.turn);
    if (frame.type === 'end') {
      for (const block of stream.blocks.values()) completeBlock(threadId, turnId, block);
      // The committed assistant/message precedes this frame; keep an
      // uncommitted stream briefly in case its event is still queued.
      if (stream.committed || frame.outcome?.kind !== 'committed' || frame.outcome.eventType !== 'assistant/message') state.streams.delete(frame.attemptId);
      else setTimeout(() => state.streams.delete(frame.attemptId), 1000);
      return;
    }
    const chunk = frame.chunk;
    if (chunk.type === 'block-start' && (chunk.blockType === 'text' || chunk.blockType === 'reasoning')) {
      const itemId = blockItemId(turnId, stream.step, stream.attempt, chunk.index);
      stream.blocks.set(chunk.index, { kind: chunk.blockType, itemId, text: '', done: false });
      itemStarted(threadId, turnId, chunk.blockType === 'text'
        ? { type: 'agentMessage', id: itemId, text: '', phase: null }
        : { type: 'reasoning', id: itemId, summary: [], content: [] });
    } else if (chunk.type === 'text-delta' || chunk.type === 'reasoning-delta') {
      const block = stream.blocks.get(chunk.index);
      if (!block || !chunk.text) return;
      block.text += chunk.text;
      if (block.kind === 'text') notify('item/agentMessage/delta', { threadId, turnId, itemId: block.itemId, delta: chunk.text });
      else notify('item/reasoning/textDelta', { threadId, turnId, itemId: block.itemId, delta: chunk.text, contentIndex: 0 });
    } else if (chunk.type === 'block-end') {
      const block = stream.blocks.get(chunk.index);
      if (!block) return;
      if (typeof chunk.block?.text === 'string') block.text = chunk.block.text;
      completeBlock(threadId, turnId, block);
    }
  }

  function onJobEvent(event) {
    if (event.type !== 'output') return;
    const job = jobCalls.get(String(event.id));
    const call = job && live.get(job.threadId)?.calls.get(job.callId);
    if (!call) return;
    let read;
    try {
      read = ctx.get('jobs').readAt(event.id, job.cursor, job.owner);
    } catch {
      return;
    }
    job.cursor = read.next;
    const delta = read.chunks.filter((chunk) => chunk.channel !== 'log').map((chunk) => chunk.text).join('');
    if (delta) notify('item/commandExecution/outputDelta', { threadId: job.threadId, turnId: turnIdOf(job.threadId, call.turn), itemId: job.callId, delta });
  }

  ctx.on('session/event', onSessionEvent);
  ctx.on('agent/assistant-stream', onStream);
  ctx.on('agent/inbox/claimed', ({ message, turn }) => {
    const entry = claims.get(message.id);
    if (!entry) return;
    claims.delete(message.id);
    entry.resolve(turn);
  });
  ctx.on('agent/inbox/discarded', ({ message }) => {
    const entry = claims.get(message.id);
    if (!entry) return;
    claims.delete(message.id);
    entry.reject(rpcError(-32603, 'The input was discarded before its turn started.'));
  });
  ctx.on('session/created', (session) => {
    const parent = session.header?.parentSession;
    if (parent === undefined) return;
    const id = String(session.id);
    meta.update(id, { parentThreadId: String(parent), createdAt: session.header.createdAt, updatedAt: session.header.createdAt, cwd: session.header.cwd });
    notify('thread/started', { thread: threadObject(id, session.header, []) });
  });
  ctx.on('subagent/start', (info) => {
    if (info.local) activations.add(String(info.id));
  });
  ctx.on('subagent/end', (info) => {
    const id = String(info.id);
    activations.delete(id);
    // Without a parent to wake, nothing will arrive to release the hold.
    const parent = meta.get(id)?.parentThreadId;
    if (!parent || ctx.agents.get(parent)?.status !== 'running') setTimeout(() => releaseHold(id), 100);
  });

  // ---- Each session's shell commands carry its own NIPAPLAY_CHAT ----
  ctx.inject(['shell'], (shellCtx) => {
    const shell = shellCtx.shell;
    const original = shell.resolve;
    const resolve = function (request) {
      const chat = chatFor(request?.dshEnv?.DSH_SESSION_ID);
      return original.call(this, chat ? { ...request, env: { ...(request?.env ?? {}), NIPAPLAY_CHAT: chat } } : request);
    };
    shell.resolve = resolve;
    shellCtx.effect(() => () => {
      if (shell.resolve === resolve) shell.resolve = original;
    }, 'nipa-app-server.shell-env');
  });

  // ---- Nipa's questions to the person: Codex's request_user_input ----
  ctx.on('user-questions/request', async (request, next) => {
    if (!request.agent || !wire) return next();
    const threadId = String(request.agent.session.id);
    const asking = [...(live.get(threadId)?.calls.entries() ?? [])].filter(([, call]) => call.item.tool === 'ask_user_question').pop();
    const response = await wire.request('item/tool/requestUserInput', {
      threadId,
      turnId: currentTurnId(threadId) ?? '',
      itemId: String(request.wait?.callId ?? asking?.[0] ?? randomUUID()),
      questions: (request.questions ?? []).map((question) => ({
        id: String(question.id), header: String(question.header ?? ''),
        question: question.detail ? `${question.question}\n\n${question.detail}` : String(question.question),
        isOther: true, isSecret: false,
        options: question.options?.length ? question.options.map((option) => ({ label: String(option.label), description: String(option.description ?? '') })) : null,
      })),
    }, request.signal);
    return {
      answers: (request.questions ?? []).map((question) => {
        const given = (response?.answers?.[question.id]?.answers ?? []).map(String);
        const labels = new Set((question.options ?? []).map((option) => option.label));
        const custom = given.filter((answer) => !labels.has(answer)).join('\n');
        return { id: String(question.id), selected: given.filter((answer) => labels.has(answer)), ...(custom ? { custom } : {}) };
      }),
    };
  });

  ctx.effect(() => {
    wire = new Wire((message) => {
      onMessage(message).catch((error) => ctx.logger?.warn?.(`nipa-app-server: ${error?.stack ?? error}`));
    });
    wire.start();
    const unsubscribe = ctx.get('jobs')?.events?.subscribe({ owners: 'all' }, onJobEvent);
    return async () => {
      unsubscribe?.();
      wire.close();
      for (const hold of holds.values()) clearTimeout(hold.timer);
      meta.flush();
      if (globalThis[CHAT_KEY] === chatFor) delete globalThis[CHAT_KEY];
      const roots = [...handles.values()];
      handles.clear();
      try {
        await ctx.get('subagents')?.drainDescendants(roots.map((handle) => handle.agent));
      } catch (error) {
        ctx.logger?.warn?.(`nipa-app-server: stopping helpers failed: ${error}`);
      }
      await Promise.allSettled(roots.map((handle) => handle.dispose()));
    };
  }, 'nipa-app-server.serve');
}
