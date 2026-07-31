/*
 * Copyright (c) 2023 WangBin <wbsecg1 at gmail.com>
 */
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
#ifndef FLUTTER_PLUGIN_FVP_PLUGIN_H_
#define FLUTTER_PLUGIN_FVP_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>
#include <wrl/client.h>
#include <d3d11.h>
#include "mdk/RenderAPI.h"
#include "mdk/Player.h"
#include <memory>
#include <unordered_map>

using namespace MDK_NS;
using namespace Microsoft::WRL;

namespace fvp {

class FvpPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FvpPlugin(flutter::TextureRegistrar* tr, IDXGIAdapter* adapter = nullptr);

  virtual ~FvpPlugin();

  // Disallow copy and assign.
  FvpPlugin(const FvpPlugin&) = delete;
  FvpPlugin& operator=(const FvpPlugin&) = delete;

 private:
  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  flutter::TextureRegistrar* texture_registrar_ = nullptr;

  ComPtr<ID3D11Device> dev_;
  ComPtr<ID3D11DeviceContext> ctx_;
  ComPtr<IDXGIAdapter> adapter_;

  std::unordered_map<int64_t, std::shared_ptr<Player>> players_;
};

}  // namespace fvp

#endif  // FLUTTER_PLUGIN_FVP_PLUGIN_H_
