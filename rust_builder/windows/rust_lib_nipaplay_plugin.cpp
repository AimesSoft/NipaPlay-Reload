#include "rust_lib_nipaplay_plugin.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <Windows.h>

#include <algorithm>
#include <optional>

extern "C" {
uint64_t next2_engine_create(uint32_t width, uint32_t height);
uint8_t next2_engine_resize(uint64_t handle, uint32_t width, uint32_t height);
void next2_engine_dispose(uint64_t handle);
bool next2_engine_poll_frame_ready(uint64_t handle);
uint8_t next2_engine_set_frame(uint64_t handle,
                               const char* frame_json,
                               float font_size,
                               float outline_width,
                               uint8_t shadow_style,
                               float opacity);
uint8_t next2_engine_reset_scene(uint64_t handle);
uint8_t next2_engine_copy_bgra_frame(uint64_t handle,
                                     uint8_t* out_pixels,
                                     uint32_t out_len,
                                     uint32_t* out_width,
                                     uint32_t* out_height);
}

namespace rust_lib_nipaplay {

namespace {

constexpr char kChannelName[] = "nipaplay/next2_texture";
constexpr int kMaxDimension = 16384;
constexpr int kFallbackSize = 512;
constexpr UINT_PTR kTickTimerId = 0x4E32544Bu;  // "N2TK"
constexpr UINT kTickIntervalMs = 16;  // ~60Hz

std::optional<int64_t> ToInt64(const flutter::EncodableValue& value) {
  if (const auto* i32 = std::get_if<int32_t>(&value)) {
    return static_cast<int64_t>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&value)) {
    return *i64;
  }
  if (const auto* d = std::get_if<double>(&value)) {
    return static_cast<int64_t>(*d);
  }
  return std::nullopt;
}

int ReadClampedInt(const flutter::EncodableMap& args,
                   const char* key,
                   int fallback,
                   int min_value,
                   int max_value) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return std::clamp(fallback, min_value, max_value);
  }
  const auto v = ToInt64(it->second);
  if (!v.has_value()) {
    return std::clamp(fallback, min_value, max_value);
  }
  return std::clamp(static_cast<int>(*v), min_value, max_value);
}

uint64_t ReadU64(const flutter::EncodableMap& args,
                 const char* key,
                 uint64_t fallback = 0) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return *i32 > 0 ? static_cast<uint64_t>(*i32) : fallback;
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return *i64 > 0 ? static_cast<uint64_t>(*i64) : fallback;
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    try {
      return std::stoull(*s);
    } catch (...) {
      return fallback;
    }
  }
  return fallback;
}

float ReadFloat(const flutter::EncodableMap& args,
                const char* key,
                float fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* d = std::get_if<double>(&it->second)) {
    return static_cast<float>(*d);
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return static_cast<float>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<float>(*i64);
  }
  return fallback;
}

uint8_t ReadU8(const flutter::EncodableMap& args, const char* key, uint8_t fallback) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  const auto v = ToInt64(it->second);
  if (!v.has_value()) {
    return fallback;
  }
  return static_cast<uint8_t>(std::clamp<int64_t>(*v, 0, 255));
}

std::string ReadSurfaceId(const flutter::EncodableMap& args) {
  const auto it = args.find(flutter::EncodableValue("surfaceId"));
  if (it == args.end()) {
    return "default";
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return s->empty() ? "default" : *s;
  }
  if (const auto v = ToInt64(it->second); v.has_value()) {
    return std::to_string(*v);
  }
  return "default";
}

}  // namespace

struct RustLibNipaplayPlugin::TextureBinding {
  explicit TextureBinding(size_t size = 0) {
    pixel_buffer.buffer = nullptr;
    pixel_buffer.width = 0;
    pixel_buffer.height = 0;
    pixel_buffer.release_context = nullptr;
    pixel_buffer.release_callback = nullptr;
    if (size > 0) {
      rgba.resize(size);
      pixel_buffer.buffer = rgba.data();
    }
  }

  std::vector<uint8_t> rgba;
  FlutterDesktopPixelBuffer pixel_buffer{};
};

struct RustLibNipaplayPlugin::SurfaceState {
  std::string surface_id;
  uint32_t width = 0;
  uint32_t height = 0;
  uint64_t engine_handle = 0;
  int64_t texture_id = -1;
  std::unique_ptr<TextureBinding> binding;
  std::unique_ptr<flutter::TextureVariant> texture_variant;

  SurfaceState(std::string id, uint32_t w, uint32_t h)
      : surface_id(std::move(id)), width(w), height(h) {}
};

void RustLibNipaplayPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<RustLibNipaplayPlugin>(registrar);
  registrar->AddPlugin(std::move(plugin));
}

RustLibNipaplayPlugin::RustLibNipaplayPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar), texture_registrar_(registrar->texture_registrar()) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });

  window_proc_delegate_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
          -> std::optional<LRESULT> {
        return WindowProc(this, hwnd, message, wparam, lparam);
      });
}

RustLibNipaplayPlugin::~RustLibNipaplayPlugin() {
  HWND hwnd = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    StopTickTimerLocked(hwnd);
  }

  if (window_proc_delegate_id_ >= 0) {
    registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_delegate_id_);
  }

  std::vector<uint64_t> handles;
  std::vector<int64_t> texture_ids;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& kv : surfaces_) {
      if (kv.second->engine_handle != 0) {
        handles.push_back(kv.second->engine_handle);
      }
      if (kv.second->texture_id >= 0) {
        texture_ids.push_back(kv.second->texture_id);
      }
    }
    surfaces_.clear();
  }
  for (auto id : texture_ids) {
    texture_registrar_->UnregisterTexture(id, []() {});
  }
  for (auto handle : handles) {
    next2_engine_dispose(handle);
  }
}

void RustLibNipaplayPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (!method_call.arguments()) {
    result->Error("invalid_arguments", "Missing arguments");
    return;
  }
  const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_arguments", "Arguments must be a map");
    return;
  }

  if (method_call.method_name() == "getTextureInfo") {
    const std::string surface_id = ReadSurfaceId(*args);
    const uint32_t width = static_cast<uint32_t>(
        ReadClampedInt(*args, "width", kFallbackSize, 1, kMaxDimension));
    const uint32_t height = static_cast<uint32_t>(
        ReadClampedInt(*args, "height", kFallbackSize, 1, kMaxDimension));
    HWND hwnd = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;

    std::lock_guard<std::mutex> lock(mutex_);
    auto it = surfaces_.find(surface_id);
    bool is_new_engine = false;
    if (it == surfaces_.end()) {
      auto created = std::make_unique<SurfaceState>(surface_id, width, height);
      created->engine_handle = next2_engine_create(width, height);
      if (created->engine_handle == 0) {
        result->Error("engine_create_failed", "next2_engine_create returned 0");
        return;
      }
      is_new_engine = true;
      it = surfaces_.emplace(surface_id, std::move(created)).first;
    }
    SurfaceState* state = it->second.get();

    if (state->engine_handle == 0) {
      state->engine_handle = next2_engine_create(width, height);
      if (state->engine_handle == 0) {
        result->Error("engine_create_failed", "next2_engine_create returned 0");
        return;
      }
      is_new_engine = true;
    } else if (state->width != width || state->height != height) {
      const auto ok = next2_engine_resize(state->engine_handle, width, height);
      if (ok == 0) {
        next2_engine_dispose(state->engine_handle);
        state->engine_handle = next2_engine_create(width, height);
        if (state->engine_handle == 0) {
          result->Error("engine_create_failed", "next2_engine_create returned 0");
          return;
        }
      }
      is_new_engine = true;
      state->width = width;
      state->height = height;
      state->binding.reset();
      if (state->texture_id >= 0) {
        texture_registrar_->UnregisterTexture(state->texture_id, []() {});
        state->texture_id = -1;
        state->texture_variant.reset();
      }
    }

    if (state->texture_id < 0 || !state->binding || !state->texture_variant) {
      const size_t size = static_cast<size_t>(state->width) *
                          static_cast<size_t>(state->height) * 4;
      state->binding = std::make_unique<TextureBinding>(size);
      auto* binding = state->binding.get();
      state->texture_variant = std::make_unique<flutter::TextureVariant>(
          flutter::PixelBufferTexture(
              [binding](size_t, size_t) -> const FlutterDesktopPixelBuffer* {
                return &binding->pixel_buffer;
              }));
      state->binding->pixel_buffer.width = state->width;
      state->binding->pixel_buffer.height = state->height;
      state->binding->pixel_buffer.buffer = state->binding->rgba.data();
      state->texture_id =
          texture_registrar_->RegisterTexture(state->texture_variant.get());
      is_new_engine = true;
    }

    EnsureTickTimerLocked(hwnd);

    flutter::EncodableMap response;
    response[flutter::EncodableValue("textureId")] =
        flutter::EncodableValue(state->texture_id);
    response[flutter::EncodableValue("engineHandle")] =
        flutter::EncodableValue(static_cast<int64_t>(state->engine_handle));
    response[flutter::EncodableValue("width")] =
        flutter::EncodableValue(static_cast<int32_t>(state->width));
    response[flutter::EncodableValue("height")] =
        flutter::EncodableValue(static_cast<int32_t>(state->height));
    response[flutter::EncodableValue("isNewEngine")] =
        flutter::EncodableValue(is_new_engine);
    result->Success(flutter::EncodableValue(response));
    return;
  }

  if (method_call.method_name() == "setFrame") {
    const uint64_t handle = ReadU64(*args, "engineHandle", 0);
    const auto it_json = args->find(flutter::EncodableValue("frameJson"));
    if (handle == 0 || it_json == args->end()) {
      result->Error("invalid_arguments", "Missing engineHandle/frameJson");
      return;
    }
    const auto* frame_json = std::get_if<std::string>(&it_json->second);
    if (!frame_json) {
      result->Error("invalid_arguments", "frameJson must be string");
      return;
    }
    const float font_size = ReadFloat(*args, "fontSize", 24.0f);
    const float outline_width = ReadFloat(*args, "outlineWidth", 1.0f);
    const uint8_t shadow_style = ReadU8(*args, "shadowStyle", 1);
    const float opacity = ReadFloat(*args, "opacity", 1.0f);
    const uint8_t ok = next2_engine_set_frame(handle, frame_json->c_str(),
                                              font_size, outline_width,
                                              shadow_style, opacity);
    result->Success(flutter::EncodableValue(ok != 0));
    return;
  }

  if (method_call.method_name() == "resetScene") {
    const uint64_t handle = ReadU64(*args, "engineHandle", 0);
    if (handle == 0) {
      result->Error("invalid_arguments", "Missing engineHandle");
      return;
    }
    const uint8_t ok = next2_engine_reset_scene(handle);
    result->Success(flutter::EncodableValue(ok != 0));
    return;
  }

  if (method_call.method_name() == "disposeTexture") {
    const std::string surface_id = ReadSurfaceId(*args);
    DisposeSurface(surface_id);
    result->Success(flutter::EncodableValue());
    return;
  }

  result->NotImplemented();
}

void RustLibNipaplayPlugin::DisposeSurface(const std::string& surface_id) {
  std::unique_ptr<SurfaceState> removed;
  HWND hwnd = registrar_->GetView() ? registrar_->GetView()->GetNativeWindow() : nullptr;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = surfaces_.find(surface_id);
    if (it == surfaces_.end()) {
      return;
    }
    removed = std::move(it->second);
    surfaces_.erase(it);
    if (surfaces_.empty()) {
      StopTickTimerLocked(hwnd);
    }
  }
  if (removed->texture_id >= 0) {
    texture_registrar_->UnregisterTexture(removed->texture_id, []() {});
  }
  if (removed->engine_handle != 0) {
    next2_engine_dispose(removed->engine_handle);
  }
}

void RustLibNipaplayPlugin::Tick() {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& kv : surfaces_) {
    SurfaceState* state = kv.second.get();
    if (state->engine_handle == 0 || state->texture_id < 0 || !state->binding) {
      continue;
    }
    if (!next2_engine_poll_frame_ready(state->engine_handle)) {
      continue;
    }
    uint32_t out_w = 0;
    uint32_t out_h = 0;
    const uint32_t out_len =
        static_cast<uint32_t>(state->binding->rgba.size());
    const uint8_t ok = next2_engine_copy_bgra_frame(
        state->engine_handle, state->binding->rgba.data(), out_len, &out_w, &out_h);
    if (ok == 0 || out_w == 0 || out_h == 0) {
      continue;
    }
    state->binding->pixel_buffer.width = out_w;
    state->binding->pixel_buffer.height = out_h;
    texture_registrar_->MarkTextureFrameAvailable(state->texture_id);
  }
}

void RustLibNipaplayPlugin::EnsureTickTimerLocked(HWND hwnd) {
  if (tick_timer_active_ || hwnd == nullptr) {
    return;
  }
  if (::SetTimer(hwnd, kTickTimerId, kTickIntervalMs, nullptr) != 0) {
    tick_timer_active_ = true;
  }
}

void RustLibNipaplayPlugin::StopTickTimerLocked(HWND hwnd) {
  if (!tick_timer_active_) {
    return;
  }
  if (hwnd != nullptr) {
    ::KillTimer(hwnd, kTickTimerId);
  }
  tick_timer_active_ = false;
}

std::optional<LRESULT> RustLibNipaplayPlugin::WindowProc(
    RustLibNipaplayPlugin* self,
    HWND hwnd,
    UINT message,
    WPARAM wparam,
    LPARAM lparam) {
  if (message == WM_TIMER && wparam == kTickTimerId) {
    self->Tick();
    return 0;
  }
  return std::nullopt;
}

}  // namespace rust_lib_nipaplay
