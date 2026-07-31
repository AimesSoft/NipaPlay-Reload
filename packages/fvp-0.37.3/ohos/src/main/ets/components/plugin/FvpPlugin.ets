/*
 * Copyright (c) 2026 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import {
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  SurfaceTextureEntry,
} from '@ohos/flutter_ohos';
import fvpNative from 'libfvp.so';

const TAG = 'FvpPlugin';

/** FvpPlugin */
export default class FvpPlugin implements FlutterPlugin, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private binding: FlutterPluginBinding | null = null;
  private textures: Map<number, SurfaceTextureEntry> = new Map();

  getUniqueClassName(): string {
    return 'FvpPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.binding = binding;
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'fvp');
    this.channel.setMethodCallHandler(this);
    fvpNative.nativeSetResourceManager(binding.getApplicationContext().resourceManager);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.textures.forEach((_entry, texId) => {
      fvpNative.nativeSetSurface(0, texId, 0, 0, 0);
    });
    this.textures.clear();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.binding = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'CreateRT') {
      const args = call.args as Map<string, number>;
      const handle: number = args.get('player') as number;
      const width: number = args.get('width') as number;
      const height: number = args.get('height') as number;

      const textureRegistry = this.binding?.getTextureRegistry();
      if (!textureRegistry) {
        result.error('NO_TEXTURE_REGISTRY', 'TextureRegistry not available', null);
        return;
      }

      const texId = textureRegistry.getTextureId();
      const entry = textureRegistry.registerTexture(texId);
      const surfaceId = entry.getSurfaceId();
      textureRegistry.setTextureBufferSize(texId, width, height);

      fvpNative.nativeSetSurface(handle, texId, surfaceId, width, height);

      this.textures.set(texId, entry);
      result.success(texId);
    } else if (call.method === 'ReleaseRT') {
      const args = call.args as Map<string, number>;
      const texId: number = args.get('texture') as number;

      fvpNative.nativeSetSurface(0, texId, 0, 0, 0);
      this.binding?.getTextureRegistry()?.unregisterTexture(texId);
      this.textures.delete(texId);
      result.success(null);
    } else if (call.method === 'MixWithOthers') {
      result.success(null);
    } else {
      result.notImplemented();
    }
  }
}
