/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import bundleManager from '@ohos.bundle.bundleManager';
import Want from '@ohos.app.ability.Want';
import { common } from '@kit.AbilityKit';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import PermissionConstants from './PermissionConstants';

/**
 * 与 novary taoyao SettingPage.startSetting（约 119 行）一致：
 * 在 requestPermissionOnSetting 等无法二次拉起时，跳转系统「应用信息」页供用户手动授权（含通知）。
 */
export class OhosApplicationSettingsOpener {
  /**
   * 需传入 UIAbilityContext；基类 Context 无 startAbility，与 AppSettingManager 使用 ability.context 一致。
   */
  static openApplicationInfoPage(uiContext: common.UIAbilityContext): Promise<void> {
    let bundleName: string = '';
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      bundleName = bundleInfo.name;
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      Log.d(PermissionConstants.LOG_TAG, 'openApplicationInfoPage getBundleName failed: ' + msg);
      return Promise.reject(new Error('bundleName unavailable'));
    }
    const want: Want = OhosApplicationSettingsOpener.buildApplicationInfoWant(bundleName);
    return uiContext.startAbility(want);
  }

  private static buildApplicationInfoWant(bundleName: string): Want {
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility',
      uri: 'application_info_entry',
      parameters: {
        pushParams: bundleName
      }
    };
    return want;
  }
}
