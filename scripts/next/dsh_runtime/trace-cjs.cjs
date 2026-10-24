const fs = require('node:fs');
const Module = require('node:module');
const out = process.env.DSH_TRACE_OUT;
// Windows paths are written the way URLs and POSIX paths are, so that one
// reader (build_lock.py) understands every platform's trace.
const slashed = (f) => f.replace(/\\/g, '/');
const orig = Module._load;
Module._load = function (request, parent, isMain) {
  const r = orig.apply(this, arguments);
  try { const f = Module._resolveFilename(request, parent, isMain); if (out && /[\\/]/.test(f)) fs.appendFileSync(out, 'file://' + slashed(f) + '\n'); } catch {}
  return r;
};
const dl = process.dlopen;
process.dlopen = function (m, f) { if (out) fs.appendFileSync(out, 'file://' + slashed(String(f)) + '\n'); return dl.apply(this, arguments); };

// Files read through fs (profile bundles, assets, locale files...) are as much
// part of what Nipa needs as modules.
const log = (p) => {
  try {
    if (typeof p === 'string' || p instanceof URL || Buffer.isBuffer(p)) {
      let s = slashed(p instanceof URL ? p.pathname : String(p));
      if (s.includes('node_modules/')) fs.appendFileSync(out, 'file://' + s + '\n');
    }
  } catch {}
};
const names = ['readFileSync','readFile','openSync','open','createReadStream'];
for (const n of names) {
  const o = fs[n]; if (!o) continue;
  fs[n] = function (p, ...r) { log(p); return o.call(this, p, ...r); };
  if (o.native) fs[n].native = o.native;
}
const pn = ['readFile','open'];
for (const n of pn) {
  const o = fs.promises[n]; if (!o) continue;
  fs.promises[n] = function (p, ...r) { log(p); return o.call(this, p, ...r); };
}
