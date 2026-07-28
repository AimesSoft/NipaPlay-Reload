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
import ArrayList from '@ohos.util.ArrayList';
import { Callback } from '@ohos.base';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import PermissionConstants from './PermissionConstants';
import { PermissionRequestResult } from '@kit.AbilityKit';

const TAG: string = 'PermissionUtils';

export default class PermissionUtils {
  static parseOhosName(permission: String): number {
    switch (permission) {
      // 读写「全部日历」：READ_WHOLE_CALENDAR / WRITE_WHOLE_CALENDAR（与 READ_CALENDAR/WRITE_CALENDAR 仅当前应用账户下日历，范围不同）
      case 'ohos.permission.WRITE_WHOLE_CALENDAR':
        return PermissionConstants.PERMISSION_GROUP_CALENDAR_WRITE_ONLY;
      case 'ohos.permission.READ_WHOLE_CALENDAR':
      case 'ohos.permission.WRITE_WHOLE_CALENDAR':
        return PermissionConstants.PERMISSION_GROUP_CALENDAR_FULL_ACCESS;
      case 'ohos.permission.WRITE_CALENDAR':
        return PermissionConstants.PERMISSION_GROUP_CALENDAR_WRITE_ONLY;
      case 'ohos.permission.WRITE_CALENDAR':
      case 'ohos.permission.READ_CALENDAR':
        return PermissionConstants.PERMISSION_GROUP_CALENDAR_FULL_ACCESS;
      case 'ohos.permission.READ_CALENDAR':
      case 'ohos.permission.WRITE_CALENDAR':
        return PermissionConstants.PERMISSION_GROUP_CALENDAR;
      case 'ohos.permission.CAMERA':
        return PermissionConstants.PERMISSION_GROUP_CAMERA;
      case 'ohos.permission.READ_CONTACTS':
      case 'ohos.permission.WRITE_CONTACTS':
      // case 'ohos.permission.GET_LOCAL_ACCOUNTS':
        return PermissionConstants.PERMISSION_GROUP_CONTACTS;
      case 'ohos.permission.LOCATION_IN_BACKGROUND':
        return PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS;
      case 'ohos.permission.LOCATION':
      case 'ohos.permission.APPROXIMATELY_LOCATION':
        return PermissionConstants.PERMISSION_GROUP_LOCATION;
      case 'ohos.permission.MICROPHONE':
        return PermissionConstants.PERMISSION_GROUP_MICROPHONE;
      case 'ohos.permission.SET_TELEPHONY_STATE':
      case 'ohos.permission.GET_TELEPHONY_STATE':
      case 'ohos.permission.PLACE_CALL':
      case 'ohos.permission.ANSWER_CALL':
      case 'ohos.permission.READ_CALL_LOG':
      case 'ohos.permission.WRITE_CALL_LOG':
      case 'ohos.permission.CONNECT_CELLULAR_CALL_SERVICE':
      case 'ohos.permission.MANAGE_VOICEMAIL':
        return PermissionConstants.PERMISSION_GROUP_PHONE;
      case 'ohos.permission.READ_HEALTH_DATA':
        return PermissionConstants.PERMISSION_GROUP_SENSORS;
      case 'ohos.permission.RECEIVE_SMS':
      case 'ohos.permission.RECEIVE_WAP_MESSAGES':
      case 'ohos.permission.RECEIVE_MMS':
        return PermissionConstants.PERMISSION_GROUP_SMS;
      case 'ohos.permission.READ_EXTERNAL_STORAGE':
      case 'ohos.permission.WRITE_EXTERNAL_STORAGE':
        return PermissionConstants.PERMISSION_GROUP_STORAGE;
      case 'ohos.permission.MEDIA_LOCATION':
        return PermissionConstants.PERMISSION_GROUP_ACCESS_MEDIA_LOCATION;
      case 'ohos.permission.ACTIVITY_MOTION':
        return PermissionConstants.PERMISSION_GROUP_ACTIVITY_RECOGNITION;
      case 'ohos.permission.MANAGE_EXTERNAL_STORAGE':
        return PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE;
      case 'ohos.permission.SYSTEM_ALERT_WINDOW':
        return PermissionConstants.PERMISSION_GROUP_SYSTEM_ALERT_WINDOW;
      case 'ohos.permission.INSTALL_BUNDLE':
        return PermissionConstants.PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES;
      case 'ohos.permission.ACCESS_NOTIFICATION_POLICY':
        return PermissionConstants.PERMISSION_GROUP_ACCESS_NOTIFICATION_POLICY;
      case 'ohos.permission.USE_BLUETOOTH':
        return PermissionConstants.PERMISSION_GROUP_BLUETOOTH_SCAN;
      case 'ohos.permission.DISCOVER_BLUETOOTH':
        return PermissionConstants.PERMISSION_GROUP_BLUETOOTH_ADVERTISE;
      case 'ohos.permission.MANAGE_BLUETOOTH':
      case 'ohos.permission.ACCESS_BLUETOOTH':
        return PermissionConstants.PERMISSION_GROUP_BLUETOOTH_CONNECT;
      case 'ohos.permission.NOTIFICATION_CONTROLLER':
        return PermissionConstants.PERMISSION_GROUP_NOTIFICATION;
      case 'ohos.permission.GET_WIFI_INFO':
      case 'ohos.permission.SET_WIFI_INFO':
        return PermissionConstants.PERMISSION_GROUP_NEARBY_WIFI_DEVICES;
      case 'ohos.permission.READ_MEDIA':
        return PermissionConstants.PERMISSION_GROUP_AUDIO;
      case 'ohos.permission.READ_IMAGEVIDEO':
      case 'ohos.permission.WRITE_IMAGEVIDEO':
        return PermissionConstants.PERMISSION_GROUP_PHOTOS;
      case 'ohos.permission.SCHEDULE_EXACT_ALARM':
        return PermissionConstants.PERMISSION_GROUP_SCHEDULE_EXACT_ALARM;
      case 'ohos.permission.READ_PASTEBOARD':
        return PermissionConstants.PERMISSION_GROUP_READ_PASTEBOARD;
      default:
        return PermissionConstants.PERMISSION_GROUP_UNKNOWN;
    }
  }

  static hasPermissionInManifest(confirmedPermission: ArrayList<string>, permission: string, callback: Callback<boolean>): void {
    try {
      if (confirmedPermission != null) {
        for (let confirmed of confirmedPermission) {
          if (confirmed == permission) {
            callback(true);
            return;
          }
        }
      }
      bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION)
        .then((bundleInfo) => {
          for (let requestedPermission of bundleInfo.reqPermissionDetails) {
            if (requestedPermission?.name == permission) {
              callback(true);
              return;
            }
          }
          callback(false);
        })
    } catch (e) {
      Log.i(TAG, 'hasPermissionInManifest exception : ' + e);
      callback(false);
    }
  }

  static getRequestPermission(permissions: ArrayList<string>, callback: Callback<ArrayList<string>>): void {
    let permissionNames: ArrayList<string> = new ArrayList();
    try {
      Log.i(TAG, 'getRequestPermission before getBundleInfoForSelf');
      bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION)
        .then((bundleInfo) => {
          Log.i(TAG, 'getRequestPermission getBundleInfoForSelf then');
          for (let requestedPermission of bundleInfo.reqPermissionDetails) {
            if (permissions.has(requestedPermission.name)) {
              permissionNames.add(requestedPermission.name);
            }
          }
          // 不用经过getBundleInfo校验直接返回进行授权因此直接使用permissions
          callback(permissionNames);
        })
        .catch((err: Object) => {
          Log.i(TAG, 'getRequestPermission getBundleInfoForSelf reject: ' + err);
        })
    } catch (e) {
      Log.i(TAG, 'getRequestPermission exception : ' + e);
    }
  }

  static getManifestNames(permission: number, callback: ESObject): void {
    let permissionNames: ArrayList<string> = new ArrayList();
    switch (permission) {
      case PermissionConstants.PERMISSION_GROUP_CALENDAR_WRITE_ONLY:
        let calendarNamesWriteOnly: ArrayList<string> = new ArrayList();
        // 全日历写权限；若仅需应用账户内日历可用 WRITE_CALENDAR（与本工程 module 声明一致时再改）
        calendarNamesWriteOnly.add('ohos.permission.WRITE_WHOLE_CALENDAR');
        PermissionUtils.getRequestPermission(calendarNamesWriteOnly, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_CALENDAR_FULL_ACCESS:
      case PermissionConstants.PERMISSION_GROUP_CALENDAR:
        let calendarNames: ArrayList<string> = new ArrayList();
        // 读写全部日历；READ/WRITE_CALENDAR 为应用账户范围内，语义更窄
        calendarNames.add('ohos.permission.READ_WHOLE_CALENDAR');
        calendarNames.add('ohos.permission.WRITE_WHOLE_CALENDAR');
        PermissionUtils.getRequestPermission(calendarNames, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_CAMERA:
        PermissionUtils.hasPermissionInManifest(permissionNames, 'ohos.permission.CAMERA', (camera) => {
          if (camera) {
            permissionNames.add('ohos.permission.CAMERA');
          }
          callback(permissionNames);
        });
        break;
      case PermissionConstants.PERMISSION_GROUP_CONTACTS:
        let contracts: ArrayList<string> = new ArrayList();
        contracts.add('ohos.permission.READ_CONTACTS');
        contracts.add('ohos.permission.WRITE_CONTACTS');
        // contracts.add('ohos.permission.GET_LOCAL_ACCOUNTS');
        callback(contracts);
        break;
      case PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS:
        let location: ArrayList<string> = new ArrayList();
        location.add('ohos.permission.LOCATION_IN_BACKGROUND');
        PermissionUtils.getRequestPermission(location, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_LOCATION_WHEN_IN_USE:
        let whenInUseLocation: ArrayList<string> = new ArrayList();
        whenInUseLocation.add('ohos.permission.APPROXIMATELY_LOCATION');
        PermissionUtils.getRequestPermission(whenInUseLocation, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_LOCATION:
        let locationGroup: ArrayList<string> = new ArrayList();
        locationGroup.add('ohos.permission.LOCATION');
        locationGroup.add('ohos.permission.APPROXIMATELY_LOCATION');
        PermissionUtils.getRequestPermission(locationGroup, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_SPEECH:
      case PermissionConstants.PERMISSION_GROUP_MICROPHONE:
        let microphone: ArrayList<string> = new ArrayList();
        microphone.add('ohos.permission.MICROPHONE');
        PermissionUtils.getRequestPermission(microphone, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_PHONE:
        let phone: ArrayList<string> = new ArrayList();
        phone.add('ohos.permission.SET_TELEPHONY_STATE');
        phone.add('ohos.permission.GET_TELEPHONY_STATE');
        phone.add('ohos.permission.PLACE_CALL');
        phone.add('ohos.permission.ANSWER_CALL');
        phone.add('ohos.permission.READ_CALL_LOG');
        phone.add('ohos.permission.WRITE_CALL_LOG');
        // phone.add('ohos.permission.CONNECT_CELLULAR_CALL_SERVICE');
        phone.add('ohos.permission.MANAGE_VOICEMAIL');
        callback(phone);
        break;
      case PermissionConstants.PERMISSION_GROUP_SENSORS:
      case PermissionConstants.PERMISSION_GROUP_SENSORS_ALWAYS:
        let sensor: ArrayList<string> = new ArrayList();
        sensor.add('ohos.permission.READ_HEALTH_DATA');
        callback(sensor);
        break;
      case PermissionConstants.PERMISSION_GROUP_SMS:
        let sms: ArrayList<string> = new ArrayList();
        sms.add('ohos.permission.RECEIVE_SMS');
        sms.add('ohos.permission.RECEIVE_WAP_MESSAGES');
        sms.add('ohos.permission.RECEIVE_MMS');
        callback(sms);
        break;
      case PermissionConstants.PERMISSION_GROUP_STORAGE:
        callback(permissionNames);
        break;
      case PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS:
        callback(permissionNames);
        break;
      case PermissionConstants.PERMISSION_GROUP_ACCESS_MEDIA_LOCATION:
        let mediaLocation: ArrayList<string> = new ArrayList();
        mediaLocation.add('ohos.permission.MEDIA_LOCATION');
        PermissionUtils.getRequestPermission(mediaLocation, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_ACTIVITY_RECOGNITION:
        let motion: ArrayList<string> = new ArrayList();
        motion.add('ohos.permission.ACTIVITY_MOTION');
        callback(motion);
        break;
      case PermissionConstants.PERMISSION_GROUP_BLUETOOTH:
        let bluetooth: ArrayList<string> = new ArrayList();
        bluetooth.add('ohos.permission.ACCESS_BLUETOOTH');
        PermissionUtils.getRequestPermission(bluetooth, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE:
        callback(permissionNames);
        break;
      case PermissionConstants.PERMISSION_GROUP_SYSTEM_ALERT_WINDOW:
        callback(permissionNames);
        break;
      case PermissionConstants.PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES:
        let installBundle: ArrayList<string> = new ArrayList();
        installBundle.add('ohos.permission.INSTALL_BUNDLE');
        callback(installBundle);
        break;
      case PermissionConstants.PERMISSION_GROUP_ACCESS_NOTIFICATION_POLICY:
        let policy: ArrayList<string> = new ArrayList();
        policy.add('ohos.permission.ACCESS_NOTIFICATION_POLICY');
        callback(policy);
        break;
      case PermissionConstants.PERMISSION_GROUP_BLUETOOTH_SCAN:
        let bluetoothScan: ArrayList<string> = new ArrayList();
        bluetoothScan.add('ohos.permission.USE_BLUETOOTH');
        callback(bluetoothScan);
        break;
      case PermissionConstants.PERMISSION_GROUP_BLUETOOTH_ADVERTISE:
        let bluetoothDiscover: ArrayList<string> = new ArrayList();
        bluetoothDiscover.add('ohos.permission.DISCOVER_BLUETOOTH');
        callback(bluetoothDiscover);
        break;
      case PermissionConstants.PERMISSION_GROUP_BLUETOOTH_CONNECT:
        let bluetoothConnect: ArrayList<string> = new ArrayList();
        bluetoothConnect.add('ohos.permission.MANAGE_BLUETOOTH');
        bluetoothConnect.add('ohos.permission.ACCESS_BLUETOOTH');
        callback(bluetoothConnect);
        break;
      case PermissionConstants.PERMISSION_GROUP_NOTIFICATION:
        let postNotification: ArrayList<string> = new ArrayList();
        postNotification.add('ohos.permission.NOTIFICATION_CONTROLLER');
        callback(postNotification);
        break;
      case PermissionConstants.PERMISSION_GROUP_NEARBY_WIFI_DEVICES:
        callback(permissionNames);
        break;
      case PermissionConstants.PERMISSION_GROUP_PHOTOS:
      case PermissionConstants.PERMISSION_GROUP_VIDEOS:
        let photosVideos: ArrayList<string> = new ArrayList();
        photosVideos.add('ohos.permission.READ_IMAGEVIDEO');
        photosVideos.add('ohos.permission.WRITE_IMAGEVIDEO');
        PermissionUtils.getRequestPermission(photosVideos, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_AUDIO:
        let media: ArrayList<string> = new ArrayList();
        media.add('ohos.permission.READ_MEDIA');
        PermissionUtils.getRequestPermission(media, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_SCHEDULE_EXACT_ALARM:
        let exactAlarm: ArrayList<string> = new ArrayList();
        exactAlarm.add('ohos.permission.SCHEDULE_EXACT_ALARM');
        callback(permissionNames);
        break;
      case PermissionConstants.PERMISSION_GROUP_READ_PASTEBOARD:
        let readPasteboard: ArrayList<string> = new ArrayList();
        readPasteboard.add('ohos.permission.READ_PASTEBOARD');
        PermissionUtils.getRequestPermission(readPasteboard, callback);
        break;
      case PermissionConstants.PERMISSION_GROUP_MEDIA_LIBRARY:
      case PermissionConstants.PERMISSION_GROUP_REMINDERS:
      case PermissionConstants.PERMISSION_GROUP_UNKNOWN:
        callback(null);
        break;
      default:
        callback(permissionNames);
        break;
    }
  }

  static toPermissionStatus(authResult: number): number {
    if (authResult == -1 || authResult == 2) {
      return PermissionConstants.PERMISSION_STATUS_DENIED;
    }
    return PermissionConstants.PERMISSION_STATUS_GRANTED;
  }

  static updatePermissionShouldShowStatus(permission: number): void {
  }

  static strictestStatus(statuses: Set<PermissionConstants>): number {
    if (statuses.has(PermissionConstants.PERMISSION_STATUS_NEVER_ASK_AGAIN)) {
      return PermissionConstants.PERMISSION_STATUS_NEVER_ASK_AGAIN;
    }
    if (statuses.has(PermissionConstants.PERMISSION_STATUS_RESTRICTED)) {
      return PermissionConstants.PERMISSION_STATUS_RESTRICTED;
    }
    if (statuses.has(PermissionConstants.PERMISSION_STATUS_DENIED)) {
      return PermissionConstants.PERMISSION_STATUS_DENIED;
    }
    if (statuses.has(PermissionConstants.PERMISSION_STATUS_LIMITED)) {
      return PermissionConstants.PERMISSION_STATUS_LIMITED;
    }
    return PermissionConstants.PERMISSION_STATUS_GRANTED;
  }

  static strictestStatusFromTwo(statusA?: PermissionConstants, statusB?: PermissionConstants): number {
    const statuses = new Set<PermissionConstants>();
    if (statusA !== undefined) {
      statuses.add(statusA);
    }
    if (statusB !== undefined) {
      statuses.add(statusB);
    }
    return PermissionUtils.strictestStatus(statuses);
  }
}