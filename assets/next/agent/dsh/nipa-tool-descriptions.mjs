// Nipa's own wording for the tools DSH offers the model.
//
// DSH's tools carry the description their plugin registered with; there is no
// setting for it. The documented place to reshape what a request offers is the
// `system-prompt/assemble` waterfall, whose assembly lists the tool schemas
// about to be sent. This plugin replaces `description` there, by tool name,
// with the text in config.file (a JSON object of name -> description). The
// parameter schemas, the tools' behaviour and every tool the file does not
// name stay as DSH made them. Only public API is used: no DSH file is imported.
import { readFileSync } from 'node:fs';

export const name = 'nipa-tool-descriptions';

export function apply(ctx, config = {}) {
  if (!config.file) throw new Error('nipa-tool-descriptions: config.file names the descriptions');
  const table = JSON.parse(readFileSync(config.file, 'utf8'));
  if (table === null || typeof table !== 'object' || Array.isArray(table)) {
    throw new Error('nipa-tool-descriptions: the file must be a JSON object of tool name to description');
  }
  for (const [tool, text] of Object.entries(table)) {
    if (typeof text !== 'string' || text.trim() === '') {
      throw new Error(`nipa-tool-descriptions: the description of ${tool} must be a non-empty string`);
    }
  }
  const reported = new Set();
  ctx.on('system-prompt/assemble', async (assembly, context, next) => {
    const result = await next();
    const present = new Set(result.tools.map((tool) => tool.name));
    for (const tool of Object.keys(table)) {
      if (present.has(tool) || reported.has(tool)) continue;
      reported.add(tool);
      ctx.logger?.info?.(`nipa-tool-descriptions: ${tool} is not enabled here; its description is ignored`);
    }
    return {
      ...result,
      tools: result.tools.map((tool) =>
        Object.hasOwn(table, tool.name) ? { ...tool, description: table[tool.name] } : tool),
    };
  });
}
