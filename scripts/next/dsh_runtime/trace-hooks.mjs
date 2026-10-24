import { appendFileSync } from 'node:fs';
const out = process.env.DSH_TRACE_OUT;
export async function load(url, context, next) {
  if (out && url.startsWith('file://')) appendFileSync(out, url + '\n');
  return next(url, context);
}
