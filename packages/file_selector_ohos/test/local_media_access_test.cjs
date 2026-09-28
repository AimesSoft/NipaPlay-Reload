// Run with Node and the TypeScript compiler shipped with the HarmonyOS SDK:
// node --test test/local_media_access_test.cjs
// Set ARKTS_TYPESCRIPT_PATH to <SDK>/ets/build-tools/ets-loader/node_modules/typescript.
// These tests execute the native implementation with fault-injected OS APIs;
// they do not replace an ArkTS build or testing Picker on a real device.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require(process.env.ARKTS_TYPESCRIPT_PATH || 'typescript');
const source = fs.readFileSync(path.join(__dirname,
  '../ohos/src/main/ets/file_selector/LocalMediaAccess.ets'), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
}).outputText;

function harness() {
  const handlers = new Map();
  const state = {
    supported: true, selection: [], saved: [], persisted: [], activated: [],
    failPersist: false, failActivate: '', failCopy: '', unreadable: false,
    files: new Set(), closed: [], copied: [], pickerOptions: null,
  };
  class FileUri {
    constructor(uri) { this.uri = uri; }
    get path() { return decodeURIComponent(new URL(this.uri).pathname); }
    get name() { return this.path.split('/').pop(); }
  }
  class BasicMessageChannel {
    constructor(_messenger, name) { this.name = name; }
    setMessageHandler(handler) { handlers.set(this.name, handler); }
  }
  const nativeFs = {
    OpenMode: { READ_ONLY: 0 },
    stat: async () => ({ isDirectory: () => true }),
    listFile: async () => { if (state.unreadable) throw new Error('EACCES'); return []; },
    access: async (file) => state.files.has(file),
    mkdir: async (file) => state.files.add(file),
    open: async (uri) => ({ fd: uri }),
    copyFile: async (fd, destination) => {
      assert.equal(typeof fd, 'string');
      state.copied.push([fd, destination]);
      state.files.add(destination);
      if (fd === state.failCopy) throw new Error('ENOSPC');
    },
    rename: async (from, to) => {
      assert(!state.files.has(to), 'must not overwrite an existing import');
      state.files.delete(from); state.files.add(to);
    },
    unlink: async (file) => state.files.delete(file),
    close: async (file) => state.closed.push(file.fd),
  };
  const mocks = {
    '@ohos.file.fs': nativeFs,
    '@ohos.file.fileuri': { FileUri, getUriFromPath: (p) => 'file://docs' + p },
    '@ohos.file.picker': {
      DocumentSelectOptions: class {}, DocumentSelectMode: { FOLDER: 1 },
      DocumentViewPicker: class {
        async select(options) { state.pickerOptions = options; return state.selection; }
      },
    },
    '@ohos.fileshare': {
      OperationMode: { READ_MODE: 1, WRITE_MODE: 2 },
      persistPermission: async (policies) => {
        if (state.failPersist) throw new Error('permission denied');
        state.persisted.push(...policies);
      },
      activatePermission: async (policies) => {
        if (policies[0].uri === state.failActivate) throw new Error('grant revoked');
        state.activated.push(...policies);
      },
    },
    '@ohos.data.preferences': { getPreferences: async () => ({
      get: async () => JSON.stringify(state.saved),
      put: async (_key, value) => { state.saved = JSON.parse(value); },
      flush: async () => {},
    }) },
    './GeneratedFileSelectorApi': { FileSelectorApiCodec: { INSTANCE: {} } },
  };
  const exports = {};
  vm.runInNewContext(compiled, {
    exports, canIUse: () => state.supported,
    require: (name) => {
      if (name.endsWith('/BasicMessageChannel')) return { default: BasicMessageChannel };
      if (name in mocks) return { ...mocks[name], default: mocks[name] };
      throw new Error('Unexpected native dependency: ' + name);
    },
  });
  new exports.LocalMediaAccess({ filesDir: '/app/files' }).setup({});
  const invoke = async (method, args = []) => new Promise((resolve) => {
    const handler = handlers.get('dev.flutter.pigeon.FileSelectorApi.' + method);
    assert(handler, `missing native channel: ${method}`);
    handler.onMessage(args, { reply: (value) => resolve(JSON.parse(JSON.stringify(value))) });
  });
  return { state, invoke };
}

test('directory cancellation replies null and releases the picker', async () => {
  const { state, invoke } = harness();
  assert.deepEqual(await invoke('getDirectoryPath', [null]), [null]);
  state.selection = ['file://docs/Movies/%E7%95%AA%E5%89%A7%20100%25'];
  assert.deepEqual(await invoke('pickMediaDirectory'), ['/Movies/番剧 100%']);
  assert.equal(state.persisted[0].operationMode, 1);
  assert.equal(state.saved.length, 1);
});

test('unsupported devices return an actionable error without opening Picker', async () => {
  const { state, invoke } = harness(); state.supported = false;
  assert.equal((await invoke('getDirectoryPath', [null]))[0], 'directory-selection-unsupported');
  assert.equal(state.pickerOptions, null);
});

test('general directory selection preserves write permission across restart and later media selection', async () => {
  const { state, invoke } = harness();
  state.selection = ['file://docs/Downloads'];
  assert.deepEqual(await invoke('getDirectoryPath', [null]), ['/Downloads']);
  assert.equal(state.saved[0].operationMode, 3);
  await invoke('restoreDirectoryPermissions');
  assert.equal(state.activated.at(-1).operationMode, 3);
  await invoke('pickMediaDirectory');
  assert.equal(state.saved[0].operationMode, 3);
  assert.equal(state.saved.length, 1);
});

test('inaccessible paths and failed persistent grants are never accepted', async () => {
  const { state, invoke } = harness(); state.selection = ['file://docs/Movies'];
  state.unreadable = true;
  assert.equal((await invoke('getDirectoryPath', [null]))[0], 'directory-access-denied');
  state.unreadable = false; state.failPersist = true;
  assert.equal((await invoke('getDirectoryPath', [null]))[0], 'directory-permission-unavailable');
  assert.deepEqual(state.saved, []);
});

test('restoration isolates revoked grants and retains them for retry', async () => {
  const { state, invoke } = harness();
  state.saved = [{uri: 'file://docs/revoked', operationMode: 1}, {uri: 'file://docs/available', operationMode: 3}];
  state.failActivate = state.saved[0].uri;
  assert.deepEqual(await invoke('restoreDirectoryPermissions'), [['file://docs/revoked']]);
  assert.equal(state.activated[0].uri, 'file://docs/available');
  assert.equal(state.saved.length, 2);
});

test('file import cancellation creates no directories', async () => {
  const { state, invoke } = harness();
  assert.deepEqual(await invoke('importMediaFiles'), [null]);
  assert.equal(state.files.size, 0);
});

test('access reactivation respects directory boundaries and retries after revocation', async () => {
  const { state, invoke } = harness();
  state.saved = [{uri: 'file://docs/Movies', operationMode: 1}, {uri: 'file://docs/Movies/Anime', operationMode: 1}];
  assert.deepEqual(await invoke('ensureDirectoryAccess', ['/Movies/Anime/Season 1']), [null]);
  assert.equal(state.activated[0].uri, state.saved[1].uri);
  assert.deepEqual(await invoke('ensureDirectoryAccess', ['/Movies-other']), [null]);
  assert.equal(state.activated.length, 1);
  state.failActivate = state.saved[1].uri;
  assert.equal((await invoke('ensureDirectoryAccess', ['/Movies/Anime']))[0], 'directory-access-denied');
  state.failActivate = '';
  assert.deepEqual(await invoke('ensureDirectoryAccess', ['/Movies/Anime']), [null]);
  assert.equal((await invoke('ensureDirectoryAccess', ['file://docs/Movies']))[0], 'directory-access-denied');
});

test('concurrent picker requests are rejected without losing the active request', async () => {
  const { invoke } = harness();
  const active = invoke('getDirectoryPath', [null]);
  assert.equal((await invoke('importMediaFiles'))[0], 'picker-busy');
  assert.deepEqual(await active, [null]);
  assert.deepEqual(await invoke('importMediaFiles'), [null]);
});

test('imports copy via descriptors, preserve names and never overwrite', async () => {
  const { state, invoke } = harness();
  state.selection = ['file://docs/a/episode.mkv', 'file://docs/b/episode.mkv'];
  const [result] = await invoke('importMediaFiles');
  assert.equal(result.directory, '/app/files/ImportedMedia');
  assert.equal(result.importedCount, 2);
  assert(state.files.has(result.directory + '/episode.mkv'));
  assert(state.files.has(result.directory + '/episode (1).mkv'));
  assert.equal(state.closed.length, 2);
  assert(![...state.files].some((file) => file.endsWith('.importing')));
});

test('partial import failure cleans temporary files and reports successful imports', async () => {
  const { state, invoke } = harness();
  state.selection = ['file://docs/ok.mp4', 'file://docs/fail.mp4', 'file://docs/rejected.txt'];
  state.failCopy = state.selection[1];
  const [result] = await invoke('importMediaFiles');
  assert.equal(result.importedCount, 1); assert.equal(result.failedCount, 2);
  assert.equal(state.closed.length, 2);
  assert(state.files.has(result.directory + '/ok.mp4'));
  assert(![...state.files].some((file) => file.endsWith('.importing')));
});

test('total failure reports an error and permits retry', async () => {
  const { state, invoke } = harness();
  state.selection = ['file://docs/fail.mp4']; state.failCopy = state.selection[0];
  assert.equal((await invoke('importMediaFiles'))[0], 'media-import-failed');
  state.failCopy = '';
  assert.equal((await invoke('importMediaFiles'))[0].importedCount, 1);
});
