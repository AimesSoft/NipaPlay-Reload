#include "include/erika_flutter/erika_flutter_plugin.h"

#include <napi/native_api.h>
#include <native_window/external_window.h>

#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <unordered_map>

#include "erika.h"

#include <atomic>

namespace {

struct OhosPlayer {
  ErikaPresenterHandle* presenter = nullptr;
  OHNativeWindow* window = nullptr;
};

std::unordered_map<int64_t, OhosPlayer> g_players;
// Process-wide monotonic ids. Using the presenter pointer as the id let a
// destroyed player's reused allocation collide with a stale ArkTS-side id,
// routing late calls into a brand-new player.
std::atomic<int64_t> g_next_player_id{1};

napi_value Null(napi_env env) {
  napi_value value = nullptr;
  napi_get_null(env, &value);
  return value;
}

napi_value Int64(napi_env env, int64_t value) {
  napi_value result = nullptr;
  napi_create_int64(env, value, &result);
  return result;
}

napi_value Int32(napi_env env, int32_t value) {
  napi_value result = nullptr;
  napi_create_int32(env, value, &result);
  return result;
}

napi_value String(napi_env env, const char* value) {
  napi_value result = nullptr;
  napi_create_string_utf8(env, value == nullptr ? "" : value, NAPI_AUTO_LENGTH, &result);
  return result;
}

int64_t GetInt64(napi_env env, napi_value value) {
  int64_t result = 0;
  napi_get_value_int64(env, value, &result);
  return result;
}

int32_t GetInt32(napi_env env, napi_value value) {
  int32_t result = 0;
  napi_get_value_int32(env, value, &result);
  return result;
}

double GetDouble(napi_env env, napi_value value) {
  double result = 0.0;
  napi_get_value_double(env, value, &result);
  return result;
}

std::string GetString(napi_env env, napi_value value) {
  size_t size = 0;
  napi_get_value_string_utf8(env, value, nullptr, 0, &size);
  std::string result(size, '\0');
  if (size > 0) {
    size_t written = 0;
    result.resize(size + 1);
    napi_get_value_string_utf8(env, value, result.data(), result.size(), &written);
    result.resize(written);
  }
  return result;
}

OhosPlayer* FindPlayer(int64_t player_id) {
  const auto found = g_players.find(player_id);
  return found == g_players.end() ? nullptr : &found->second;
}

void ReleaseWindow(OhosPlayer& player) {
  if (player.presenter != nullptr && player.window != nullptr) {
    erika_presenter_detach_surface(player.presenter);
  }
  if (player.window != nullptr) {
    OH_NativeWindow_DestroyNativeWindow(player.window);
    player.window = nullptr;
  }
}

napi_value NativeCreate(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    return Int64(env, 0);
  }
  ErikaPresenterConfig config = {};
  config.output_mode = GetInt32(env, args[0]);
  config.edr_headroom = static_cast<float>(GetDouble(env, args[1]));
  config.luma_upscaler = GetInt32(env, args[2]);
  config.video_alpha_mode = argc > 3 ? GetInt32(env, args[3]) : 0;
  auto* presenter = erika_presenter_create_with_config(config);
  if (presenter == nullptr) {
    return Int64(env, 0);
  }
  const auto player_id = g_next_player_id.fetch_add(1, std::memory_order_relaxed);
  g_players.emplace(player_id, OhosPlayer{presenter, nullptr});
  return Int64(env, player_id);
}

napi_value NativeLastError(napi_env env, napi_callback_info) {
  char* message = erika_last_error_message();
  napi_value result = String(env, message);
  erika_string_free(message);
  return result;
}

napi_value NativeDestroy(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc == 0) {
    return Null(env);
  }
  const auto player_id = GetInt64(env, args[0]);
  const auto found = g_players.find(player_id);
  if (found != g_players.end()) {
    ReleaseWindow(found->second);
    erika_presenter_destroy(found->second.presenter);
    g_players.erase(found);
  }
  return Null(env);
}

napi_value NativeInvoke(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    return String(env, R"({"ok":false,"status":1,"error":"missing nativeInvoke argument"})");
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return String(env, R"({"ok":false,"status":1,"error":"unknown Erika player"})");
  }
  const std::string method = GetString(env, args[1]);
  const std::string arguments = GetString(env, args[2]);
  char* response = erika_presenter_invoke_json(
      player->presenter, method.c_str(), arguments.c_str());
  napi_value result = String(env, response);
  erika_string_free(response);
  return result;
}

napi_value NativeRegisterSubtitleMemoryFont(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    napi_value result = nullptr;
    napi_create_array_with_length(env, 2, &result);
    napi_set_element(env, result, 0, Int32(env, ErikaStatus_NullPointer));
    napi_set_element(env, result, 1, Int64(env, 0));
    return result;
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  bool is_typed_array = false;
  napi_is_typedarray(env, args[1], &is_typed_array);
  napi_typedarray_type array_type = napi_uint8_array;
  size_t byte_count = 0;
  void* bytes = nullptr;
  napi_value array_buffer = nullptr;
  size_t byte_offset = 0;
  const bool valid_bytes = is_typed_array &&
      napi_get_typedarray_info(
          env, args[1], &array_type, &byte_count, &bytes, &array_buffer, &byte_offset) == napi_ok &&
      (array_type == napi_uint8_array || array_type == napi_uint8_clamped_array);
  uint64_t font_id = 0;
  const auto status = player == nullptr || !valid_bytes
      ? ErikaStatus_NullPointer
      : erika_presenter_register_subtitle_memory_font(
            player->presenter, static_cast<const uint8_t*>(bytes), byte_count, &font_id);
  napi_value result = nullptr;
  napi_create_array_with_length(env, 2, &result);
  napi_set_element(env, result, 0, Int32(env, status));
  napi_set_element(env, result, 1, Int64(env, static_cast<int64_t>(font_id)));
  return result;
}

napi_value NativeAttachSurface(napi_env env, napi_callback_info info) {
  size_t argc = 5;
  napi_value args[5] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 5) {
    return Int32(env, ErikaStatus_NullPointer);
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return Int32(env, ErikaStatus_NullPointer);
  }
  ReleaseWindow(*player);
  const auto surface_id = static_cast<uint64_t>(GetInt64(env, args[1]));
  OHNativeWindow* window = nullptr;
  const int32_t create_status =
      OH_NativeWindow_CreateNativeWindowFromSurfaceId(surface_id, &window);
  if (create_status != 0 || window == nullptr) {
    return Int32(env, ErikaStatus_PlayerError);
  }
  const uint32_t width = static_cast<uint32_t>(GetInt32(env, args[2]));
  const uint32_t height = static_cast<uint32_t>(GetInt32(env, args[3]));
  const double scale = GetDouble(env, args[4]);
  const auto status = erika_presenter_attach_wgpu_surface(
      player->presenter,
      ErikaWgpuSurfaceKind_OhosNativeWindow,
      static_cast<uint64_t>(reinterpret_cast<uintptr_t>(window)),
      0,
      width,
      height,
      scale);
  if (status != ErikaStatus_Ok) {
    OH_NativeWindow_DestroyNativeWindow(window);
    return Int32(env, status);
  }
  player->window = window;
  return Int32(env, ErikaStatus_Ok);
}

napi_value NativeResizeSurface(napi_env env, napi_callback_info info) {
  size_t argc = 4;
  napi_value args[4] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 4) {
    return Int32(env, ErikaStatus_NullPointer);
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return Int32(env, ErikaStatus_NullPointer);
  }
  return Int32(
      env,
      erika_presenter_resize_surface(
          player->presenter,
          static_cast<uint32_t>(GetInt32(env, args[1])),
          static_cast<uint32_t>(GetInt32(env, args[2])),
          GetDouble(env, args[3])));
}

napi_value NativeDetachSurface(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc == 0) {
    return Int32(env, ErikaStatus_NullPointer);
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return Int32(env, ErikaStatus_NullPointer);
  }
  const auto status = erika_presenter_detach_surface(player->presenter);
  if (player->window != nullptr) {
    OH_NativeWindow_DestroyNativeWindow(player->window);
    player->window = nullptr;
  }
  return Int32(env, status);
}

napi_value NativeRenderTick(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 2) {
    return String(env, R"({"ok":false,"status":1,"error":"missing render argument"})");
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return String(env, R"({"ok":false,"status":1,"error":"unknown Erika player"})");
  }
  char* response =
      erika_presenter_render_tick_json(player->presenter, GetDouble(env, args[1]));
  napi_value result = String(env, response);
  erika_string_free(response);
  return result;
}

napi_value NativePollEvent(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc == 0) {
    return Null(env);
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return Null(env);
  }
  char* response = erika_presenter_poll_event_json(player->presenter);
  if (response == nullptr) {
    return Null(env);
  }
  napi_value result = String(env, response);
  erika_string_free(response);
  return result;
}

napi_value NativeCaptureFrame(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value args[3] = {};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  if (argc < 3) {
    return Null(env);
  }
  OhosPlayer* player = FindPlayer(GetInt64(env, args[0]));
  if (player == nullptr) {
    return Null(env);
  }

  const int32_t requested_width = GetInt32(env, args[1]);
  const int32_t requested_height = GetInt32(env, args[2]);
  if (requested_width <= 0 || requested_height <= 0) {
    return Null(env);
  }
  const auto width = static_cast<uint32_t>(requested_width);
  const auto height = static_cast<uint32_t>(requested_height);
  const size_t width_size = static_cast<size_t>(width);
  const size_t height_size = static_cast<size_t>(height);
  if (height_size > std::numeric_limits<size_t>::max() / width_size ||
      width_size * height_size >
          std::numeric_limits<size_t>::max() / static_cast<size_t>(4)) {
    return Null(env);
  }
  const size_t byte_count = width_size * height_size * 4;

  napi_value array_buffer = nullptr;
  void* rgba = nullptr;
  if (napi_create_arraybuffer(env, byte_count, &rgba, &array_buffer) != napi_ok ||
      rgba == nullptr) {
    return Null(env);
  }
  const auto status = erika_presenter_capture_frame_rgba(
      player->presenter,
      width,
      height,
      static_cast<uint8_t*>(rgba),
      byte_count);
  if (status != ErikaStatus_Ok) {
    return Null(env);
  }

  napi_value bytes = nullptr;
  if (napi_create_typedarray(
          env,
          napi_uint8_array,
          byte_count,
          array_buffer,
          0,
          &bytes) != napi_ok) {
    return Null(env);
  }
  return bytes;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor descriptors[] = {
      {"nativeCreate", nullptr, NativeCreate, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeLastError", nullptr, NativeLastError, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeDestroy", nullptr, NativeDestroy, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeInvoke", nullptr, NativeInvoke, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeRegisterSubtitleMemoryFont", nullptr, NativeRegisterSubtitleMemoryFont, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeAttachSurface", nullptr, NativeAttachSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeResizeSurface", nullptr, NativeResizeSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeDetachSurface", nullptr, NativeDetachSurface, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeRenderTick", nullptr, NativeRenderTick, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativePollEvent", nullptr, NativePollEvent, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"nativeCaptureFrame", nullptr, NativeCaptureFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(
      env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
  return exports;
}

}  // namespace

NAPI_MODULE(erika_flutter, Init)

extern "C" void* ErikaOhosPlayerFromId(int64_t player_id) {
  OhosPlayer* player = FindPlayer(player_id);
  return player == nullptr ? nullptr : player->presenter;
}
