#define _CRT_SECURE_NO_WARNINGS
#include "rust_lib_nipaplay_plugin.h"

#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <Windows.h>

#include <algorithm>
#include <optional>
#include <mutex>

extern "C" {
uint64_t next2_engine_create(uint32_t width, uint32_t height);
uint8_t next2_engine_resize(uint64_t handle, uint32_t width, uint32_t height);
void next2_engine_dispose(uint64_t handle);
bool next2_engine_poll_frame_ready(uint64_t handle);
uint8_t next2_engine_create_dxgi_shared_texture(uint64_t handle,
                                                uint32_t width,
                                                uint32_t height,
                                                uintptr_t* out_shared_handle,
                                                uint32_t* out_width,
                                                uint32_t* out_height);
uint8_t next2_engine_set_frame(uint64_t handle,
                               const char* frame_json,
                               float font_size,
                               float outline_width,
                               uint8_t shadow_style,
                               float opacity,
                               const char* custom_font_family,
                               const char* custom_font_file_path);
uint8_t next2_engine_reset_scene(uint64_t handle);
}

namespace rust_lib_nipaplay {

namespace {

constexpr char kChannelName[] = "nipaplay/next2_texture";
constexpr int kMaxDimension = 16384;
constexpr int kFallbackSize = 512;
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

std::string ReadString(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return "";
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    return *s;
  }
  return "";
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
  TextureBinding(uintptr_t raw_shared_handle, uint32_t width, uint32_t height)
      : shared_handle(reinterpret_cast<HANDLE>(raw_shared_handle)),
        descriptor(std::make_unique<FlutterDesktopGpuSurfaceDescriptor>()) {
    descriptor->struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    descriptor->handle = shared_handle;
    descriptor->width = width;
    descriptor->height = height;
    descriptor->visible_width = width;
    descriptor->visible_height = height;
    descriptor->release_context = nullptr;
    descriptor->release_callback = [](void*) {};
    descriptor->format = kFlutterDesktopPixelFormatBGRA8888;
  }

  ~TextureBinding() {
    if (shared_handle != nullptr && shared_handle != INVALID_HANDLE_VALUE) {
      ::CloseHandle(shared_handle);
    }
  }

  TextureBinding(const TextureBinding&) = delete;
  TextureBinding& operator=(const TextureBinding&) = delete;

  HANDLE shared_handle = nullptr;
  std::unique_ptr<FlutterDesktopGpuSurfaceDescriptor> descriptor;
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
}

RustLibNipaplayPlugin::~RustLibNipaplayPlugin() {
  StopTickThread();

  std::vector<std::unique_ptr<SurfaceState>> removed_surfaces;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto& kv : surfaces_) {
      removed_surfaces.push_back(std::move(kv.second));
    }
    surfaces_.clear();
  }
  for (auto& surface : removed_surfaces) {
    ReleaseTexture(surface.get());
    if (surface->engine_handle != 0) {
      next2_engine_dispose(surface->engine_handle);
    }
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
      ReleaseTexture(state);
    }

    if (state->texture_id < 0 || !state->binding || !state->texture_variant) {
      uintptr_t shared_handle = 0;
      uint32_t out_width = state->width;
      uint32_t out_height = state->height;
      const uint8_t ok = next2_engine_create_dxgi_shared_texture(
          state->engine_handle, state->width, state->height, &shared_handle,
          &out_width, &out_height);
      if (ok == 0 || shared_handle == 0) {
        result->Error("texture_create_failed",
                      "next2_engine_create_dxgi_shared_texture failed");
        return;
      }

      state->width = out_width;
      state->height = out_height;
      state->binding =
          std::make_unique<TextureBinding>(shared_handle, state->width, state->height);
      auto* binding = state->binding.get();
      state->texture_variant = std::make_unique<flutter::TextureVariant>(
          flutter::GpuSurfaceTexture(
              kFlutterDesktopGpuSurfaceTypeDxgiSharedHandle,
              [binding](size_t, size_t)
                  -> const FlutterDesktopGpuSurfaceDescriptor* {
                return binding->descriptor.get();
              }));
      state->texture_id =
          texture_registrar_->RegisterTexture(state->texture_variant.get());
      is_new_engine = true;
    }

    EnsureTickThreadRunning();

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
    const std::string custom_font_family = ReadString(*args, "customFontFamily");
    const std::string custom_font_file_path = ReadString(*args, "customFontFilePath");
    const uint8_t ok = next2_engine_set_frame(handle, frame_json->c_str(),
                                              font_size, outline_width,
                                              shadow_style, opacity,
                                              custom_font_family.c_str(),
                                              custom_font_file_path.c_str());
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
  {
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = surfaces_.find(surface_id);
    if (it == surfaces_.end()) {
      return;
    }
    removed = std::move(it->second);
    surfaces_.erase(it);
    if (surfaces_.empty()) {
      StopTickThread();
    }
  }
  if (removed->texture_id >= 0) {
    ReleaseTexture(removed.get());
  }
  if (removed->engine_handle != 0) {
    next2_engine_dispose(removed->engine_handle);
  }
}

void RustLibNipaplayPlugin::ReleaseTexture(SurfaceState* state) {
  if (!state) {
    return;
  }
  if (state->texture_id < 0) {
    state->texture_variant.reset();
    state->binding.reset();
    return;
  }

  struct RetiredTexture {
    std::unique_ptr<flutter::TextureVariant> texture_variant;
    std::unique_ptr<TextureBinding> binding;
  };

  const int64_t texture_id = state->texture_id;
  state->texture_id = -1;
  auto retired = std::make_shared<RetiredTexture>();
  retired->texture_variant = std::move(state->texture_variant);
  retired->binding = std::move(state->binding);
  texture_registrar_->UnregisterTexture(texture_id, [retired]() {});
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
    texture_registrar_->MarkTextureFrameAvailable(state->texture_id);
  }
}

void RustLibNipaplayPlugin::EnsureTickThreadRunning() {
  if (tick_running_.load()) {
    return;
  }
  tick_running_.store(true);
  tick_thread_ = std::thread([this]() {
    while (tick_running_.load()) {
      try {
        Tick();
      } catch (...) {
      }
      ::Sleep(kTickIntervalMs);
    }
  });
}

void RustLibNipaplayPlugin::StopTickThread() {
  if (!tick_running_.load()) {
    return;
  }
  tick_running_.store(false);
  if (tick_thread_.joinable()) {
    tick_thread_.join();
  }
}

}  // namespace rust_lib_nipaplay
