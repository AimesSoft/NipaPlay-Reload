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

import common from '@ohos.app.ability.common';
import { ErrorCallback } from './ErrorCallback';
import PermissionConstants from './PermissionConstants';
import locationManager from '@ohos.geoLocationManager';
import bluetoothManager from '@ohos.bluetoothManager';
import sim from '@ohos.telephony.sim';

export class ServiceManager {
  checkServiceStatus(permission: number, context: common.Context,
    successCallback: SuccessCallback, errorCallback: ErrorCallback): void {
    if (permission == PermissionConstants.PERMISSION_GROUP_LOCATION ||
      permission == PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS ||
      permission == PermissionConstants.PERMISSION_GROUP_LOCATION_WHEN_IN_USE) {
      successCallback.onSuccess(this.isLocationServiceEnable()
        ? PermissionConstants.SERVICE_STATUS_ENABLED : PermissionConstants.SERVICE_STATUS_DISABLED);
      return;
    }
    if (permission == PermissionConstants.PERMISSION_GROUP_BLUETOOTH) {
      successCallback.onSuccess(this.isBluetoothServiceEnable()
        ? PermissionConstants.SERVICE_STATUS_ENABLED : PermissionConstants.SERVICE_STATUS_DISABLED);
      return;
    }
    if (permission == PermissionConstants.PERMISSION_GROUP_PHONE) {
      try {
        sim.getSimState(0).then((state) => {
          if (state == sim.SimState.SIM_STATE_READY) {
            successCallback.onSuccess(PermissionConstants.SERVICE_STATUS_ENABLED);
            return;
          }
          sim.getSimState(1).then((stateSimTwo) => {
            if (stateSimTwo == sim.SimState.SIM_STATE_READY) {
              successCallback.onSuccess(PermissionConstants.SERVICE_STATUS_ENABLED);
              return;
            }
            successCallback.onSuccess(PermissionConstants.SERVICE_STATUS_DISABLED);
          });
        });
      } catch (error) {
        successCallback.onSuccess(PermissionConstants.SERVICE_STATUS_DISABLED);
      }
      return;
    }
    if (permission == PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS) {
      successCallback.onSuccess(PermissionConstants.SERVICE_STATUS_DISABLED);
      return;
    }
    successCallback.onSuccess(PermissionConstants.SERVICE_STATUS_NOT_APPLICABLE);
  }

  private isLocationServiceEnable(): boolean {
    try {
      return locationManager.isLocationEnabled();
    } catch (error) {
      return false;
    }
  }

  private isBluetoothServiceEnable(): boolean {
    try {
      return bluetoothManager.getState() == bluetoothManager.BluetoothState.STATE_ON;
    } catch (error) {
      return false;
    }
  }
}

export interface SuccessCallback {
  onSuccess(serviceStatus: number): void;
}