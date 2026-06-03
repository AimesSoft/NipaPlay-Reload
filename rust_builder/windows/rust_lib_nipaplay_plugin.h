#ifndef FLUTTER_PLUGIN_RUST_LIB_NIPAPLAY_PLUGIN_H_
#define FLUTTER_PLUGIN_RUST_LIB_NIPAPLAY_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace rust_lib_nipaplay {

class RustLibNipaplayPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit RustLibNipaplayPlugin(flutter::PluginRegistrarWindows* registrar);
  ~RustLibNipaplayPlugin() override;

  RustLibNipaplayPlugin(const RustLibNipaplayPlugin&) = delete;
  RustLibNipaplayPlugin& operator=(const RustLibNipaplayPlugin&) = delete;

 private:
  struct SurfaceState;
  struct TextureBinding;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void EnsureTickThreadRunning();
  void StopTickThread();
  void DisposeSurface(const std::string& surface_id);
  void ReleaseTexture(SurfaceState* state);
  void Tick();

  flutter::PluginRegistrarWindows* registrar_;
  flutter::TextureRegistrar* texture_registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unordered_map<std::string, std::unique_ptr<SurfaceState>> surfaces_;
  std::mutex mutex_;
  std::thread tick_thread_;
  std::atomic<bool> tick_running_{false};
};

}  // namespace rust_lib_nipaplay

#endif  // FLUTTER_PLUGIN_RUST_LIB_NIPAPLAY_PLUGIN_H_
