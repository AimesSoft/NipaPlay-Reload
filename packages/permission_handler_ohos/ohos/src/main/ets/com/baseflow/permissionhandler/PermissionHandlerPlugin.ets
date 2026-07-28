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
import UIAbility from '@ohos.app.ability.UIAbility';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import MethodChannel from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import StandardMethodCodec from '@ohos/flutter_ohos/src/main/ets/plugin/common/StandardMethodCodec';
import { AppSettingManager } from './AppSettingManager';
import { MethodCallHandlerImpl } from './MethodCallHandlerImpl';
import { PermissionManager } from './PermissionManager';
import { ServiceManager } from './ServiceManager';


const TAG: string = 'PermissionHandlerPlugin';

/**
 * Platform implementation of the permission_handler Flutter plugin.
 *
 * <p>Instantiate this in an add to app scenario to gracefully handle ability and context changes.
 * See {@code com.example.permissionhandlerexample.MainAbility} for an example.
 *
 */
export default class PermissionHandlerPlugin implements FlutterPlugin, AbilityAware {
  private permissionManager: PermissionManager;
  private methodChannel: MethodChannel | null = null;
  private methodCallHandler: MethodCallHandlerImpl | null = null;
  private pluginBinding: AbilityPluginBinding | null = null;

  constructor() {
    this.permissionManager = new PermissionManager();
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.pluginBinding = binding;
    this.startListeningToAbility(this.pluginBinding.getAbility());
  }

  onDetachedFromAbility(): void {
    this.stopListeningToAbility();
  }

  getUniqueClassName(): string {
    return TAG;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    Log.i(TAG, 'onAttachedToEngine');
    this.startListening(binding?.getApplicationContext(), binding?.getBinaryMessenger());
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.stopListening();
  }

  private startListening(context: common.Context, message: BinaryMessenger): void {
    this.methodChannel = new MethodChannel(message, 'flutter.baseflow.com/permissions/methods', StandardMethodCodec.INSTANCE);
    this.methodCallHandler = new MethodCallHandlerImpl(context, new AppSettingManager(),
      this.permissionManager, new ServiceManager());
    this.methodChannel.setMethodCallHandler(this.methodCallHandler);
  }

  private stopListening(): void {
    this.methodChannel?.setMethodCallHandler(null);
    this.methodChannel = null;
    this.methodCallHandler = null;
  }

  private startListeningToAbility(ability: UIAbility): void {
    if (this.methodCallHandler != null) {
      this.methodCallHandler.setAbility(ability);
    }
  }

  private stopListeningToAbility(): void {
    if (this.methodCallHandler != null) {
      this.methodCallHandler.setAbility(null);
    }
  }
}