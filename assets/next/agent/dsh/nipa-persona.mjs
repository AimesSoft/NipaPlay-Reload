// Nipa's base instructions as DSH's complete system prompt: it replaces the
// harness identity and coding persona, like Codex's model_instructions_file.
// Workspace AGENTS.md files still arrive through agent-instructions, and
// runtime context (working directory, memory) still follows as user context.
import { readFileSync } from 'node:fs';

export const name = 'nipa-persona';
export const inject = ['systemPrompt'];

export function apply(ctx, config = {}) {
  if (!config.file) throw new Error('nipa-persona: config.file names the base instructions');
  const text = readFileSync(config.file, 'utf8').trim();
  ctx.systemPrompt.section({ name: 'nipa:base', order: 0, text, complete: true, interpolate: false });
}
