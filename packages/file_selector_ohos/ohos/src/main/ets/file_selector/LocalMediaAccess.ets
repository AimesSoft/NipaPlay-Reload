import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import fileShare from '@ohos.fileshare';
import picker from '@ohos.file.picker';
import preferences from '@ohos.data.preferences';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { FileSelectorApiCodec } from './GeneratedFileSelectorApi';

const CHANNEL_PREFIX = 'dev.flutter.pigeon.FileSelectorApi.';
// Keep aligned with rust/src/api/file_scan.rs: is_video_file.
const VIDEO_EXTENSIONS = ['mp4', 'mkv'];

function accessError(code: string, message: string): Error {
  const error = new Error(message);
  error.name = code;
  return error;
}

interface ImportResult {
  directory: string;
  importedCount: number;
  failedCount: number;
}

// Returns real, authorized sandbox paths to Dart and Rust. Picker URIs must
// never be passed to POSIX I/O or "normalized" by replacing their slashes.
export class LocalMediaAccess {
  private busy: boolean = false;
  private context: common.UIAbilityContext;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  setup(messenger: BinaryMessenger): void {
    this.register(messenger, 'getDirectoryPath', (args: ESObject[]) => this.selectDirectory(args[0] as string | null, true));
    this.register(messenger, 'pickMediaDirectory', () => this.selectDirectory(null, false));
    this.register(messenger, 'importMediaFiles', () => this.importMediaFiles());
    this.register(messenger, 'restoreDirectoryPermissions', () => this.restorePermissions());
    this.register(messenger, 'ensureDirectoryAccess', (args: ESObject[]) => this.ensureDirectoryAccess(args[0] as string));
  }

  private register(messenger: BinaryMessenger, method: string,
    operation: (args: ESObject[]) => Promise<ESObject>): void {
    const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(messenger, CHANNEL_PREFIX + method, FileSelectorApiCodec.INSTANCE);
    channel.setMessageHandler({
      onMessage: (message: ESObject, reply: Reply<ESObject>): void => {
        operation(message as ESObject[]).then((value: ESObject) => {
          reply.reply([value]);
        }).catch((error: Error) => {
          reply.reply([error.name || 'media-access-error', error.message, null]);
        });
      }
    });
  }

  private async selectDirectory(initialDirectory: string | null, writable: boolean): Promise<string | null> {
    if (!canIUse('SystemCapability.FileManagement.UserFileService.FolderSelection')) {
      throw accessError('directory-selection-unsupported', '当前设备不支持直接选择文件夹。');
    }
    if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
      throw accessError('directory-permission-unavailable', '当前设备不支持保存文件夹访问授权。');
    }
    this.beginSelection();
    try {
      const options = new picker.DocumentSelectOptions();
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      options.maxSelectNumber = 1;
      if (initialDirectory) {
        options.defaultFilePathUri = fileUri.getUriFromPath(initialDirectory);
      }
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      if (uris.length === 0) return null;
      const uri = uris[0];
      const store = await this.getStore();
      const saved = JSON.parse(await store.get('grants', '[]') as string) as fileShare.PolicyInfo[];
      const previous = saved.find((grant: fileShare.PolicyInfo) => grant.uri === uri);
      const requestedMode = writable
        ? fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE
        : fileShare.OperationMode.READ_MODE;
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: requestedMode | (previous ? previous.operationMode : 0)
      };
      try {
        await fileShare.persistPermission([policy]);
        await fileShare.activatePermission([policy]);
      } catch (error) {
        throw accessError('directory-permission-unavailable', '无法保存文件夹访问授权，请改为导入视频文件。');
      }
      let path: string;
      try {
        path = new fileUri.FileUri(uri).path;
        if (!path.startsWith('/') || !(await fs.stat(path)).isDirectory()) {
          throw new Error('Not a readable local directory');
        }
        // A media source needs reading, not permission to create a probe file.
        await fs.listFile(path, { listNum: 1 });
      } catch (error) {
        throw accessError('directory-access-denied', '所选文件夹无法作为本地目录访问，请导入视频文件。');
      }
      const updated = saved.filter((grant: fileShare.PolicyInfo) => grant.uri !== uri);
      updated.push(policy);
      await store.put('grants', JSON.stringify(updated));
      await store.flush();
      return path;
    } finally {
      this.busy = false;
    }
  }

  async restorePermissions(): Promise<string[]> {
    const store = await this.getStore();
    const saved = JSON.parse(await store.get('grants', '[]') as string) as fileShare.PolicyInfo[];
    const failures: string[] = [];
    for (const policy of saved) {
      try {
        await fileShare.activatePermission([policy]);
      } catch (error) {
        // A revoked grant must not block restoration of the other directories.
        // Keep the record so a temporarily disconnected volume can recover.
        failures.push(policy.uri);
      }
    }
    return failures;
  }

  private getStore(): Promise<preferences.Preferences> {
    return preferences.getPreferences(this.context, { name: 'nipaplay_media_directories' });
  }

  private async ensureDirectoryAccess(path: string): Promise<null> {
    if (!path || !path.startsWith('/')) {
      throw accessError('directory-access-denied', '无效的本地文件夹路径。');
    }
    const store = await this.getStore();
    const saved = JSON.parse(await store.get('grants', '[]') as string) as fileShare.PolicyInfo[];
    // Reactivate before scanning or playback, including after a background /
    // foreground transition. A failed grant must never look like deleted media.
    let matchingPolicy: fileShare.PolicyInfo | undefined;
    let matchingLength = 0;
    for (const policy of saved) {
      const root = new fileUri.FileUri(policy.uri).path;
      if ((path === root || path.startsWith(root + '/')) && root.length > matchingLength) {
        matchingPolicy = policy;
        matchingLength = root.length;
      }
    }
    try {
      if (matchingPolicy) {
        await fileShare.activatePermission([matchingPolicy]);
      }
      await fs.listFile(path, { listNum: 1 });
    } catch (error) {
      throw accessError('directory-access-denied', '媒体文件夹暂时无法访问，请重新添加文件夹以恢复授权。');
    }
    return null;
  }

  private beginSelection(): void {
    if (this.busy) throw accessError('picker-busy', '文件选择或导入正在进行中，请稍候。');
    this.busy = true;
  }

  private async importMediaFiles(): Promise<ImportResult | null> {
    this.beginSelection();
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 500;
      options.fileSuffixFilters = ['视频|' + VIDEO_EXTENSIONS.map((ext: string) => '.' + ext).join(',')];
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      if (uris.length === 0) return null;
      // filesDir survives cache cleanup and app restarts. Never copy into cacheDir.
      const directory = this.context.filesDir + '/ImportedMedia';
      if (!await fs.access(directory)) await fs.mkdir(directory);
      let importedCount = 0;
      let failedCount = 0;
      for (const uri of uris) {
        let source: fs.File | undefined;
        let temporaryPath = '';
        try {
          const name = new fileUri.FileUri(uri).name;
          const dot = name.lastIndexOf('.');
          if (name.includes('/') || name.includes('\\') || dot < 1 ||
            !VIDEO_EXTENSIONS.includes(name.substring(dot + 1).toLowerCase())) {
            throw new Error('所选文件不是支持的视频文件。');
          }
          let destination = directory + '/' + name;
          let suffix = 1;
          while (await fs.access(destination)) {
            destination = directory + '/' + name.substring(0, dot) + ' (' + suffix++ + ')' + name.substring(dot);
          }
          // Copy using native file descriptors: do not load a multi-GB video
          // into an ArrayBuffer or send its bytes through the Flutter channel.
          temporaryPath = destination + '.importing';
          source = await fs.open(uri, fs.OpenMode.READ_ONLY);
          await fs.copyFile(source.fd, temporaryPath);
          await fs.rename(temporaryPath, destination);
          temporaryPath = '';
          importedCount++;
        } catch (error) {
          failedCount++;
        } finally {
          if (source !== undefined) {
            try { await fs.close(source); } catch (_) {}
          }
          if (temporaryPath) {
            try { await fs.unlink(temporaryPath); } catch (_) {}
          }
        }
      }
      if (importedCount === 0) {
        throw accessError('media-import-failed', '视频导入失败，请检查剩余空间和所选文件的访问权限。');
      }
      return { directory: directory, importedCount: importedCount, failedCount: failedCount };
    } finally {
      this.busy = false;
    }
  }
}
