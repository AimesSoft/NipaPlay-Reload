// Copyright (c) Aimes Soft and contributors.
// SPDX-License-Identifier: MIT
#pragma once
#include <napi/native_api.h>
#include <native_window/external_window.h>
#include <hilog/log.h>
#include "erika.h"
#include "presenter_worker.h"
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

// Released runtimes before custom-model support must still load this bridge.
#pragma weak erika_presenter_load_upscaler_model

namespace erika_ohos {
using Task = std::function<void(napi_env)>;
inline std::string Take(char* value) {
  std::string copy = value ? value : ""; erika_string_free(value); return copy;
}
inline std::atomic<bool> frame_trace{false};
inline napi_value Null(napi_env env) { napi_value v; napi_get_null(env, &v); return v; }
inline napi_value Number(napi_env env, int64_t n) { napi_value v; napi_create_int64(env, n, &v); return v; }
inline napi_value String(napi_env env, const std::string& s) {
  napi_value v; napi_create_string_utf8(env, s.c_str(), s.size(), &v); return v;
}
inline double Double(napi_env env, napi_value v) { double n = 0; napi_get_value_double(env, v, &n); return n; }
inline int64_t Integer(napi_env env, napi_value v) { int64_t n = 0; napi_get_value_int64(env, v, &n); return n; }
inline std::string Text(napi_env env, napi_value v) {
  size_t n = 0; napi_get_value_string_utf8(env, v, nullptr, 0, &n);
  std::string s(n + 1, '\0'); size_t written = 0;
  napi_get_value_string_utf8(env, v, s.data(), s.size(), &written); s.resize(written); return s;
}
struct Reply {
  enum Kind { Nil, Int, Json, Bytes, Font } kind = Nil;
  int64_t number = 0, font = 0;
  std::string text, error;
  std::vector<uint8_t> bytes;
};
inline napi_value Value(napi_env env, const Reply& r) {
  if (r.kind == Reply::Int) return Number(env, r.number);
  if (r.kind == Reply::Json) return String(env, r.text);
  if (r.kind == Reply::Font) {
    napi_value v; napi_create_array_with_length(env, 2, &v);
    napi_set_element(env, v, 0, Number(env, r.number)); napi_set_element(env, v, 1, Number(env, r.font)); return v;
  }
  if (r.kind == Reply::Bytes) {
    void* data = nullptr; napi_value buffer, v;
    if (napi_create_arraybuffer(env, r.bytes.size(), &data, &buffer) != napi_ok) return Null(env);
    if (!r.bytes.empty()) std::memcpy(data, r.bytes.data(), r.bytes.size());
    napi_create_typedarray(env, napi_uint8_array, r.bytes.size(), buffer, 0, &v); return v;
  }
  return Null(env);
}
// Only this mailbox crosses into ArkUI. Calls are nonblocking: workers never
// depend on ArkUI making progress, including while teardown joins them.
struct Mailbox {
  napi_threadsafe_function function = nullptr;
  std::atomic<bool> closing{false};
  bool Send(Task task) {
    if (closing.load()) return false;
    auto* owned = new Task(std::move(task));
    if (napi_call_threadsafe_function(function, owned, napi_tsfn_nonblocking) == napi_ok) return true;
    delete owned; return false;
  }
};
struct Subscription { bool alive = true; uint64_t generation = 0; napi_ref callback = nullptr; };
struct Player {
  ErikaPresenterHandle* presenter = nullptr; // Owner-only, never exported.
  OHNativeWindow* window = nullptr; // Owned producer reference, owner-only.
  int64_t id;
  std::thread::id platform = std::this_thread::get_id();
  bool traced = false;
  std::mutex frame_mutex;
  std::string last_render = R"({"ok":true,"value":null})";
  std::shared_ptr<Subscription> subscription = std::make_shared<Subscription>(); // ArkUI only.
  std::shared_ptr<std::atomic<bool>> event_pending = std::make_shared<std::atomic<bool>>(false);
  erika::PresenterWorker worker;
  explicit Player(int64_t value) : id(value) {}
  ErikaStatus Detach() {
    auto status = presenter ? erika_presenter_detach_surface(presenter) : ErikaStatus_NullPointer;
    if (window) OH_NativeWindow_DestroyNativeWindow(window);
    window = nullptr; return status;
  }
  void Stop() {
    worker.Stop([this] { Detach(); if (presenter) erika_presenter_destroy(presenter); presenter = nullptr; });
  }
  ~Player() { Stop(); }
  Reply CachedFrame() {
    std::lock_guard<std::mutex> lock(frame_mutex);
    Reply reply; reply.kind = Reply::Json; reply.text = last_render; return reply;
  }
  std::string Render(double time) {
    const auto start = std::chrono::steady_clock::now();
    const bool trace = frame_trace.load() || (std::getenv("ERIKA_FLUTTER_FRAME_TRACE") &&
      std::strcmp(std::getenv("ERIKA_FLUTTER_FRAME_TRACE"), "1") == 0);
    if (trace && !traced) {
      traced = true;
      OH_LOG_Print(LOG_APP, LOG_INFO, 0x3900, "Erika", "presenter_worker player=%{public}lld platform_thread=%{public}llu render_thread=%{public}llu off_platform=%{public}s",
        static_cast<long long>(id), static_cast<unsigned long long>(std::hash<std::thread::id>{}(platform)),
        static_cast<unsigned long long>(std::hash<std::thread::id>{}(std::this_thread::get_id())),
        platform != std::this_thread::get_id() ? "true" : "false");
    }
    auto response = Take(erika_presenter_render_tick_json(presenter, time));
    { std::lock_guard<std::mutex> lock(frame_mutex); last_render = response; }
    const double work_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
    if (trace && work_ms >= 16) OH_LOG_Print(LOG_APP, LOG_INFO, 0x3900, "Erika",
      "frame_tick player=%{public}lld work_ms=%{public}.3f", static_cast<long long>(id), work_ms);
    return response;
  }
};
struct Environment {
  Mailbox mailbox;
  std::shared_ptr<std::atomic<bool>> alive = std::make_shared<std::atomic<bool>>(true);
  std::unordered_map<int64_t, std::unique_ptr<Player>> players; // ArkUI only.
  std::string last_error; // Copy of the owner's thread-local error.
  void Retire(napi_env env, Player& p) {
    p.subscription->alive = false;
    p.Stop(); // NativeWindow producer must retire before the host destroys its surface.
    if (env && p.subscription->callback) napi_delete_reference(env, p.subscription->callback);
    p.subscription->callback = nullptr;
  }
};
inline std::atomic<int64_t> next_id{1};
enum class Op { Create, Destroy, Invoke, Font, Model, Attach, Resize, Detach, Render, Poll, Audio, Capture, LastError, Start, Stop, Trace };
struct Binding { Environment* state; Op op; bool async; };
struct Request {
  Op op;
  int64_t id = 0;
  uint64_t surface = 0;
  double a = 0, b = 0, c = 0, d = 0;
  std::string method, json;
  std::vector<uint8_t> bytes;
};
inline void ReadBytes(napi_env env, napi_value v, std::vector<uint8_t>& out) {
  bool is_buffer = false; napi_is_arraybuffer(env, v, &is_buffer);
  void* data = nullptr; size_t count = 0;
  if (is_buffer) napi_get_arraybuffer_info(env, v, &data, &count);
  else {
    bool typed = false; napi_is_typedarray(env, v, &typed); if (!typed) return;
    napi_typedarray_type type; napi_value buffer; size_t offset;
    if (napi_get_typedarray_info(env, v, &type, &count, &data, &buffer, &offset) != napi_ok ||
        (type != napi_uint8_array && type != napi_uint8_clamped_array)) return;
  }
  if (data && count) out.assign(static_cast<uint8_t*>(data), static_cast<uint8_t*>(data) + count);
}
inline Reply Execute(Player& p, const Request& r) {
  Reply reply;
  reply.kind = Reply::Int;
  if (r.op == Op::Create) {
    ErikaPresenterConfig config{};
    config.output_mode = static_cast<int32_t>(r.a); config.edr_headroom = static_cast<float>(r.b);
    config.luma_upscaler = static_cast<int32_t>(r.c); config.video_alpha_mode = static_cast<int32_t>(r.d);
    p.presenter = erika_presenter_create_with_config(config); reply.number = p.presenter ? p.id : 0;
  } else if (!p.presenter) {
    reply.number = ErikaStatus_NullPointer;
    if (r.op == Op::Invoke || r.op == Op::Render) {
      reply.kind = Reply::Json; reply.text = R"({"ok":false,"status":1,"error":"unknown Erika player"})";
    } else if (r.op == Op::Capture || r.op == Op::Poll) reply.kind = Reply::Nil;
  } else if (r.op == Op::Invoke) {
    reply.kind = Reply::Json; reply.text = Take(erika_presenter_invoke_json(p.presenter, r.method.c_str(), r.json.c_str()));
  } else if (r.op == Op::Font) {
    uint64_t font = 0; reply.kind = Reply::Font;
    reply.number = erika_presenter_register_subtitle_memory_font(p.presenter, r.bytes.data(), r.bytes.size(), &font); reply.font = font;
  } else if (r.op == Op::Model) {
    if (!erika_presenter_load_upscaler_model) {
      reply.number = ErikaStatus_PlayerError;
      reply.error = "The Erika runtime does not support custom upscaler models; update the native library";
      return reply;
    }
    reply.number = erika_presenter_load_upscaler_model(p.presenter, r.method.c_str(), r.bytes.data(), r.bytes.size());
  } else if (r.op == Op::Attach) {
    p.Detach();
    // Surface IDs cross threads, never XComponent/ArkUI objects. The NDK's
    // CreateNativeWindowFromSurfaceId owns a producer reference; NativeWindow
    // has no ArkUI affinity. All use/release is serialized here. ArkTS retains
    // its texture/XComponent until a detach/destroy fence has completed.
    if (OH_NativeWindow_CreateNativeWindowFromSurfaceId(r.surface, &p.window) != 0 || !p.window)
      reply.number = ErikaStatus_PlayerError;
    else {
      reply.number = erika_presenter_attach_wgpu_surface(p.presenter, ErikaWgpuSurfaceKind_OhosNativeWindow,
        static_cast<uint64_t>(reinterpret_cast<uintptr_t>(p.window)), 0, static_cast<uint32_t>(r.a), static_cast<uint32_t>(r.b), r.c);
      if (reply.number != ErikaStatus_Ok) { OH_NativeWindow_DestroyNativeWindow(p.window); p.window = nullptr; }
    }
  } else if (r.op == Op::Resize) {
    reply.number = erika_presenter_resize_surface(p.presenter, static_cast<uint32_t>(r.a), static_cast<uint32_t>(r.b), r.c);
  } else if (r.op == Op::Detach) reply.number = p.Detach();
  else if (r.op == Op::Render) { reply.kind = Reply::Json; reply.text = p.Render(r.a); }
  else if (r.op == Op::Poll) {
    reply.text = Take(erika_presenter_poll_event_json(p.presenter)); reply.kind = reply.text.empty() ? Reply::Nil : Reply::Json;
  } else if (r.op == Op::Audio) {
    ErikaPresenterStats stats{}; reply.number = erika_presenter_audio_only_tick(p.presenter, &stats);
  } else if (r.op == Op::Capture) {
    reply.kind = Reply::Nil;
    // Bound allocations before multiplication, as in the Flutter texture path.
    if (r.a >= 1 && r.b >= 1 && r.a <= 8192 && r.b <= 8192) {
      const auto w = static_cast<uint32_t>(r.a), h = static_cast<uint32_t>(r.b);
      reply.bytes.resize(static_cast<size_t>(w) * h * 4);
      if (erika_presenter_capture_frame_rgba(p.presenter, w, h, reply.bytes.data(), reply.bytes.size()) == ErikaStatus_Ok)
        reply.kind = Reply::Bytes;
      else reply.bytes.clear();
    }
  }
  reply.error = Take(erika_last_error_message()); // C API error storage is thread local.
  return reply;
}
inline void StartFrames(Environment& state, Player& p, uint64_t generation) {
  auto subscription = p.subscription;
  p.worker.SetFrameTask([&state, &p, subscription, generation] {
    if (!p.presenter) return;
    const double time = std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
    p.Render(time);
    // Bound the TSFN event backlog to one batch per presenter while ArkUI is busy.
    if (p.event_pending->exchange(true)) return;
    std::vector<std::string> events;
    for (int i = 0; i < 64; ++i) {
      auto raw = Take(erika_presenter_poll_event_json(p.presenter)); if (raw.empty()) break;
      events.push_back(std::move(raw));
    }
    if (events.empty()) { p.event_pending->store(false); return; }
    auto pending = p.event_pending;
    if (!state.mailbox.Send([subscription, generation, pending, events = std::move(events)](napi_env env) {
      pending->store(false);
      if (!subscription->alive || subscription->generation != generation || !subscription->callback) return;
      napi_value callback, receiver, ignored;
      napi_get_reference_value(env, subscription->callback, &callback); napi_get_undefined(env, &receiver);
      for (const auto& raw : events) {
        if (!subscription->alive || subscription->generation != generation) break;
        napi_value arg = String(env, raw);
        if (napi_call_function(env, receiver, callback, 1, &arg, &ignored) != napi_ok) break;
      }
    })) pending->store(false);
  });
}
inline napi_value Dispatch(napi_env env, napi_callback_info info) {
  size_t argc = 5; napi_value args[5]{}; void* data = nullptr;
  napi_get_cb_info(env, info, &argc, args, nullptr, &data);
  const auto& binding = *static_cast<Binding*>(data);
  auto& state = *binding.state;
  Request r{}; r.op = binding.op;
  if (r.op == Op::Trace) {
    bool enabled = false;
    if (argc) napi_get_value_bool(env, args[0], &enabled);
    frame_trace.store(enabled);
    return Null(env);
  }
  if (r.op == Op::LastError) return String(env, state.last_error);
  r.id = argc ? Integer(env, args[0]) : 0;
  if (r.op == Op::Create && argc < 3) {
    // As before the owner thread: outputMode, headroom and upscaler are
    // required (videoAlphaMode defaults to opaque); a short call creates nothing.
    Reply none; none.kind = Reply::Int;
    if (!binding.async) return Value(env, none);
    napi_deferred deferred; napi_value promise;
    napi_create_promise(env, &deferred, &promise);
    napi_resolve_deferred(env, deferred, Value(env, none));
    return promise;
  }
  if (r.op == Op::Create) {
    r.a = argc > 0 ? Double(env, args[0]) : 0; r.b = argc > 1 ? Double(env, args[1]) : 1;
    r.c = argc > 2 ? Double(env, args[2]) : 0; r.d = argc > 3 ? Double(env, args[3]) : 0;
    r.id = next_id.fetch_add(1); state.players.emplace(r.id, std::make_unique<Player>(r.id));
  }
  auto found = state.players.find(r.id);
  Player* p = found == state.players.end() ? nullptr : found->second.get();
  if (r.op == Op::Destroy) {
    if (p) { state.Retire(env, *p); state.players.erase(found); }
    return Null(env);
  }
  if (r.op == Op::Start || r.op == Op::Stop) {
    if (!p) return Null(env);
    auto& sub = *p->subscription;
    ++sub.generation;
    p->worker.SetFrameTask({});
    if (sub.callback) napi_delete_reference(env, sub.callback);
    sub.callback = nullptr;
    if (r.op == Op::Start && argc > 1) {
      napi_create_reference(env, args[1], 1, &sub.callback);
      StartFrames(state, *p, sub.generation);
    }
    return Null(env);
  }
  if (r.op == Op::Invoke && argc >= 3) { r.method = Text(env, args[1]); r.json = Text(env, args[2]); }
  if (r.op == Op::Font && argc >= 2) ReadBytes(env, args[1], r.bytes);
  if (r.op == Op::Model && argc >= 3) { r.method = Text(env, args[1]); ReadBytes(env, args[2], r.bytes); }
  if (r.op == Op::Attach && argc >= 5) {
    napi_valuetype type; napi_typeof(env, args[1], &type);
    if (type == napi_bigint) { bool lossless = false; napi_get_value_bigint_uint64(env, args[1], &r.surface, &lossless); }
    else r.surface = static_cast<uint64_t>(Integer(env, args[1]));
    r.a = Double(env, args[2]); r.b = Double(env, args[3]); r.c = Double(env, args[4]);
  }
  if (r.op == Op::Resize && argc >= 4) { r.a = Double(env, args[1]); r.b = Double(env, args[2]); r.c = Double(env, args[3]); }
  if (r.op == Op::Render && argc >= 2) r.a = Double(env, args[1]);
  if (r.op == Op::Capture && argc >= 3) { r.a = Double(env, args[1]); r.b = Double(env, args[2]); }
  auto missing = [r] {
    Reply reply; reply.number = ErikaStatus_NullPointer; reply.kind = Reply::Int;
    if (r.op == Op::Invoke || r.op == Op::Render) {
      reply.kind = Reply::Json; reply.text = R"({"ok":false,"status":1,"error":"unknown Erika player"})";
    } else if (r.op == Op::Poll || r.op == Op::Capture) reply.kind = Reply::Nil;
    else if (r.op == Op::Font) reply.kind = Reply::Font;
    return reply;
  };
  if (!binding.async) {
    // Preserve the existing synchronous ArkTS host API. No N-API object or
    // borrowed typed-array memory is accessed by the worker.
    Reply reply;
    if (p && r.op == Op::Render) {
      // Legacy host-driven rendering remains synchronous when accepted. If an
      // automatic/explicit frame is already pending, return its latest completed
      // stats instead of queuing another render behind it.
      auto done = std::make_shared<std::promise<Reply>>();
      auto result = done->get_future();
      if (p->worker.RequestFrame([p, r, done] { done->set_value(Execute(*p, r)); })) reply = result.get();
      else reply = p->CachedFrame();
    } else reply = p ? p->worker.Call([p, r] { return Execute(*p, r); }) : missing();
    state.last_error = reply.error;
    if (r.op == Op::Create && reply.number == 0) state.players.erase(r.id);
    return Value(env, reply);
  }
  napi_deferred deferred; napi_value promise;
  napi_create_promise(env, &deferred, &promise);
  if (!p) { napi_resolve_deferred(env, deferred, Value(env, missing())); return promise; }
  auto work = [p, r = std::move(r), &state, deferred, alive = state.alive] {
    auto reply = Execute(*p, r);
    state.mailbox.Send([&state, deferred, alive, operation = r.op, id = r.id, reply = std::move(reply)](napi_env env) {
      if (!alive->load()) return;
      state.last_error = reply.error;
      if (operation == Op::Create && reply.number == 0) state.players.erase(id);
      napi_resolve_deferred(env, deferred, Value(env, reply));
    });
  };
  const bool accepted = binding.op == Op::Render ? p->worker.RequestFrame(std::move(work),
    [&state, deferred, alive = state.alive] {
      state.mailbox.Send([deferred, alive](napi_env env) {
        if (alive->load()) napi_resolve_deferred(env, deferred, Null(env));
      });
    }) : p->worker.Post(std::move(work));
  if (!accepted) napi_resolve_deferred(env, deferred, Null(env));
  return promise;
}
struct ModuleState : Environment { std::vector<std::unique_ptr<Binding>> bindings; };
inline napi_value Init(napi_env env, napi_value exports) {
  auto* state = new ModuleState();
  napi_value name = String(env, "Erika presenter completions");
  if (napi_create_threadsafe_function(env, nullptr, nullptr, name, 0, 1, nullptr, nullptr, nullptr,
      [](napi_env env, napi_value, void*, void* data) {
        std::unique_ptr<Task> task(static_cast<Task*>(data));
        if (env && task) (*task)(env); // env=null during abort: release owned values only.
      }, &state->mailbox.function) != napi_ok) { delete state; return exports; }
  napi_unref_threadsafe_function(env, state->mailbox.function);
  napi_add_env_cleanup_hook(env, [](void* data) {
    auto* state = static_cast<ModuleState*>(data);
    state->alive->store(false);
    state->mailbox.closing.store(true);
    for (auto& entry : state->players) state->Retire(nullptr, *entry.second);
    state->players.clear();
    napi_release_threadsafe_function(state->mailbox.function, napi_tsfn_abort);
    delete state;
  }, state);
  const std::pair<const char*, Op> operations[] = {
    {"nativeCreate", Op::Create}, {"nativeLastError", Op::LastError}, {"nativeDestroy", Op::Destroy},
    {"nativeInvoke", Op::Invoke}, {"nativeRegisterSubtitleMemoryFont", Op::Font}, {"nativeLoadUpscalerModel", Op::Model},
    {"nativeAttachSurface", Op::Attach}, {"nativeResizeSurface", Op::Resize}, {"nativeDetachSurface", Op::Detach},
    {"nativeRenderTick", Op::Render}, {"nativePollEvent", Op::Poll}, {"nativeAudioOnlyTick", Op::Audio},
    {"nativeCaptureFrame", Op::Capture}, {"nativeStartFrames", Op::Start}, {"nativeStopFrames", Op::Stop},
    {"nativeSetFrameTrace", Op::Trace}
  };
  for (const auto& operation : operations) for (bool async : {false, true}) {
    if (async && (operation.second == Op::LastError || operation.second == Op::Destroy ||
        operation.second == Op::Start || operation.second == Op::Stop || operation.second == Op::Trace)) continue;
    auto binding = std::make_unique<Binding>(Binding{state, operation.second, async});
    const std::string key = std::string(operation.first) + (async ? "Async" : "");
    napi_property_descriptor descriptor{key.c_str(), nullptr, Dispatch, nullptr, nullptr, nullptr, napi_default, binding.get()};
    napi_define_properties(env, exports, 1, &descriptor);
    state->bindings.push_back(std::move(binding));
  }
  return exports;
}
} // namespace erika_ohos
