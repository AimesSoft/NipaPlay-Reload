// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.
// Based on FileSelectorApiImpl.java originally written by
// Copyright 2013 The Flutter Authors.

import fs from '@ohos.file.fs';
import picker from '@ohos.file.picker';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { Result, FileTypes, FileResponse, FileSelectorApiCodec, wrapError } from './GeneratedFileSelectorApi'
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MessageCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/MessageCodec';
import BasicMessageChannel, { Reply } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BasicMessageChannel';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import common from '@ohos.app.ability.common';
import { photoPickerSelect, documentPickerSelect, filePicker } from './FIleSelectorUtil'
import ArrayList from '@ohos.util.ArrayList';

const TAG = "FileSelectorApiImpl";
const DOCUMENT = "Document";
const TEXT_MIME_TYPE = "text/*";
const MIME_TYPE = "*/*";
const PICTURE = "Picture";
const TEXT = "Text";
const FILE_SELECTION_CANCELLED = "file-selection-cancelled";
export class FileSelectorApiImpl {

  binding: AbilityPluginBinding;

  constructor(binding: AbilityPluginBinding) {
    this.binding = binding;
  }

  openFileWithExtensions(initialDirectory: string, allowedTypes: FileTypes, result: Result<FileResponse>): void {
    Log.d(TAG, 'openFile types:' + allowedTypes.extensions + ' dir:' + initialDirectory)
    filePicker(initialDirectory, allowedTypes, 1).then(async (filePickerResult: ESObject) => {
      if (filePickerResult != undefined) {
        const selectedPaths = filePickerResult as Array<string>;
        if (selectedPaths.length === 0) {
          Log.i(TAG, 'DocumentViewPicker was cancelled.');
          result.error(new Error(FILE_SELECTION_CANCELLED));
          return;
        }
        let fileUris = await this.getUrisForPaths(selectedPaths);
        if (fileUris.length === 0) {
          result.error(new Error('Failed to resolve the selected file.'));
          return;
        }
        let uri: string = fileUris[0];
        Log.i(TAG,'documentPickerSelect select file successfully, documentPicker uri: ' + uri);
        FileSelectorApiImpl.toFileResponse(uri, MIME_TYPE, uri.substring(uri.lastIndexOf("/") + 1))
          .then((file) => {
            result.success(file);
          }).catch((err: ESObject) => {
          Log.e(TAG, 'documentPickerSelect select file failed with err: ' + err);
          result.error(err);
        });
      } else {
        Log.i(TAG, 'DocumentViewPicker was cancelled.');
        result.error(new Error(FILE_SELECTION_CANCELLED))
      }
    }).catch((err: Error) => {
      Log.e(TAG, 'documentPickerSelect select file failed with err: ' + err);
      result.error(err);
    });
  }

  openFilesWithExtensions(initialDirectory: string, allowedTypes: FileTypes, result: Result<Array<FileResponse>>): void {
    Log.d(TAG, 'openFiles types:' + allowedTypes.extensions + ' dir:' + initialDirectory)
    filePicker(initialDirectory, allowedTypes).then((filePickerResult: ESObject) => {
      if (filePickerResult != undefined) {
        const selectedPaths = filePickerResult as Array<string>;
        if (selectedPaths.length === 0) {
          Log.i(TAG, 'DocumentViewPicker was cancelled.');
          result.error(new Error(FILE_SELECTION_CANCELLED));
          return;
        }
        Log.i(TAG,'documentPickerSelect select files successfully, documentPicker uris: ' + filePickerResult);
        FileSelectorApiImpl.toFileListResponse(selectedPaths, MIME_TYPE)
          .then((file) => {
            result.success(file);
          }).catch((err: ESObject) => {
          Log.e(TAG, 'documentPickerSelect select files failed with err: ' + err);
          result.error(err);
        });
      } else {
        Log.i(TAG, 'DocumentViewPicker was cancelled.');
        result.error(new Error(FILE_SELECTION_CANCELLED))
      }
    }).catch((err: Error) => {
      Log.e(TAG, 'documentPickerSelect select files failed with err: ' + err);
      result.error(err);
    });
  }

  openFile(initialDirectory: string, allowedTypes: FileTypes, result: Result<FileResponse>): void {
    if (allowedTypes.getMimeTypes().length == 0) {
      allowedTypes.setMimeTypes(tryConvertExtensionsToMimetypes(allowedTypes.getExtensions()));
    }
    Log.d(TAG, 'openFile types:' + allowedTypes.mimeTypes + ' dir:' + initialDirectory)
    for (let type of allowedTypes.getMimeTypes()) {
      Log.d(TAG, 'openFile type:' + type)
      switch (type) {
        case picker.PhotoViewMIMETypes.IMAGE_TYPE:
        case picker.PhotoViewMIMETypes.VIDEO_TYPE:
        case picker.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE:
          try {
            let PhotoSelectOptions = new picker.PhotoSelectOptions();
            PhotoSelectOptions.MIMEType = type;
            PhotoSelectOptions.maxSelectNumber = 1;
            photoPickerSelect(PhotoSelectOptions, this.getContext()).then((PhotoSelectResult: picker.PhotoSelectResult) => {
              console.info('PhotoViewPicker.select successfully, PhotoSelectResult uri: ' + JSON.stringify(PhotoSelectResult));
              let res: picker.PhotoSelectResult = PhotoSelectResult;
              FileSelectorApiImpl.toFileResponse(res.photoUris[0] , type, PICTURE)
                .then((file) => {
                  result.success(file);
              }).catch((err: ESObject) => {
                  Log.e(TAG, 'PhotoViewPicker.select failed with err: ' + err);
                  result.error(err);
              });
            }).catch((err: ESObject) => {
              Log.e(TAG, 'PhotoViewPicker.select failed with err: ' + err);
              result.error(new Error("Failed to read file, err: " + err));
            });
          } catch (err) {
            console.error('PhotoViewPicker failed with err: ' + err);
            result.error(new Error("Failed to read file: " + initialDirectory));
          }
          break;
        case DOCUMENT:
          try {
            let documentSelectOptions = new picker.DocumentSelectOptions();
            documentSelectOptions.maxSelectNumber = 1;
            documentPickerSelect(documentSelectOptions, this.getContext()).then((documentPickerResult: ESObject) => {
              if (Number.isNaN(Number(documentPickerResult))) {
                let uri: string = documentPickerResult[0];
                Log.i(TAG,'documentPickerSelect select successfully, documentPicker uri: ' + uri);
                FileSelectorApiImpl.toFileResponse(uri, TEXT_MIME_TYPE, TEXT)
                  .then((file) => {
                    result.success(file);
                  }).catch((err: ESObject) => {
                  Log.e(TAG, 'documentPickerSelect select failed with err: ' + err);
                  result.error(err);
                });
              } else {
                Log.e(TAG, 'documentPickerSelect select failed with errCode: ' + documentPickerResult);
                result.error(new Error("Failed to select file with errCode: " + documentPickerResult))
              }
            });
          } catch (err) {
            Log.e(TAG, 'documentPickerSelect select failed with err: ' + err);
            result.error(new Error("Failed to read file: " + initialDirectory));
          }
          break;
        default :
          break;
      }
    }
  }

  getContext(): common.UIAbilityContext {
    return this.binding.getAbility().context;
  }

  openFiles(initialDirectory: string, allowedTypes: FileTypes, result: Result<Array<FileResponse>>): void {
    if (allowedTypes.getMimeTypes().length == 0) {
      allowedTypes.setMimeTypes(tryConvertExtensionsToMimetypes(allowedTypes.getExtensions()));
    }
    for (let type of allowedTypes.getMimeTypes()) {
      Log.d(TAG, 'openFiles type:' + type)
      switch (type) {
        case picker.PhotoViewMIMETypes.IMAGE_TYPE:
        case picker.PhotoViewMIMETypes.VIDEO_TYPE:
        case picker.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE:
          try {
            let PhotoSelectOptions = new picker.PhotoSelectOptions();
            PhotoSelectOptions.MIMEType = type;
            PhotoSelectOptions.maxSelectNumber = 5;
            photoPickerSelect(PhotoSelectOptions, this.getContext()).then((PhotoSelectResult: picker.PhotoSelectResult) => {
              Log.i(TAG, 'PhotoViewPicker.select successfully, PhotoSelectResult uri: ' + JSON.stringify(PhotoSelectResult));
              const res: picker.PhotoSelectResult = PhotoSelectResult; //<picker.PhotoSelectResult>(PhotoSelectResult);
              FileSelectorApiImpl.toFileListResponse(res.photoUris, type)
                .then((files) => {
                  Log.i(TAG, 'PhotoViewPicker.select successfully, uri: ' + JSON.stringify(PhotoSelectResult));
                  result.success(files);
                }).catch((err: ESObject) => {
                  Log.e(TAG, 'PhotoViewPicker.select failed with err: ' + err);
                  result.error(err);
              });
            }).catch((err: ESObject) => {
              Log.e(TAG, 'PhotoViewPicker.select failed with err: ' + err);
              result.error(new Error("Failed to read file, err: " + err));
            });
          } catch (err) {
            Log.e(TAG, 'PhotoViewPicker failed with err: ' + err);
            result.error(new Error("Failed to read file: " + initialDirectory));
          }
          break;
        case DOCUMENT:
          try {
            let documentSelectOptions = new picker.DocumentSelectOptions();
            documentSelectOptions.maxSelectNumber = 5;
            documentPickerSelect(documentSelectOptions, this.getContext()).then((documentPickerResult: ESObject) => {
              if (Number.isNaN(Number(documentPickerResult))) {
                let pickerResult = documentPickerResult as Array<string>;
                Log.i(TAG,'documentPickerSelect select successfully, documentPicker uris: ' + pickerResult.toString());
                FileSelectorApiImpl.toFileListResponse(pickerResult, TEXT_MIME_TYPE)
                  .then((files) => {
                    result.success(files);
                  }).catch((err: ESObject) => {
                  Log.e(TAG, 'documentPickerSelect select failed with err: ' + err);
                  result.error(err);
                });
              } else {
                Log.e(TAG, 'documentPickerSelect select failed with errCode: ' + documentPickerResult);
                result.error(new Error("Failed to select file with errCode: " + documentPickerResult))
              }
            });
          } catch (err) {
            Log.e(TAG, 'documentPickerSelect select failed with err: ' + err);
            result.error(new Error("Failed to read file: " + initialDirectory));
          }
          break;
        default :
          break;
      }
    }
  }

  getDirectoryPath(initialDirectory: string, result: Result<string>): void {
    throw new Error('Method not implemented.')
  }

  async getUrisForPaths(paths: Array<string>): Promise<Array<string>> {
    Log.i(TAG, "getUrisForPaths");
    let uris = new Array<string>();
    try {
      paths.forEach(async path => {
        let folder = this.getContext().cacheDir;
        if (!fs.accessSync(folder)) {
          fs.mkdirSync(folder);
        }
        let oldFile: fs.File = fs.openSync(path);
        let newFile = folder + '/' + oldFile.name;
        fs.copyFileSync(oldFile.fd, newFile);
        uris.push(newFile);
      })
    } catch (err) {
      Log.e(TAG, 'Failed to getUrisForPaths: ' + JSON.stringify(err));
    }
    return uris;
  }

  static getCodec(): MessageCodec<ESObject> {
    return FileSelectorApiCodec.INSTANCE;
  }

  setup(binaryMessenger: BinaryMessenger, abilityPluginBinding: AbilityPluginBinding): void {
    let api = this;
    {
      this.binding = abilityPluginBinding;
      const channel: BasicMessageChannel<ESObject> = new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.FileSelectorApi.openFile", FileSelectorApiImpl.getCodec());
      channel.setMessageHandler({
        onMessage(msg: ESObject, reply: Reply<ESObject>): void {
          Log.d(TAG, 'onMessage reply:' + reply)
          const wrapped: Array<ESObject> = new Array<ESObject>();
          const args: Array<ESObject> = msg as Array<ESObject>;
          const initialDirectoryArg = args[0] as string;
          const allowedTypesArg = args[1] as FileTypes;
          const resultCallback: Result<FileResponse> = new ResultBuilder((result: FileResponse): void => {
            wrapped.push(result);
            reply.reply(wrapped);
          },(error: Error): void => {
            if (error.message === FILE_SELECTION_CANCELLED) {
              wrapped.push(null);
              reply.reply(wrapped);
              return;
            }
            const wrappedError: ArrayList<ESObject> = msg.wrapError(error);
            reply.reply(wrappedError);
          })
          api.openFileWithExtensions(initialDirectoryArg, allowedTypesArg, resultCallback);
        }
      });
    }
    {
      this.binding = abilityPluginBinding;
      const channel: BasicMessageChannel<ESObject>  = new BasicMessageChannel<ESObject>(
        binaryMessenger, "dev.flutter.pigeon.FileSelectorApi.openFiles", FileSelectorApiImpl.getCodec());
      channel.setMessageHandler({
        onMessage(msg: ESObject, reply: Reply<ESObject>): void {
          Log.d(TAG, 'onMessage reply:' + reply)
          const wrapped: Array<ESObject> = new Array<ESObject>();
          const args: Array<ESObject> = msg as Array<ESObject>;
          const initialDirectoryArg = args[0] as string;
          const allowedTypesArg = args[1] as FileTypes;
          const resultCallback: Result<Array<FileResponse>> = new ResultsBuilder((result: Array<FileResponse>): void => {
            wrapped.push(result);
            reply.reply(wrapped);
          },(error: Error): void => {
            if (error.message === FILE_SELECTION_CANCELLED) {
              wrapped.push(new Array<FileResponse>());
              reply.reply(wrapped);
              return;
            }
            const wrappedError: ArrayList<ESObject> = msg.wrapError(error);
            reply.reply(wrappedError);
          })
          api.openFilesWithExtensions(initialDirectoryArg, allowedTypesArg, resultCallback);
        }
      });
    }
  }

  static async toFileResponse(uri: string, type: string, name: string): Promise<FileResponse> {
    let file = fs.openSync(uri);
    let stream = fs.fdopenStreamSync(file.fd, "r");
    let stat = fs.statSync(file.fd);
    let size = stat.size;
    let buffer = new ArrayBuffer(size);
    stream.readSync(buffer, {offset: 0, length: size});
    let byteArray = new Uint8Array(buffer);
    let response = new FileResponse(uri, type, name, size, byteArray);
    stream.closeSync();
    return new Promise((resolve) => {
      resolve(response);
    })
  }

  static async toFileListResponse(uris: string[], type: string): Promise<Array<FileResponse>> {
    let files = new Array<FileResponse>();
    for (let i = 0; i < uris.length; i++) {
      let file = fs.openSync(uris[i]);
      let stream = fs.fdopenStreamSync(file.fd, "r");
      let stat = fs.statSync(file.fd);
      let size = stat.size;
      let buffer = new ArrayBuffer(size);
      stream.readSync(buffer, {offset: 0, length: size});
      let byteArray = new Uint8Array(buffer);
      let response = new FileResponse(uris[i], type, uris[i].substring(uris[i].lastIndexOf("/") + 1), size, byteArray);
      stream.closeSync();
      files.push(response)
    }

    return new Promise((resolve, reject) => {
      if (files.length > 0) {
        resolve(files);
      } else {
        reject(new Error('Read file list failed'))
      }
    })
  }
}

function tryConvertExtensionsToMimetypes(list: Array<string>): Array<string> | null {
  if (list == undefined || list.length == 0) {
    Log.w(TAG, 'list is empty')
    return null;
  }
  let mimeTypes = new Array<string>()
  for (let str of list) {
    switch (str) {
      case 'png':
      case 'jpg':
      case 'jpeg':
        if (mimeTypes.indexOf(picker.PhotoViewMIMETypes.IMAGE_TYPE) == -1) {
          mimeTypes.push(picker.PhotoViewMIMETypes.IMAGE_TYPE)
        }
        break;
      case 'txt':
      case 'json':
      default :
        if (mimeTypes.indexOf(DOCUMENT) == -1) {
          mimeTypes.push(DOCUMENT);
        }
        break;
    }
  }
  return mimeTypes;
}

class ResultBuilder{
  success : (result: FileResponse)=>void
  error: (error: Error) =>void

  constructor(success:ESObject , error:ESObject) {
    this.success = success
    this.error = error
  }
}
class ResultsBuilder{
  success : (result: Array<FileResponse>)=>void
  error: (error: Error) =>void

  constructor(success:ESObject , error:ESObject) {
    this.success = success
    this.error = error
  }
}
