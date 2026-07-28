/*
 * Copyright (C) 2024 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0.
 */

import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
} from '@ohos/flutter_ohos';
import { Context } from '@ohos.abilityAccessCtrl';
import window from '@ohos.window';

import { IsEnabledMessage, ToggleMessage, WakelockApi } from './WakelockApi';

export default class WakelockPlugin extends WakelockApi
  implements FlutterPlugin, AbilityAware {
  private context: Context | null = null;

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  async toggle(message: ToggleMessage): Promise<void> {
    if (this.context === null) {
      return;
    }
    const mainWindow = await window.getLastWindow(this.context);
    await mainWindow.setWindowKeepScreenOn(message.getEnable());
  }

  async isEnabled(): Promise<IsEnabledMessage> {
    if (this.context === null) {
      return new IsEnabledMessage(false);
    }
    const mainWindow = await window.getLastWindow(this.context);
    return new IsEnabledMessage(mainWindow.getWindowProperties().isKeepScreenOn);
  }

  getUniqueClassName(): string {
    return 'WakelockPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    WakelockApi.setup(binding.getBinaryMessenger(), this);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    WakelockApi.setup(binding.getBinaryMessenger(), null);
  }
}
