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

export default class PermissionConstants {
  static LOG_TAG: string = 'permission_handler';
  static PERMISSION_CODE: number = 24;
  static PERMISSION_CODE_IGNORE_BATTERY_OPTIMIZATIONS: number = 209;
  static PERMISSION_CODE_MANAGE_EXTERNAL_STORAGE: number = 210;
  static PERMISSION_CODE_SYSTEM_ALERT_WINDOW: number = 211;
  static PERMISSION_CODE_REQUEST_INSTALL_PACKAGES: number = 212;
  static PERMISSION_CODE_ACCESS_NOTIFICATION_POLICY: number = 213;
  static PERMISSION_CODE_SCHEDULE_EXACT_ALARM = 214;

  //PERMISSION_GROUP
  // Deprecated in favor of PERMISSION_GROUP_CALENDAR_WRITE_ONLY and
  // PERMISSION_GROUP_CALENDAR_FULL_ACCESS.
  static PERMISSION_GROUP_CALENDAR: number = 0;
  static PERMISSION_GROUP_CAMERA: number = 1;
  static PERMISSION_GROUP_CONTACTS: number = 2;
  static PERMISSION_GROUP_LOCATION: number = 3;
  static PERMISSION_GROUP_LOCATION_ALWAYS: number = 4;
  static PERMISSION_GROUP_LOCATION_WHEN_IN_USE: number = 5;
  static PERMISSION_GROUP_MEDIA_LIBRARY: number = 6;
  static PERMISSION_GROUP_MICROPHONE: number = 7;
  static PERMISSION_GROUP_PHONE: number = 8;
  static PERMISSION_GROUP_PHOTOS: number = 9;
  static PERMISSION_GROUP_PHOTOS_ADD_ONLY: number = 10;
  static PERMISSION_GROUP_REMINDERS: number = 11;
  static PERMISSION_GROUP_SENSORS: number = 12;
  static PERMISSION_GROUP_SMS: number = 13;
  static PERMISSION_GROUP_SPEECH: number = 14;
  static PERMISSION_GROUP_STORAGE: number = 15;
  static PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS: number = 16;
  static PERMISSION_GROUP_NOTIFICATION: number = 17;
  static PERMISSION_GROUP_ACCESS_MEDIA_LOCATION: number = 18;
  static PERMISSION_GROUP_ACTIVITY_RECOGNITION: number = 19;
  static PERMISSION_GROUP_UNKNOWN: number = 20;
  static PERMISSION_GROUP_BLUETOOTH: number = 21;
  static PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE: number = 22;
  static PERMISSION_GROUP_SYSTEM_ALERT_WINDOW: number = 23;
  static PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES: number = 24;
  static PERMISSION_GROUP_APP_TRACK_TRANSPARENCY: number = 25;
  static PERMISSION_GROUP_CRITICAL_ALERTS: number = 26;
  static PERMISSION_GROUP_ACCESS_NOTIFICATION_POLICY: number = 27;
  static PERMISSION_GROUP_BLUETOOTH_SCAN: number = 28;
  static PERMISSION_GROUP_BLUETOOTH_ADVERTISE: number = 29;
  static PERMISSION_GROUP_BLUETOOTH_CONNECT: number = 30;
  static PERMISSION_GROUP_NEARBY_WIFI_DEVICES: number = 31;
  static PERMISSION_GROUP_VIDEOS: number = 32;
  static PERMISSION_GROUP_AUDIO: number = 33;
  static PERMISSION_GROUP_SCHEDULE_EXACT_ALARM: number = 34;
  static PERMISSION_GROUP_SENSORS_ALWAYS: number = 35;
  static PERMISSION_GROUP_CALENDAR_WRITE_ONLY = 36;
  static PERMISSION_GROUP_CALENDAR_FULL_ACCESS = 37;
  static PERMISSION_GROUP_ASSISTANT = 38;
  static PERMISSION_GROUP_BACKGROUND_REFRESH = 39;
  static PERMISSION_GROUP_READ_PASTEBOARD = 40;

  //PERMISSION_STATUS
  static PERMISSION_STATUS_DENIED: number = 0;
  static PERMISSION_STATUS_GRANTED: number = 1;
  static PERMISSION_STATUS_RESTRICTED: number = 2;
  static PERMISSION_STATUS_LIMITED: number = 3;
  static PERMISSION_STATUS_NEVER_ASK_AGAIN: number = 4;

  //SERVICE_STATUS
  static SERVICE_STATUS_DISABLED: number = 0;
  static SERVICE_STATUS_ENABLED: number = 1;
  static SERVICE_STATUS_NOT_APPLICABLE: number = 2;
}