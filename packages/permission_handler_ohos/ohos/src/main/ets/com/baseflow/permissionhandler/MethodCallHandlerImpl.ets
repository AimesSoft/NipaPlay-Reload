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

import { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import common from '@ohos.app.ability.common';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { AppSettingManager } from './AppSettingManager';
import PermissionConstants from './PermissionConstants';
import { PermissionManager } from './PermissionManager';
import { ServiceManager } from './ServiceManager';
import UIAbility from '@ohos.app.ability.UIAbility';
import ArrayList from '@ohos.util.ArrayList';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';

export class MethodCallHandlerImpl implements MethodCallHandler {
  private applicationContext: common.Context;
  private permissionManager: PermissionManager;
  private appSettingManager: AppSettingManager;
  private serviceManager: ServiceManager;
  private ability: UIAbility | null = null;

  public constructor(applicationContext: common.Context, appSettingManager: AppSettingManager,
    permissionManager: PermissionManager, serviceManager: ServiceManager) {
    this.applicationContext = applicationContext;
    this.appSettingManager = appSettingManager;
    this.permissionManager = permissionManager;
    this.serviceManager = serviceManager;
  }

  public setAbility(ability: UIAbility | null): void {
    this.ability = ability;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'checkServiceStatus':
        let permission: number = call.args;
        this.serviceManager.checkServiceStatus(permission, this.applicationContext, {
          onSuccess: (serviceStatus: number) => {
            result.success(serviceStatus);
          }
        } as ESObject, {
          onError: (errorCode: string, errorDescription: string) => {
            result.error(errorCode, errorDescription, null);
          }
        } as ESObject);
      break
      case 'checkPermissionStatus':
        let checkedPermission: number = call.args;
        Log.d(PermissionConstants.LOG_TAG, 'MethodCall checkPermissionStatus args=' + checkedPermission);
        this.permissionManager.checkPermissionStatus(checkedPermission, this.applicationContext, {
          onSuccess : (permissionStatus: number) => {
            Log.d(PermissionConstants.LOG_TAG, 'MethodCall checkPermissionStatus onSuccess status=' + permissionStatus);
            result.success(permissionStatus);
          }
        } as ESObject);
      break;
      case 'requestPermissions':
        let permissions: ArrayList<number> = call.args;
        this.permissionManager.requestPermissions(permissions, this.ability as UIAbility, {
          onSuccess : (results:  Map<number, number>) => {
            result.success(results);
          }
        } as ESObject, {
          onError: (errorCode: string, errorDescription: string) => {
            result.error(errorCode, errorDescription, null);
          }
        } as ESObject);
      break;
      case 'shouldShowRequestPermissionRationale':
        let showShowPermission: number = call.args;
        this.permissionManager.shouldShowRequestPermissionRationale(showShowPermission, {
          onSuccess : (isShow: boolean) => {
            result.success(isShow);
          }
        } as ESObject, {
          onError: (errorCode: string, errorDescription: string) => {
            result.error(errorCode, errorDescription, null);
          }
        } as ESObject);
      break;
      case 'openAppSettings':
        this.appSettingManager.openAppSettings(this.applicationContext, this.ability, {
          onSuccess: (isSuccess: boolean) => {
            result.success(isSuccess)
          }
        } as ESObject, {
          onError: (errorCode: string, errorDescription: string) => {
            result.error(errorCode, errorDescription, null);
          }
        } as ESObject);
      break;
      default:
      result.notImplemented();
      break;
    }
  }
}
