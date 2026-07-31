// Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_ODID file.

import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { FileTypes } from './GeneratedFileSelectorApi';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '@ohos/flutter_ohos';

const TAG = "FileSelectorUtil";
enum PhotoViewMIMETypes {
  IMAGE_TYPE = 'image/*',
  VIDEO_TYPE = 'video/*',
  IMAGE_VIDEO_TYPE = '*/*',
  INVALID_TYPE = ''
}


const PHOTO_VIEW_MIME_TYPE_MAP = new Map([
  [PhotoViewMIMETypes.IMAGE_TYPE, 'FILTER_MEDIA_TYPE_IMAGE'],
  [PhotoViewMIMETypes.VIDEO_TYPE, 'FILTER_MEDIA_TYPE_VIDEO'],
  [PhotoViewMIMETypes.IMAGE_VIDEO_TYPE, 'FILTER_MEDIA_TYPE_ALL'],
]);


interface  ConfigText {
   action: string;
   type: string;
   parameters: ESObject;
}
export async function photoPickerSelect(option: picker.PhotoSelectOptions, context: common.UIAbilityContext): Promise<ESObject> {
  let config: ConfigText = {
    action: 'ohos.want.action.photoPicker',
    type: 'multipleselect',
    parameters: {
      uri: 'multipleselect',
      maxSelectCount: 5,
      filterMediaType: '*/*'
    },
  }

  if (option.maxSelectNumber != null && option.maxSelectNumber > 0) {
    let select = (option.maxSelectNumber === 1) ? 'singleselect' : 'multipleselect';
    config.type = select;
    config.parameters.uri = select;
    config.parameters.maxSelectCount = option.maxSelectNumber;
  }
  if (option.MIMEType != null && option.MIMEType.length > 0 && PHOTO_VIEW_MIME_TYPE_MAP.has(option.MIMEType)) {
    config.parameters.filterMediaType = PHOTO_VIEW_MIME_TYPE_MAP.get(option.MIMEType);
  }

  try {
    let result = await context.startAbilityForResult(config, {displayId: 1});
    console.log('[picker] result: ' + JSON.stringify(result));
    let uris: ESObject = null;
    let isOrigin: ESObject = null;
    if (result.want?.parameters != null) {
      uris = result.want.parameters['select-item-list'];
      isOrigin = result.want.parameters['isOriginal'];
    }
    let selectResult: ESObject  = new picker.PhotoSelectResult();
    if (result.resultCode === -1) {
      result.resultCode = 0;
      uris = [];
      selectResult = null;
    } else {
      selectResult.photoUris = uris as Array<string>;
      selectResult.isOriginalPhoto = isOrigin as boolean;
    }

    return new Promise<picker.PhotoSelectResult>((resolve, reject) => {
      if (result.resultCode === 0) {
        resolve(selectResult);
      } else {
        console.log('[picker] err: ' + result.resultCode);
        reject(result.resultCode);
      }
    })
  } catch (error) {
    console.log('[picker] error: ' + error);
  }
  return undefined;
}

interface ConfigParameters {
  action: string;
  parameters: ESObject;
}

export async function documentPickerSelect(option: picker.DocumentSelectOptions, context: common.UIAbilityContext): Promise<ESObject> {
  let config: ConfigParameters = {
    action: 'ohos.want.action.OPEN_FILE',
    parameters: {
      startMode: 'choose',
      key_file_suffix_filter: [".txt", ".json"],
      key_pick_dir_path: ''

    }
  }

  if (option.maxSelectNumber != null && option.maxSelectNumber > 0) {
    config.parameters.key_pick_num = option.maxSelectNumber;
  }

  if (option.defaultFilePathUri != null) {
      config.parameters.key_pick_dir_path = option.defaultFilePathUri;
    }

    let file_suffix: string[] = [];
    if (option.fileSuffixFilters != null) {
      for (let extensionType of option.fileSuffixFilters) {
        file_suffix.push("." + extensionType);
      }
      config.parameters.key_file_suffix_filter = file_suffix;
    }

  try {
    let result = await context.startAbilityForResult(config, {displayId: 1});
    let select_item_list: ESObject = result.want?.parameters?.['ability.params.stream'];
    let uris: ESObject = select_item_list.valueOf();

    return new Promise<ESObject>((resolve, reject) => {
      if (result.resultCode === 0) {
        resolve(uris);
      } else {
        console.error('[picker] err: ' + result.resultCode +  "message" + result.want?.parameters?.message);
        reject(result.resultCode);
      }
    })
  } catch (err) {
    console.error(`Invoke documentViewPicker.select failed, code is ${err.code}, message is ${err.message}`);
  }
  return undefined;
}

export async function filePicker(initialDirectory: string, allowedTypes: FileTypes, selectorNumber?: number): Promise<ESObject> {
  let documentSelectOptions = new picker.DocumentSelectOptions();
  documentSelectOptions.defaultFilePathUri = initialDirectory;
  if (selectorNumber != undefined) {
    documentSelectOptions.maxSelectNumber = selectorNumber;
  }
  let file_suffix: Array<string> = [];
  if (allowedTypes.extensions != null) {
    for (let extensionType of allowedTypes.extensions) {
      file_suffix.push("." + extensionType);
    }
  }
  documentSelectOptions.fileSuffixFilters = file_suffix;
  try {
    const documentViewPicker = new picker.DocumentViewPicker();
    let documentSelectResult = await documentViewPicker.select(documentSelectOptions);
    Log.i(TAG, "documentViewPicker select file succeed.");
    return new Promise<ESObject> ((resolve) => {resolve(documentSelectResult)});
  } catch (err) {
    Log.e(TAG, "documentViewPicker select file failed.")
    return new Promise<ESObject> ((resolve) => {resolve(undefined)});
  }
}
