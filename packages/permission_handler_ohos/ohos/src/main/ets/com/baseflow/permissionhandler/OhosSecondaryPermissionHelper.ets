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

import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import common from '@ohos.app.ability.common';
import bundleManager from '@ohos.bundle.bundleManager';
import { PermissionRequestResult } from '@kit.AbilityKit';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import PermissionConstants from './PermissionConstants';

/**
 * 与业务工程 PermissionUtil.requestPermissionsEasy / requestPermissionOnSettingEasy 对齐：
 * 首次 requestPermissionsFromUser 未全部授权时，按权限逐个调用 requestPermissionOnSetting 拉起系统二次授权。
 */
export class OhosSecondaryPermissionHelper {
  static getGrantSuccess(result: PermissionRequestResult): boolean {
    if (result.authResults === undefined || result.authResults === null) {
      return false;
    }
    const grantStatus: Array<number> = result.authResults;
    for (let i = 0; i < grantStatus.length; i++) {
      if (grantStatus[i] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return false;
      }
    }
    return true;
  }

  static getTokenId(): number {
    const bundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return bundleInfo.appInfo.accessTokenId;
  }

  static isPermissionGranted(atManager: abilityAccessCtrl.AtManager, tokenId: number,
    permission: Permissions): boolean {
    const status: abilityAccessCtrl.GrantStatus =
      atManager.verifyAccessTokenSync(tokenId, permission);
    return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
  }

  private static getGrantSuccessFromOnSettingResult(
    data: PermissionRequestResult | Array<abilityAccessCtrl.GrantStatus>): boolean {
    let grantStatus: Array<number>;
    if (data instanceof Array) {
      const arr: Array<abilityAccessCtrl.GrantStatus> = data as Array<abilityAccessCtrl.GrantStatus>;
      grantStatus = [];
      for (let i = 0; i < arr.length; i++) {
        grantStatus.push(arr[i] as number);
      }
    } else {
      const pr: PermissionRequestResult = data as PermissionRequestResult;
      if (pr.authResults === undefined || pr.authResults === null) {
        return false;
      }
      grantStatus = pr.authResults;
    }
    for (let i = 0; i < grantStatus.length; i++) {
      if (grantStatus[i] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return false;
      }
    }
    return true;
  }

  /**
   * 二次向用户申请授权（与 PermissionUtil.requestPermissionOnSettingEasy 一致：逐项检查，未授权则拉起 requestPermissionOnSetting）。
   */
  static async requestPermissionOnSettingEasy(
    context: common.Context,
    atManager: abilityAccessCtrl.AtManager,
    permissions: Array<Permissions>
  ): Promise<boolean> {
    const tokenId: number = OhosSecondaryPermissionHelper.getTokenId();
    for (let i = 0; i < permissions.length; i++) {
      const p: Permissions = permissions[i];
      if (OhosSecondaryPermissionHelper.isPermissionGranted(atManager, tokenId, p)) {
        continue;
      }
      try {
        const grantStatus: PermissionRequestResult | Array<abilityAccessCtrl.GrantStatus> =
          await atManager.requestPermissionOnSetting(context, [p]);
        if (!OhosSecondaryPermissionHelper.getGrantSuccessFromOnSettingResult(grantStatus)) {
          return false;
        }
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        Log.d(PermissionConstants.LOG_TAG, 'requestPermissionOnSetting failed: ' + msg);
        return false;
      }
    }
    return true;
  }
}
