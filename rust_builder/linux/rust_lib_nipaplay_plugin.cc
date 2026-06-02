#include "include/rust_lib_nipaplay/rust_lib_nipaplay_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <algorithm>
#include <memory>
#include <mutex>
#include <new>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

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
                               float opacity,
                               const char* custom_font_family,
                               const char* custom_font_file_path);
uint8_t next2_engine_reset_scene(uint64_t handle);
uint8_t next2_engine_copy_bgra_frame(uint64_t handle,
                                     uint8_t* out_pixels,
                                     uint32_t out_len,
                                     uint32_t* out_width,
                                     uint32_t* out_height);
}

#define RUST_LIB_NIPAPLAY_PLUGIN(obj)                                      \
  (G_TYPE_CHECK_INSTANCE_CAST((obj), rust_lib_nipaplay_plugin_get_type(), \
                              RustLibNipaplayPlugin))

constexpr char kChannelName[] = "nipaplay/next2_texture";
constexpr int kMaxDimension = 16384;
constexpr int kFallbackSize = 512;

struct SurfaceState;
using SurfaceMap = std::unordered_map<std::string, std::unique_ptr<SurfaceState>>;
using SurfaceMutex = std::mutex;

struct SurfaceState {
  std::string surface_id;
  FlPixelBufferTexture* texture = nullptr;
  FlTexture* texture_base = nullptr;
  int64_t texture_id = -1;
  uint64_t engine_handle = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  std::vector<uint8_t> rgba;
  std::mutex lock;
};

typedef struct _Next2PixelBufferTexture Next2PixelBufferTexture;
typedef struct _Next2PixelBufferTextureClass Next2PixelBufferTextureClass;

struct _Next2PixelBufferTexture {
  FlPixelBufferTexture parent_instance;
  SurfaceState* state = nullptr;
};

struct _Next2PixelBufferTextureClass {
  FlPixelBufferTextureClass parent_class;
};

G_DEFINE_TYPE(Next2PixelBufferTexture,
              next2_pixel_buffer_texture,
              fl_pixel_buffer_texture_get_type())

struct _RustLibNipaplayPlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  FlPluginRegistrar* registrar;
  FlTextureRegistrar* texture_registrar;
  SurfaceMap surfaces;
  SurfaceMutex surfaces_lock;
  guint tick_source = 0;
};

G_DEFINE_TYPE(RustLibNipaplayPlugin,
              rust_lib_nipaplay_plugin,
              g_object_get_type())

static std::optional<int64_t> ToInt64(FlValue* value) {
  if (value == nullptr) {
    return std::nullopt;
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(value);
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<int64_t>(fl_value_get_float(value));
  }
  if (fl_value_get_type(value) == FL_VALUE_TYPE_STRING) {
    const gchar* text = fl_value_get_string(value);
    if (text == nullptr) {
      return std::nullopt;
    }
    gchar* endptr = nullptr;
    const gint64 parsed = g_ascii_strtoll(text, &endptr, 10);
    if (endptr == text) {
      return std::nullopt;
    }
    return parsed;
  }
  return std::nullopt;
}

static int ReadClampedInt(FlValue* map,
                          const char* key,
                          int fallback,
                          int min_value,
                          int max_value) {
  FlValue* v = fl_value_lookup_string(map, key);
  auto parsed = ToInt64(v);
  if (!parsed.has_value()) {
    return std::clamp(fallback, min_value, max_value);
  }
  return std::clamp(static_cast<int>(*parsed), min_value, max_value);
}

static uint64_t ReadU64(FlValue* map, const char* key, uint64_t fallback = 0) {
  FlValue* v = fl_value_lookup_string(map, key);
  auto parsed = ToInt64(v);
  if (!parsed.has_value() || *parsed <= 0) {
    return fallback;
  }
  return static_cast<uint64_t>(*parsed);
}

static float ReadFloat(FlValue* map, const char* key, float fallback) {
  FlValue* v = fl_value_lookup_string(map, key);
  if (v == nullptr) {
    return fallback;
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) {
    return static_cast<float>(fl_value_get_float(v));
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return static_cast<float>(fl_value_get_int(v));
  }
  return fallback;
}

static uint8_t ReadU8(FlValue* map, const char* key, uint8_t fallback) {
  FlValue* v = fl_value_lookup_string(map, key);
  auto parsed = ToInt64(v);
  if (!parsed.has_value()) {
    return fallback;
  }
  return static_cast<uint8_t>(std::clamp<int64_t>(*parsed, 0, 255));
}

static std::string ReadSurfaceId(FlValue* map) {
  FlValue* v = fl_value_lookup_string(map, "surfaceId");
  if (v == nullptr) {
    return "default";
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
    const gchar* s = fl_value_get_string(v);
    if (s != nullptr && s[0] != '\0') {
      return std::string(s);
    }
  }
  auto parsed = ToInt64(v);
  if (parsed.has_value()) {
    return std::to_string(*parsed);
  }
  return "default";
}

static gboolean next2_texture_copy_pixels(FlPixelBufferTexture* texture,
                                          const guint8** out_buffer,
                                          guint32* width,
                                          guint32* height,
                                          GError** error) {
  (void)error;
  auto* next2_texture = reinterpret_cast<Next2PixelBufferTexture*>(texture);
  SurfaceState* state = next2_texture->state;
  if (!state) {
    return FALSE;
  }
  std::lock_guard<std::mutex> guard(state->lock);
  if (state->rgba.empty() || state->width == 0 || state->height == 0) {
    return FALSE;
  }
  *out_buffer = state->rgba.data();
  *width = state->width;
  *height = state->height;
  return TRUE;
}

static void next2_pixel_buffer_texture_class_init(
    Next2PixelBufferTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = next2_texture_copy_pixels;
}

static void next2_pixel_buffer_texture_init(Next2PixelBufferTexture* self) {
  self->state = nullptr;
}

static FlPixelBufferTexture* create_pixel_texture(SurfaceState* state) {
  auto* texture = reinterpret_cast<Next2PixelBufferTexture*>(
      g_object_new(next2_pixel_buffer_texture_get_type(), nullptr));
  texture->state = state;
  return FL_PIXEL_BUFFER_TEXTURE(texture);
}

static gboolean tick_cb(gpointer user_data) {
  RustLibNipaplayPlugin* self = RUST_LIB_NIPAPLAY_PLUGIN(user_data);
  std::lock_guard<std::mutex> lock(self->surfaces_lock);
  for (auto& kv : self->surfaces) {
    SurfaceState* state = kv.second.get();
    if (state->engine_handle == 0 || state->texture_id < 0) {
      continue;
    }
    if (!next2_engine_poll_frame_ready(state->engine_handle)) {
      continue;
    }
    std::lock_guard<std::mutex> guard(state->lock);
    if (state->rgba.empty() || state->width == 0 || state->height == 0) {
      continue;
    }
    uint32_t out_w = 0;
    uint32_t out_h = 0;
    const uint8_t ok = next2_engine_copy_bgra_frame(
        state->engine_handle, state->rgba.data(),
        static_cast<uint32_t>(state->rgba.size()), &out_w, &out_h);
    if (ok == 0 || out_w == 0 || out_h == 0) {
      continue;
    }
    state->width = out_w;
    state->height = out_h;
    fl_texture_registrar_mark_texture_frame_available(
        self->texture_registrar, state->texture_base);
  }
  return TRUE;
}

static void dispose_surface(RustLibNipaplayPlugin* self,
                            const std::string& surface_id) {
  std::unique_ptr<SurfaceState> removed;
  {
    std::lock_guard<std::mutex> lock(self->surfaces_lock);
    auto it = self->surfaces.find(surface_id);
    if (it == self->surfaces.end()) {
      return;
    }
    removed = std::move(it->second);
    self->surfaces.erase(it);
  }
  if (removed->texture_base) {
    fl_texture_registrar_unregister_texture(self->texture_registrar,
                                            removed->texture_base);
  }
  if (removed->texture) {
    g_object_unref(removed->texture);
  }
  if (removed->engine_handle != 0) {
    next2_engine_dispose(removed->engine_handle);
  }
}

static void handle_method_call(RustLibNipaplayPlugin* self,
                               FlMethodCall* method_call) {
  FlValue* args = fl_method_call_get_args(method_call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_error_response_new("invalid_arguments", "Arguments must be map", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "getTextureInfo") == 0) {
    const std::string surface_id = ReadSurfaceId(args);
    const uint32_t width = static_cast<uint32_t>(
        ReadClampedInt(args, "width", kFallbackSize, 1, kMaxDimension));
    const uint32_t height = static_cast<uint32_t>(
        ReadClampedInt(args, "height", kFallbackSize, 1, kMaxDimension));

    std::lock_guard<std::mutex> lock(self->surfaces_lock);
    auto it = self->surfaces.find(surface_id);
    bool is_new_engine = false;
    if (it == self->surfaces.end()) {
      auto created = std::make_unique<SurfaceState>();
      created->surface_id = surface_id;
      created->width = width;
      created->height = height;
      created->engine_handle = next2_engine_create(width, height);
      if (created->engine_handle == 0) {
        g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("engine_create_failed",
                                         "next2_engine_create returned 0", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      created->rgba.resize(static_cast<size_t>(width) * static_cast<size_t>(height) * 4);
      created->texture = create_pixel_texture(created.get());
      created->texture_base = FL_TEXTURE(created->texture);
      if (!fl_texture_registrar_register_texture(self->texture_registrar,
                                                 created->texture_base)) {
        g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
            fl_method_error_response_new("register_texture_failed",
                                         "Failed to register texture", nullptr));
        fl_method_call_respond(method_call, response, nullptr);
        return;
      }
      created->texture_id = fl_texture_get_id(created->texture_base);
      is_new_engine = true;
      it = self->surfaces.emplace(surface_id, std::move(created)).first;
    }
    SurfaceState* state = it->second.get();
    if (state->width != width || state->height != height) {
      const uint8_t ok = next2_engine_resize(state->engine_handle, width, height);
      if (ok == 0) {
        next2_engine_dispose(state->engine_handle);
        state->engine_handle = next2_engine_create(width, height);
        if (state->engine_handle == 0) {
          g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
              fl_method_error_response_new("engine_create_failed",
                                           "next2_engine_create returned 0", nullptr));
          fl_method_call_respond(method_call, response, nullptr);
          return;
        }
      }
      state->width = width;
      state->height = height;
      state->rgba.assign(static_cast<size_t>(width) * static_cast<size_t>(height) * 4, 0);
      is_new_engine = true;
    }

    FlValue* response_map = fl_value_new_map();
    fl_value_set_string_take(response_map, "textureId",
                             fl_value_new_int(state->texture_id));
    fl_value_set_string_take(response_map, "engineHandle",
                             fl_value_new_int(static_cast<int64_t>(state->engine_handle)));
    fl_value_set_string_take(response_map, "width",
                             fl_value_new_int(static_cast<int32_t>(state->width)));
    fl_value_set_string_take(response_map, "height",
                             fl_value_new_int(static_cast<int32_t>(state->height)));
    fl_value_set_string_take(response_map, "isNewEngine",
                             fl_value_new_bool(is_new_engine));
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(response_map));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "setFrame") == 0) {
    const uint64_t handle = ReadU64(args, "engineHandle", 0);
    FlValue* frame_json_v = fl_value_lookup_string(args, "frameJson");
    if (handle == 0 || fl_value_get_type(frame_json_v) != FL_VALUE_TYPE_STRING) {
      g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
          fl_method_error_response_new("invalid_arguments",
                                       "Missing engineHandle/frameJson", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }
    const char* frame_json = fl_value_get_string(frame_json_v);
    const float font_size = ReadFloat(args, "fontSize", 24.0f);
    const float outline_width = ReadFloat(args, "outlineWidth", 1.0f);
    const uint8_t shadow_style = ReadU8(args, "shadowStyle", 1);
    const float opacity = ReadFloat(args, "opacity", 1.0f);
    FlValue* custom_font_family_v = fl_value_lookup_string(args, "customFontFamily");
    FlValue* custom_font_file_path_v = fl_value_lookup_string(args, "customFontFilePath");
    const char* custom_font_family =
        custom_font_family_v != nullptr && fl_value_get_type(custom_font_family_v) == FL_VALUE_TYPE_STRING
            ? fl_value_get_string(custom_font_family_v)
            : "";
    const char* custom_font_file_path =
        custom_font_file_path_v != nullptr && fl_value_get_type(custom_font_file_path_v) == FL_VALUE_TYPE_STRING
            ? fl_value_get_string(custom_font_file_path_v)
            : "";
    const uint8_t ok = next2_engine_set_frame(handle, frame_json, font_size,
                                              outline_width, shadow_style, opacity,
                                              custom_font_family, custom_font_file_path);
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(ok != 0)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "resetScene") == 0) {
    const uint64_t handle = ReadU64(args, "engineHandle", 0);
    const uint8_t ok = next2_engine_reset_scene(handle);
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(fl_value_new_bool(ok != 0)));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  if (g_strcmp0(method, "disposeTexture") == 0) {
    dispose_surface(self, ReadSurfaceId(args));
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
    fl_method_call_respond(method_call, response, nullptr);
    return;
  }

  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  fl_method_call_respond(method_call, response, nullptr);
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  RustLibNipaplayPlugin* self = RUST_LIB_NIPAPLAY_PLUGIN(user_data);
  handle_method_call(self, method_call);
}

static void rust_lib_nipaplay_plugin_dispose(GObject* object) {
  RustLibNipaplayPlugin* self = RUST_LIB_NIPAPLAY_PLUGIN(object);
  if (self->tick_source != 0) {
    g_source_remove(self->tick_source);
    self->tick_source = 0;
  }
  std::vector<std::string> ids;
  {
    std::lock_guard<std::mutex> lock(self->surfaces_lock);
    ids.reserve(self->surfaces.size());
    for (const auto& kv : self->surfaces) {
      ids.push_back(kv.first);
    }
  }
  for (const auto& id : ids) {
    dispose_surface(self, id);
  }

  G_OBJECT_CLASS(rust_lib_nipaplay_plugin_parent_class)->dispose(object);
}

static void rust_lib_nipaplay_plugin_finalize(GObject* object) {
  RustLibNipaplayPlugin* self = RUST_LIB_NIPAPLAY_PLUGIN(object);
  self->surfaces.~SurfaceMap();
  self->surfaces_lock.~SurfaceMutex();
  G_OBJECT_CLASS(rust_lib_nipaplay_plugin_parent_class)->finalize(object);
}

static void rust_lib_nipaplay_plugin_class_init(RustLibNipaplayPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = rust_lib_nipaplay_plugin_dispose;
  G_OBJECT_CLASS(klass)->finalize = rust_lib_nipaplay_plugin_finalize;
}

static void rust_lib_nipaplay_plugin_init(RustLibNipaplayPlugin* self) {
  new (&self->surfaces) SurfaceMap();
  new (&self->surfaces_lock) SurfaceMutex();
  self->channel = nullptr;
  self->registrar = nullptr;
  self->texture_registrar = nullptr;
  self->tick_source = 0;
}

void rust_lib_nipaplay_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  RustLibNipaplayPlugin* self = RUST_LIB_NIPAPLAY_PLUGIN(
      g_object_new(rust_lib_nipaplay_plugin_get_type(), nullptr));
  self->registrar = registrar;
  self->texture_registrar = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlMethodCodec) codec =
      FL_METHOD_CODEC(fl_standard_method_codec_new());
  self->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName, codec);
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            g_object_unref);

  self->tick_source = g_timeout_add(16, tick_cb, self);
}
