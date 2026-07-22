#include "windows_native_video.h"

#include <flutter/binary_messenger.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include <client.h>
#include <gl/GL.h>
#include <render.h>
#include <render_gl.h>

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cmath>
#include <cstdint>
#include <cwchar>
#include <future>
#include <iostream>
#include <iterator>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <unordered_map>
#include <variant>

#include <commctrl.h>
#include <windowsx.h>

namespace {

constexpr char kChannelName[] = "nipaplay/windows_native_video";
constexpr char kDesktopWindowChannelName[] =
    "nipaplay/desktop_multi_window_host";
constexpr int64_t kWindowHostedVideoSurfaceId = -1;
constexpr wchar_t kOverlayWindowClassName[] =
    L"NipaPlayWindowsNativeVideoOverlay";
constexpr wchar_t kFlutterRegularHostWindowClassName[] =
    L"FLUTTER_HOST_WINDOW";
constexpr wchar_t kFlutterViewWindowClassName[] = L"FLUTTERVIEW";

struct FlutterRegularHostSearch {
  DWORD process_id = 0;
  HWND result = nullptr;
};

BOOL CALLBACK FindFlutterRegularHostWindow(HWND window, LPARAM parameter) {
  auto* search = reinterpret_cast<FlutterRegularHostSearch*>(parameter);
  DWORD process_id = 0;
  ::GetWindowThreadProcessId(window, &process_id);
  if (process_id != search->process_id) {
    return TRUE;
  }

  wchar_t class_name[64] = {};
  if (::GetClassNameW(window, class_name, 64) == 0 ||
      std::wcscmp(class_name, kFlutterRegularHostWindowClassName) != 0) {
    return TRUE;
  }
  search->result = window;
  return FALSE;
}

HWND ResolveFlutterRegularHostWindow() {
  FlutterRegularHostSearch search{::GetCurrentProcessId(), nullptr};
  ::EnumWindows(FindFlutterRegularHostWindow,
                reinterpret_cast<LPARAM>(&search));
  return search.result;
}

constexpr UINT_PTR kDetachedWindowSubclassId = 706;
std::unordered_map<HWND, double> g_detached_window_aspect_ratios;
std::unordered_map<HWND, RECT> g_picture_in_picture_restore_bounds;

LRESULT CALLBACK DetachedWindowSubclassProc(HWND window,
                                            UINT message,
                                            WPARAM wparam,
                                            LPARAM lparam,
                                            UINT_PTR,
                                            DWORD_PTR) {
  if (message == WM_NCDESTROY) {
    g_detached_window_aspect_ratios.erase(window);
    g_picture_in_picture_restore_bounds.erase(window);
    ::RemoveWindowSubclass(window, DetachedWindowSubclassProc,
                           kDetachedWindowSubclassId);
    return ::DefSubclassProc(window, message, wparam, lparam);
  }
  if (message != WM_SIZING || lparam == 0) {
    return ::DefSubclassProc(window, message, wparam, lparam);
  }

  const auto ratio_it = g_detached_window_aspect_ratios.find(window);
  if (ratio_it == g_detached_window_aspect_ratios.end() ||
      ratio_it->second <= 0.0) {
    return ::DefSubclassProc(window, message, wparam, lparam);
  }

  auto* sizing_rect = reinterpret_cast<RECT*>(lparam);
  RECT current_window = {};
  RECT current_client = {};
  ::GetWindowRect(window, &current_window);
  ::GetClientRect(window, &current_client);
  const int frame_width =
      (current_window.right - current_window.left) - current_client.right;
  const int frame_height =
      (current_window.bottom - current_window.top) - current_client.bottom;
  const int proposed_width = sizing_rect->right - sizing_rect->left;
  const int proposed_height = sizing_rect->bottom - sizing_rect->top;
  const double ratio = ratio_it->second;

  const bool size_from_height =
      wparam == WMSZ_TOP || wparam == WMSZ_BOTTOM;
  if (size_from_height) {
    const int client_height = std::max(1, proposed_height - frame_height);
    const int target_width =
        static_cast<int>(std::lround(client_height * ratio)) + frame_width;
    sizing_rect->right = sizing_rect->left + target_width;
  } else {
    const int client_width = std::max(1, proposed_width - frame_width);
    const int target_height =
        static_cast<int>(std::lround(client_width / ratio)) + frame_height;
    if (wparam == WMSZ_TOPLEFT || wparam == WMSZ_TOPRIGHT) {
      sizing_rect->top = sizing_rect->bottom - target_height;
    } else {
      sizing_rect->bottom = sizing_rect->top + target_height;
    }
  }
  return TRUE;
}

void SetDetachedWindowAspectRatio(HWND window, double ratio) {
  if (ratio <= 0.0 || !std::isfinite(ratio)) {
    g_detached_window_aspect_ratios.erase(window);
    ::RemoveWindowSubclass(window, DetachedWindowSubclassProc,
                           kDetachedWindowSubclassId);
    return;
  }
  g_detached_window_aspect_ratios[window] = ratio;
  ::SetWindowSubclass(window, DetachedWindowSubclassProc,
                      kDetachedWindowSubclassId, 0);
}

void MakeDetachedWindowFrameless(HWND window) {
  LONG_PTR style = ::GetWindowLongPtrW(window, GWL_STYLE);
  style &= ~WS_CAPTION;
  style |= WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
  ::SetWindowLongPtrW(window, GWL_STYLE, style);
  ::SetWindowPos(window, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                     SWP_FRAMECHANGED);
}

void SetDetachedWindowClientSize(HWND window, double logical_width,
                                 double logical_height) {
  if (logical_width <= 0.0 || logical_height <= 0.0) {
    return;
  }
  const UINT dpi = ::GetDpiForWindow(window);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  RECT bounds = {
      0, 0, static_cast<LONG>(std::lround(logical_width * scale)),
      static_cast<LONG>(std::lround(logical_height * scale))};
  const DWORD style = static_cast<DWORD>(::GetWindowLongPtrW(window, GWL_STYLE));
  const DWORD ex_style =
      static_cast<DWORD>(::GetWindowLongPtrW(window, GWL_EXSTYLE));
  ::AdjustWindowRectExForDpi(&bounds, style, FALSE, ex_style, dpi);
  ::SetWindowPos(window, nullptr, 0, 0, bounds.right - bounds.left,
                 bounds.bottom - bounds.top,
                 SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
}

double ReadDouble(const flutter::EncodableMap& args,
                  const char* key,
                  double fallback);
bool ReadBool(const flutter::EncodableMap& args,
              const char* key,
              bool fallback);

std::string ReadString(const flutter::EncodableMap& args,
                       const char* key,
                       const std::string& fallback = "") {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* value = std::get_if<std::string>(&it->second)) {
    return *value;
  }
  return fallback;
}

void SetDetachedWindowPictureInPicture(
    HWND window,
    const flutter::EncodableMap& args) {
  const bool enabled = ReadBool(args, "enabled", false);
  if (!enabled) {
    const auto restore_it = g_picture_in_picture_restore_bounds.find(window);
    if (restore_it == g_picture_in_picture_restore_bounds.end()) {
      return;
    }
    const RECT restore = restore_it->second;
    g_picture_in_picture_restore_bounds.erase(restore_it);
    ::SetWindowPos(window, nullptr, restore.left, restore.top,
                   restore.right - restore.left, restore.bottom - restore.top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
    return;
  }

  if (g_picture_in_picture_restore_bounds.find(window) ==
      g_picture_in_picture_restore_bounds.end()) {
    RECT current = {};
    if (::GetWindowRect(window, &current)) {
      g_picture_in_picture_restore_bounds[window] = current;
    }
  }

  const HMONITOR monitor = ::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info = {};
  monitor_info.cbSize = sizeof(monitor_info);
  if (monitor == nullptr || !::GetMonitorInfoW(monitor, &monitor_info)) {
    return;
  }
  const RECT work = monitor_info.rcWork;
  const double work_width = static_cast<double>(work.right - work.left);
  const double work_height = static_cast<double>(work.bottom - work.top);
  const double ratio = std::clamp(ReadDouble(args, "aspectRatio", 16.0 / 9.0),
                                  0.5, 3.0);
  const UINT dpi = ::GetDpiForWindow(window);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  const double margin = std::max(0.0, ReadDouble(args, "margin", 16.0) * scale);
  const double available_width = std::max(1.0, work_width - margin * 2.0);
  double client_height = std::min(work_height / 3.0,
                                  std::max(1.0, work_height - margin * 2.0));
  double client_width = client_height * ratio;
  if (client_width > available_width) {
    client_width = available_width;
    client_height = client_width / ratio;
  }
  SetDetachedWindowClientSize(window, client_width / scale,
                              client_height / scale);

  RECT resized = {};
  if (!::GetWindowRect(window, &resized)) {
    return;
  }
  const int window_width = resized.right - resized.left;
  const int window_height = resized.bottom - resized.top;
  const std::string placement = ReadString(args, "placement", "topRight");
  const int left = work.left + static_cast<int>(std::lround(margin));
  const int right =
      work.right - window_width - static_cast<int>(std::lround(margin));
  const int top = work.top + static_cast<int>(std::lround(margin));
  const int bottom =
      work.bottom - window_height - static_cast<int>(std::lround(margin));
  const bool place_left =
      placement == "topLeft" || placement == "bottomLeft";
  const bool place_bottom =
      placement == "bottomLeft" || placement == "bottomRight";
  ::SetWindowPos(window, nullptr, place_left ? left : right,
                 place_bottom ? bottom : top, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
}
constexpr UINT kRenderMessage = WM_APP + 0x4E56;

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
  if (const auto* s = std::get_if<std::string>(&value)) {
    try {
      return std::stoll(*s);
    } catch (...) {
      return std::nullopt;
    }
  }
  return std::nullopt;
}

std::optional<int64_t> ReadInt64(const flutter::EncodableMap& args,
                                 const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return std::nullopt;
  }
  return ToInt64(it->second);
}

double ReadDouble(const flutter::EncodableMap& args,
                  const char* key,
                  double fallback = 0.0) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* d = std::get_if<double>(&it->second)) {
    return *d;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return static_cast<double>(*i32);
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return static_cast<double>(*i64);
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    try {
      return std::stod(*s);
    } catch (...) {
      return fallback;
    }
  }
  return fallback;
}

bool ReadBool(const flutter::EncodableMap& args,
              const char* key,
              bool fallback = false) {
  const auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) {
    return fallback;
  }
  if (const auto* b = std::get_if<bool>(&it->second)) {
    return *b;
  }
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) {
    return *i32 != 0;
  }
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) {
    return *i64 != 0;
  }
  if (const auto* s = std::get_if<std::string>(&it->second)) {
    const std::string value = *s;
    return value == "1" || value == "true" || value == "yes" ||
           value == "on";
  }
  return fallback;
}

int LogicalToPhysical(HWND window, double value) {
  const UINT dpi = ::GetDpiForWindow(window);
  const double scale = dpi > 0 ? static_cast<double>(dpi) / 96.0 : 1.0;
  return static_cast<int>(std::lround(value * scale));
}

bool IsOverlayAboveFlutterEnabled() {
  wchar_t value[8] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      L"NIPAPLAY_WINDOWS_HDR_WINDOW_OVERLAY_ABOVE", value,
      static_cast<DWORD>(std::size(value)));
  return length > 0 && value[0] == L'1';
}

HWND ResolveOverlayInsertAfter(HWND host_window) {
  if (IsOverlayAboveFlutterEnabled()) {
    return HWND_TOP;
  }
  return host_window != nullptr ? host_window : HWND_BOTTOM;
}

int64_t HwndToInt64(HWND hwnd) {
  return static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd));
}

flutter::EncodableMap BuildWindowDiagnostics(HWND hwnd) {
  flutter::EncodableMap result;
  result[flutter::EncodableValue("hwnd")] =
      flutter::EncodableValue(HwndToInt64(hwnd));
  if (hwnd == nullptr) {
    return result;
  }

  const LONG_PTR style = ::GetWindowLongPtrW(hwnd, GWL_STYLE);
  const LONG_PTR ex_style = ::GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
  DWORD process_id = 0;
  const DWORD thread_id = ::GetWindowThreadProcessId(hwnd, &process_id);
  result[flutter::EncodableValue("style")] =
      flutter::EncodableValue(static_cast<int64_t>(style));
  result[flutter::EncodableValue("exStyle")] =
      flutter::EncodableValue(static_cast<int64_t>(ex_style));
  result[flutter::EncodableValue("visible")] =
      flutter::EncodableValue(::IsWindowVisible(hwnd) != FALSE);
  result[flutter::EncodableValue("enabled")] =
      flutter::EncodableValue(::IsWindowEnabled(hwnd) != FALSE);
  result[flutter::EncodableValue("threadId")] =
      flutter::EncodableValue(static_cast<int64_t>(thread_id));
  result[flutter::EncodableValue("processId")] =
      flutter::EncodableValue(static_cast<int64_t>(process_id));
  result[flutter::EncodableValue("parent")] =
      flutter::EncodableValue(HwndToInt64(::GetParent(hwnd)));
  result[flutter::EncodableValue("owner")] =
      flutter::EncodableValue(HwndToInt64(::GetWindow(hwnd, GW_OWNER)));
  result[flutter::EncodableValue("zPrev")] =
      flutter::EncodableValue(HwndToInt64(::GetWindow(hwnd, GW_HWNDPREV)));
  result[flutter::EncodableValue("zNext")] =
      flutter::EncodableValue(HwndToInt64(::GetWindow(hwnd, GW_HWNDNEXT)));
  result[flutter::EncodableValue("styleChild")] =
      flutter::EncodableValue((style & WS_CHILD) != 0);
  result[flutter::EncodableValue("stylePopup")] =
      flutter::EncodableValue((style & WS_POPUP) != 0);
  result[flutter::EncodableValue("exLayered")] =
      flutter::EncodableValue((ex_style & WS_EX_LAYERED) != 0);
  result[flutter::EncodableValue("exTransparent")] =
      flutter::EncodableValue((ex_style & WS_EX_TRANSPARENT) != 0);
  result[flutter::EncodableValue("exNoActivate")] =
      flutter::EncodableValue((ex_style & WS_EX_NOACTIVATE) != 0);
  return result;
}

flutter::EncodableMap BuildHitTestDiagnostics(HWND host_window,
                                              HWND overlay_window) {
  flutter::EncodableMap result;
  RECT rect = {};
  if (host_window == nullptr || overlay_window == nullptr ||
      !::GetWindowRect(overlay_window, &rect) || rect.right <= rect.left ||
      rect.bottom <= rect.top) {
    return result;
  }

  POINT screen_point = {
      (rect.left + rect.right) / 2,
      (rect.top + rect.bottom) / 2,
  };
  result[flutter::EncodableValue("screenX")] =
      flutter::EncodableValue(static_cast<int32_t>(screen_point.x));
  result[flutter::EncodableValue("screenY")] =
      flutter::EncodableValue(static_cast<int32_t>(screen_point.y));
  result[flutter::EncodableValue("windowFromPoint")] =
      flutter::EncodableValue(HwndToInt64(::WindowFromPoint(screen_point)));

  POINT client_point = screen_point;
  if (::ScreenToClient(host_window, &client_point)) {
    result[flutter::EncodableValue("hostClientX")] =
        flutter::EncodableValue(static_cast<int32_t>(client_point.x));
    result[flutter::EncodableValue("hostClientY")] =
        flutter::EncodableValue(static_cast<int32_t>(client_point.y));
    result[flutter::EncodableValue("childFromPointAll")] =
        flutter::EncodableValue(HwndToInt64(::ChildWindowFromPointEx(
            host_window, client_point, CWP_SKIPINVISIBLE | CWP_SKIPDISABLED)));
    result[flutter::EncodableValue("childFromPointSkipTransparent")] =
        flutter::EncodableValue(HwndToInt64(::ChildWindowFromPointEx(
            host_window, client_point,
            CWP_SKIPINVISIBLE | CWP_SKIPDISABLED | CWP_SKIPTRANSPARENT)));
  }
  return result;
}

bool HostClientOriginOnScreen(HWND host_window, POINT* origin) {
  if (host_window == nullptr || origin == nullptr) {
    return false;
  }
  origin->x = 0;
  origin->y = 0;
  return ::ClientToScreen(host_window, origin) != FALSE;
}

bool HostWindowCanShowOverlay(HWND host_window, bool host_window_active) {
  if (!host_window_active || host_window == nullptr ||
      ::IsIconic(host_window) || !::IsWindowVisible(host_window)) {
    return false;
  }

  const HWND foreground_window = ::GetForegroundWindow();
  if (foreground_window == nullptr) {
    return true;
  }

  DWORD host_process_id = 0;
  DWORD foreground_process_id = 0;
  ::GetWindowThreadProcessId(host_window, &host_process_id);
  ::GetWindowThreadProcessId(foreground_window, &foreground_process_id);
  if (host_process_id == 0 || foreground_process_id == 0) {
    return true;
  }
  return host_process_id == foreground_process_id;
}

void LogNativeVideo(const std::string& message) {
  std::cout << "NipaPlay WindowsNativeVideo: " << message << std::endl;
}

bool HasTransparentWindowBackgroundOverride() {
  wchar_t value[8] = {};
  const DWORD length = ::GetEnvironmentVariableW(
      L"NIPAPLAY_DISABLE_WINDOWS_TRANSPARENT_BACKGROUND", value,
      static_cast<DWORD>(std::size(value)));
  return length > 0 && value[0] == L'1';
}

bool ApplyTransparentAccent(HWND hwnd, const char* label) {
  if (hwnd == nullptr) {
    LogNativeVideo(std::string(label) + " transparent accent skipped: hwnd=0");
    return false;
  }

  typedef enum _ACCENT_STATE {
    ACCENT_DISABLED = 0,
    ACCENT_ENABLE_GRADIENT = 1,
    ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
    ACCENT_ENABLE_BLURBEHIND = 3,
    ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
    ACCENT_ENABLE_HOSTBACKDROP = 5,
    ACCENT_INVALID_STATE = 6
  } ACCENT_STATE;
  struct ACCENTPOLICY {
    int nAccentState;
    int nFlags;
    int nColor;
    int nAnimationId;
  };
  struct WINCOMPATTRDATA {
    int nAttribute;
    PVOID pData;
    ULONG ulDataSize;
  };
  typedef BOOL(WINAPI* SetWindowCompositionAttributeProc)(
      HWND, WINCOMPATTRDATA*);

  HMODULE user32 = ::LoadLibraryW(L"user32.dll");
  if (user32 == nullptr) {
    LogNativeVideo(std::string(label) +
                   " transparent accent failed: LoadLibrary user32 error=" +
                   std::to_string(::GetLastError()));
    return false;
  }

  auto set_window_composition_attribute =
      reinterpret_cast<SetWindowCompositionAttributeProc>(
          ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_window_composition_attribute == nullptr) {
    const DWORD error = ::GetLastError();
    ::FreeLibrary(user32);
    LogNativeVideo(std::string(label) +
                   " transparent accent failed: missing API error=" +
                   std::to_string(error));
    return false;
  }

  ACCENTPOLICY policy = {};
  policy.nAccentState = ACCENT_ENABLE_TRANSPARENTGRADIENT;
  policy.nFlags = 2;
  policy.nColor = 0x00000000;
  policy.nAnimationId = 0;
  WINCOMPATTRDATA data = {};
  data.nAttribute = 19;
  data.pData = &policy;
  data.ulDataSize = sizeof(policy);

  ::SetLastError(ERROR_SUCCESS);
  const BOOL ok = set_window_composition_attribute(hwnd, &data);
  const DWORD error = ::GetLastError();
  ::FreeLibrary(user32);
  if (!ok) {
    LogNativeVideo(std::string(label) +
                   " transparent accent failed: SetWindowCompositionAttribute "
                   "error=" +
                   std::to_string(error) + " hwnd=" +
                   std::to_string(HwndToInt64(hwnd)));
    return false;
  }

  LogNativeVideo(std::string(label) + " transparent accent enabled hwnd=" +
                 std::to_string(HwndToInt64(hwnd)) + " style=" +
                 std::to_string(static_cast<int64_t>(
                     ::GetWindowLongPtrW(hwnd, GWL_STYLE))) +
                 " exStyle=" +
                 std::to_string(static_cast<int64_t>(
                     ::GetWindowLongPtrW(hwnd, GWL_EXSTYLE))));
  return true;
}

std::string OptionalInt64ToString(const std::optional<int64_t>& value) {
  return value.has_value() ? std::to_string(value.value()) : "null";
}

void* GetOpenGLProcAddress(void*, const char* name) {
  void* proc = reinterpret_cast<void*>(::wglGetProcAddress(name));
  if (proc == nullptr || proc == reinterpret_cast<void*>(0x1) ||
      proc == reinterpret_cast<void*>(0x2) ||
      proc == reinterpret_cast<void*>(0x3) ||
      proc == reinterpret_cast<void*>(-1)) {
    static HMODULE opengl32 = ::LoadLibraryW(L"opengl32.dll");
    proc = opengl32 != nullptr
               ? reinterpret_cast<void*>(::GetProcAddress(opengl32, name))
               : nullptr;
  }
  return proc;
}

}  // namespace

class WindowsOpenGLVideoRenderer {
 public:
  WindowsOpenGLVideoRenderer(HWND hwnd, int64_t player_handle)
      : hwnd_(hwnd),
        player_handle_(player_handle),
        mpv_(reinterpret_cast<mpv_handle*>(
            static_cast<intptr_t>(player_handle))) {}

  ~WindowsOpenGLVideoRenderer() { Destroy(); }

  WindowsOpenGLVideoRenderer(const WindowsOpenGLVideoRenderer&) = delete;
  WindowsOpenGLVideoRenderer& operator=(const WindowsOpenGLVideoRenderer&) =
      delete;

  bool Initialize() {
    if (hwnd_ == nullptr || mpv_ == nullptr) {
      LogNativeVideo("renderer init failed: invalid hwnd/player hwnd=" +
                     std::to_string(HwndToInt64(hwnd_)) + " player=" +
                     std::to_string(player_handle_));
      return false;
    }

    dc_ = ::GetDC(hwnd_);
    if (dc_ == nullptr) {
      LogNativeVideo("renderer init failed: GetDC error=" +
                     std::to_string(::GetLastError()));
      return false;
    }

    if (!EnsurePixelFormat()) {
      Destroy();
      return false;
    }

    std::promise<bool> init_promise;
    auto init_future = init_promise.get_future();
    render_thread_ = std::thread(&WindowsOpenGLVideoRenderer::RenderThreadMain,
                                 this, std::move(init_promise));
    const bool initialized = init_future.get();
    if (!initialized) {
      Destroy();
      return false;
    }

    ::SetWindowLongPtrW(hwnd_, GWLP_USERDATA,
                        reinterpret_cast<LONG_PTR>(this));
    LogNativeVideo("renderer init ok hwnd=" +
                   std::to_string(HwndToInt64(hwnd_)) + " player=" +
                   std::to_string(player_handle_));
    RequestRender();
    return true;
  }

  void RequestRender() {
    if (destroyed_.load() || hwnd_ == nullptr) {
      return;
    }
    {
      std::lock_guard<std::mutex> lock(render_signal_mutex_);
      render_requested_ = true;
    }
    render_cv_.notify_one();
  }

  void HostWindowDidChange() {
    if (destroyed_.load() || hwnd_ == nullptr) {
      return;
    }
    ::InvalidateRect(hwnd_, nullptr, FALSE);
    RequestRender();
  }

  void Render() {
    RequestRender();
  }

 private:
  void RenderThreadMain(std::promise<bool> init_promise) {
    const bool initialized = InitializeOnRenderThread();
    init_promise.set_value(initialized);
    if (!initialized) {
      DestroyOpenGLOnRenderThread();
      return;
    }

    for (;;) {
      std::unique_lock<std::mutex> lock(render_signal_mutex_);
      render_cv_.wait(lock, [this] {
        return render_requested_ || stop_render_thread_;
      });
      if (stop_render_thread_) {
        break;
      }
      render_requested_ = false;
      lock.unlock();
      RenderFrameOnRenderThread();
    }

    DestroyOpenGLOnRenderThread();
  }

  bool InitializeOnRenderThread() {
    gl_context_ = ::wglCreateContext(dc_);
    if (gl_context_ == nullptr) {
      LogNativeVideo("renderer init failed: wglCreateContext error=" +
                     std::to_string(::GetLastError()));
      return false;
    }

    if (!::wglMakeCurrent(dc_, gl_context_)) {
      LogNativeVideo("renderer init failed: wglMakeCurrent error=" +
                     std::to_string(::GetLastError()));
      return false;
    }

    mpv_opengl_init_params gl_init_params = {};
    gl_init_params.get_proc_address = GetOpenGLProcAddress;
    gl_init_params.get_proc_address_ctx = nullptr;
    int advanced_control = 1;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE,
         const_cast<char*>(MPV_RENDER_API_TYPE_OPENGL)},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init_params},
        {MPV_RENDER_PARAM_ADVANCED_CONTROL, &advanced_control},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };

    const int result = ::mpv_render_context_create(&render_context_, mpv_,
                                                   params);
    if (result < 0 || render_context_ == nullptr) {
      LogNativeVideo("renderer init failed: mpv_render_context_create " +
                     std::string(::mpv_error_string(result)));
      return false;
    }

    ::mpv_render_context_set_update_callback(
        render_context_,
        [](void* context) {
          auto* renderer =
              reinterpret_cast<WindowsOpenGLVideoRenderer*>(context);
          if (renderer != nullptr) {
            renderer->RequestRender();
          }
        },
        this);
    return true;
  }

  void RenderFrameOnRenderThread() {
    if (destroyed_.load() || render_context_ == nullptr ||
        gl_context_ == nullptr || dc_ == nullptr) {
      return;
    }
    RECT client_rect = {};
    if (!::GetClientRect(hwnd_, &client_rect)) {
      return;
    }
    const int width =
        std::max(1, static_cast<int>(client_rect.right - client_rect.left));
    const int height =
        std::max(1, static_cast<int>(client_rect.bottom - client_rect.top));

    if (!::wglMakeCurrent(dc_, gl_context_)) {
      LogRenderFailure("wglMakeCurrent", ::GetLastError());
      return;
    }

    ::glViewport(0, 0, width, height);
    ::glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    ::glClear(GL_COLOR_BUFFER_BIT);

    const uint64_t update_flags =
        ::mpv_render_context_update(render_context_);
    mpv_opengl_fbo fbo = {0, width, height, 0};
    int flip_y = 1;
    int depth = 8;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_DEPTH, &depth},
        {MPV_RENDER_PARAM_INVALID, nullptr},
    };
    const int result = ::mpv_render_context_render(render_context_, params);
    if (result < 0) {
      LogNativeVideo("renderer frame failed: " +
                     std::string(::mpv_error_string(result)));
      return;
    }

    if (!::SwapBuffers(dc_)) {
      LogRenderFailure("SwapBuffers", ::GetLastError());
      return;
    }
    ::mpv_render_context_report_swap(render_context_);

    ++rendered_frames_;
    if (rendered_frames_ <= 3) {
      LogNativeVideo("renderer frame ok frame=" +
                     std::to_string(rendered_frames_) + " size=" +
                     std::to_string(width) + "x" + std::to_string(height) +
                     " updateFlags=" + std::to_string(update_flags));
    }
  }

 private:
  bool EnsurePixelFormat() {
    const int current = ::GetPixelFormat(dc_);
    if (current > 0) {
      return true;
    }

    PIXELFORMATDESCRIPTOR descriptor = {};
    descriptor.nSize = sizeof(descriptor);
    descriptor.nVersion = 1;
    descriptor.dwFlags =
        PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    descriptor.iPixelType = PFD_TYPE_RGBA;
    descriptor.cColorBits = 32;
    descriptor.cDepthBits = 24;
    descriptor.cStencilBits = 8;
    descriptor.iLayerType = PFD_MAIN_PLANE;

    const int pixel_format = ::ChoosePixelFormat(dc_, &descriptor);
    if (pixel_format <= 0) {
      LogNativeVideo("renderer init failed: ChoosePixelFormat error=" +
                     std::to_string(::GetLastError()));
      return false;
    }
    if (!::SetPixelFormat(dc_, pixel_format, &descriptor)) {
      LogNativeVideo("renderer init failed: SetPixelFormat error=" +
                     std::to_string(::GetLastError()));
      return false;
    }
    return true;
  }

  void LogRenderFailure(const char* operation, DWORD error) {
    ++render_failures_;
    if (render_failures_ <= 3) {
      LogNativeVideo(std::string("renderer frame failed: ") + operation +
                     " error=" + std::to_string(error));
    }
  }

  void DestroyOpenGLOnRenderThread() {
    if (render_context_ != nullptr) {
      ::wglMakeCurrent(dc_, gl_context_);
      ::mpv_render_context_set_update_callback(render_context_, nullptr,
                                               nullptr);
      ::mpv_render_context_free(render_context_);
      render_context_ = nullptr;
    }
    if (gl_context_ != nullptr) {
      ::wglMakeCurrent(nullptr, nullptr);
      ::wglDeleteContext(gl_context_);
      gl_context_ = nullptr;
    }
  }

  void Destroy() {
    if (destroyed_.exchange(true)) {
      return;
    }

    {
      std::lock_guard<std::mutex> lock(render_signal_mutex_);
      stop_render_thread_ = true;
      render_requested_ = true;
    }
    render_cv_.notify_one();
    if (render_thread_.joinable()) {
      render_thread_.join();
    }

    if (hwnd_ != nullptr &&
        reinterpret_cast<WindowsOpenGLVideoRenderer*>(
            ::GetWindowLongPtrW(hwnd_, GWLP_USERDATA)) == this) {
      ::SetWindowLongPtrW(hwnd_, GWLP_USERDATA, 0);
    }
    if (dc_ != nullptr && hwnd_ != nullptr) {
      ::ReleaseDC(hwnd_, dc_);
      dc_ = nullptr;
    }
    LogNativeVideo("renderer destroyed hwnd=" +
                   std::to_string(HwndToInt64(hwnd_)) + " player=" +
                   std::to_string(player_handle_) + " frames=" +
                   std::to_string(rendered_frames_));
  }

  HWND hwnd_ = nullptr;
  HDC dc_ = nullptr;
  HGLRC gl_context_ = nullptr;
  int64_t player_handle_ = 0;
  mpv_handle* mpv_ = nullptr;
  mpv_render_context* render_context_ = nullptr;
  std::atomic_bool destroyed_{false};
  std::thread render_thread_;
  std::mutex render_signal_mutex_;
  std::condition_variable render_cv_;
  bool render_requested_ = false;
  bool stop_render_thread_ = false;
  uint64_t rendered_frames_ = 0;
  uint64_t render_failures_ = 0;
};

namespace {

std::atomic<uint32_t> g_overlay_input_log_count{0};

bool IsOverlayInputProbeEnabled() {
  static const bool enabled = [] {
    wchar_t value[8] = {};
    const DWORD length = ::GetEnvironmentVariableW(
        L"NIPAPLAY_WINDOWS_NATIVE_VIDEO_INPUT_PROBE", value,
        static_cast<DWORD>(std::size(value)));
    return length > 0 && value[0] == L'1';
  }();
  return enabled;
}

void LogOverlayInputMessage(HWND hwnd,
                            const char* name,
                            WPARAM wparam,
                            LPARAM lparam) {
  if (!IsOverlayInputProbeEnabled()) {
    return;
  }
  const uint32_t count = g_overlay_input_log_count.fetch_add(1);
  if (count >= 64) {
    return;
  }
  LogNativeVideo(std::string("VIDEO_WINDOW_RECEIVED_INPUT ") + name +
                 " hwnd=" +
                 std::to_string(HwndToInt64(hwnd)) + " wparam=" +
                 std::to_string(static_cast<uint64_t>(wparam)) + " lparam=" +
                 std::to_string(static_cast<int64_t>(lparam)) + " screen=(" +
                 std::to_string(GET_X_LPARAM(lparam)) + "," +
                 std::to_string(GET_Y_LPARAM(lparam)) + ")");
}

LRESULT CALLBACK OverlayWndProc(HWND hwnd,
                                UINT message,
                                WPARAM wparam,
                                LPARAM lparam) {
  auto* renderer = reinterpret_cast<WindowsOpenGLVideoRenderer*>(
      ::GetWindowLongPtrW(hwnd, GWLP_USERDATA));
  switch (message) {
    case kRenderMessage:
      if (renderer != nullptr) {
        renderer->Render();
      }
      return 0;
    case WM_PAINT: {
      PAINTSTRUCT paint = {};
      ::BeginPaint(hwnd, &paint);
      if (renderer != nullptr) {
        renderer->Render();
      }
      ::EndPaint(hwnd, &paint);
      return 0;
    }
    case WM_SIZE:
    case WM_DISPLAYCHANGE:
      if (renderer != nullptr) {
        renderer->HostWindowDidChange();
      }
      return 0;
    case WM_MOUSEACTIVATE:
      LogOverlayInputMessage(hwnd, "WM_MOUSEACTIVATE", wparam, lparam);
      return MA_NOACTIVATE;
    case WM_NCHITTEST:
      LogOverlayInputMessage(hwnd, "WM_NCHITTEST", wparam, lparam);
      return HTTRANSPARENT;
    case WM_SETCURSOR:
      LogOverlayInputMessage(hwnd, "WM_SETCURSOR", wparam, lparam);
      return FALSE;
    case WM_MOUSEMOVE:
    case WM_LBUTTONDOWN:
    case WM_LBUTTONUP:
    case WM_LBUTTONDBLCLK:
    case WM_RBUTTONDOWN:
    case WM_RBUTTONUP:
    case WM_RBUTTONDBLCLK:
    case WM_MBUTTONDOWN:
    case WM_MBUTTONUP:
    case WM_MBUTTONDBLCLK:
    case WM_MOUSEHWHEEL:
    case WM_MOUSEWHEEL:
      LogOverlayInputMessage(hwnd, "mouse-message", wparam, lparam);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    default:
      return ::DefWindowProc(hwnd, message, wparam, lparam);
  }
}

void RegisterOverlayWindowClass() {
  static bool registered = false;
  if (registered) {
    return;
  }

  WNDCLASSW window_class = {};
  window_class.style = CS_OWNDC | CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
  window_class.hCursor = ::LoadCursor(nullptr, IDC_ARROW);
  window_class.hInstance = ::GetModuleHandle(nullptr);
  window_class.lpszClassName = kOverlayWindowClassName;
  window_class.lpfnWndProc = OverlayWndProc;
  window_class.hbrBackground = reinterpret_cast<HBRUSH>(::GetStockObject(
      BLACK_BRUSH));

  ::RegisterClassW(&window_class);
  registered = true;
}

}  // namespace

WindowsNativeVideoPlugin::WindowsNativeVideoPlugin(
    HWND host_window,
    HWND flutter_view,
    flutter::BinaryMessenger* messenger)
    : host_window_(host_window),
      flutter_view_(flutter_view),
      main_host_window_(host_window),
      main_flutter_view_(flutter_view) {
  LogNativeVideo("plugin created host=" + std::to_string(HwndToInt64(host_window_)) +
                 " flutterView=" + std::to_string(HwndToInt64(flutter_view_)));
  if (!HasTransparentWindowBackgroundOverride()) {
    host_transparent_background_enabled_ =
        ApplyTransparentAccent(host_window_, "HostWindow");
  } else {
    LogNativeVideo("HostWindow transparent accent disabled by environment");
  }
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
  desktop_window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kDesktopWindowChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  desktop_window_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleDesktopWindowMethodCall(call, std::move(result));
      });
}

WindowsNativeVideoPlugin::~WindowsNativeVideoPlugin() {
  Destroy();
}

void WindowsNativeVideoPlugin::SetFlutterView(HWND flutter_view) {
  flutter_view_ = flutter_view;
  LogNativeVideo("SetFlutterView flutterView=" +
                 std::to_string(HwndToInt64(flutter_view_)));
}

void WindowsNativeVideoPlugin::HostWindowDidChange() {
  SyncOverlayWindowToHost(false);
}

void WindowsNativeVideoPlugin::HostWindowDidActivate() {
  host_window_active_ = true;
  SyncOverlayWindowToHost(true);
}

void WindowsNativeVideoPlugin::HostWindowDidDeactivate() {
  host_window_active_ = false;
  HideOverlayWindow(false);
}

void WindowsNativeVideoPlugin::HostWindowZOrderDidChange() {
  SyncOverlayWindowToHost(true);
}

void WindowsNativeVideoPlugin::Destroy() {
  LogNativeVideo("Destroy overlay=" + std::to_string(HwndToInt64(overlay_window_)) +
                 " attachedPlayer=" + std::to_string(attached_player_handle_) +
                 " visible=" + std::to_string(overlay_visible_ ? 1 : 0));
  video_renderer_.reset();
  if (overlay_window_ != nullptr) {
    ::DestroyWindow(overlay_window_);
    overlay_window_ = nullptr;
  }
  overlay_frame_generation_.reset();
  overlay_frame_rect_valid_ = false;
  overlay_physical_rect_valid_ = false;
  overlay_visible_ = false;
  attached_player_handle_ = 0;
}

void WindowsNativeVideoPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      method_call.arguments()
          ? std::get_if<flutter::EncodableMap>(method_call.arguments())
          : nullptr;
  if (!args) {
    result->Error("INVALID_ARGUMENTS", "Arguments are required");
    return;
  }

  const auto view_id = ReadInt64(*args, "viewId");
  if (!view_id.has_value() || view_id.value() != kWindowHostedVideoSurfaceId) {
    result->Error("VIEW_NOT_FOUND",
                  "Only the window-hosted Windows native video surface is "
                  "supported");
    return;
  }

  const auto& method = method_call.method_name();
  if (method == "getViewHandles") {
    if (EnsureOverlayWindow() == nullptr) {
      result->Error("WINDOW_CREATE_FAILED",
                    "Unable to create Windows native video overlay");
      return;
    }
    LogNativeVideo("getViewHandles " + BuildDiagnosticsSummary());
    result->Success(flutter::EncodableValue(BuildHandles()));
    return;
  }

  if (method == "attachPlayer") {
    if (EnsureOverlayWindow() == nullptr) {
      result->Error("WINDOW_CREATE_FAILED",
                    "Unable to create Windows native video overlay");
      return;
    }
    const int64_t player_handle = ReadInt64(*args, "playerHandle").value_or(0);
    if (player_handle <= 0) {
      result->Error("INVALID_PLAYER_HANDLE",
                    "A valid libmpv player handle is required");
      return;
    }
    if (attached_player_handle_ == player_handle && video_renderer_ != nullptr) {
      video_renderer_->HostWindowDidChange();
      LogNativeVideo("attachPlayer reused renderer player=" +
                     std::to_string(attached_player_handle_) + " " +
                     BuildDiagnosticsSummary());
      result->Success(flutter::EncodableValue(BuildHandles()));
      return;
    }

    video_renderer_.reset();
    auto renderer =
        std::make_unique<WindowsOpenGLVideoRenderer>(overlay_window_,
                                                     player_handle);
    if (!renderer->Initialize()) {
      attached_player_handle_ = 0;
      result->Error("RENDERER_CREATE_FAILED",
                    "Unable to create Windows libmpv OpenGL renderer");
      return;
    }
    video_renderer_ = std::move(renderer);
    attached_player_handle_ = player_handle;
    LogNativeVideo("attachPlayer player=" +
                   std::to_string(attached_player_handle_) + " " +
                   BuildDiagnosticsSummary());
    result->Success(flutter::EncodableValue(BuildHandles()));
    return;
  }

  if (method == "detachPlayer") {
    LogNativeVideo("detachPlayer player=" +
                   std::to_string(attached_player_handle_) + " overlay=" +
                   std::to_string(HwndToInt64(overlay_window_)));
    video_renderer_.reset();
    HideOverlayWindow();
    attached_player_handle_ = 0;
    result->Success();
    return;
  }

  if (method == "setOverlayFrame") {
    UpdateOverlayFrame(*args);
    result->Success();
    return;
  }

  if (method == "getViewDiagnostics") {
    result->Success(flutter::EncodableValue(BuildDiagnostics()));
    return;
  }

  result->NotImplemented();
}

void WindowsNativeVideoPlugin::HandleDesktopWindowMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      method_call.arguments()
          ? std::get_if<flutter::EncodableMap>(method_call.arguments())
          : nullptr;
  if (!args) {
    result->Error("INVALID_ARGUMENTS", "Arguments are required");
    return;
  }
  HWND window = ResolveFlutterRegularHostWindow();
  if (window == nullptr) {
    result->Error("WINDOW_NOT_FOUND",
                  "No same-engine Flutter secondary window is available");
    return;
  }

  const auto& method = method_call.method_name();
  if (method == "configureWindow") {
    if (ReadBool(*args, "frameless")) {
      MakeDetachedWindowFrameless(window);
    }
    SetDetachedWindowAspectRatio(window, ReadDouble(*args, "aspectRatio"));
    SetDetachedWindowClientSize(window, ReadDouble(*args, "width"),
                                ReadDouble(*args, "height"));
    const bool always_on_top = ReadBool(*args, "alwaysOnTop");
    ::SetWindowPos(window, always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0,
                   0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    result->Success(flutter::EncodableValue(always_on_top));
    return;
  }
  if (method == "setAspectRatio") {
    SetDetachedWindowAspectRatio(window, ReadDouble(*args, "aspectRatio"));
    result->Success();
    return;
  }
  if (method == "setAlwaysOnTop") {
    const bool always_on_top = ReadBool(*args, "alwaysOnTop");
    ::SetWindowPos(window, always_on_top ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0,
                   0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    result->Success(flutter::EncodableValue(always_on_top));
    return;
  }
  if (method == "setPictureInPictureMode") {
    const bool enabled = ReadBool(*args, "enabled");
    const std::string placement =
        ReadString(*args, "placement", "topRight");
    SetDetachedWindowPictureInPicture(window, *args);
    LogNativeVideo(
        "picture-in-picture enabled=" + std::to_string(enabled ? 1 : 0) +
        " placement=" + placement +
        " aspect=" + std::to_string(ReadDouble(*args, "aspectRatio")));
    result->Success();
    return;
  }
  if (method == "startDragging") {
    ::ReleaseCapture();
    ::SendMessageW(window, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    result->Success();
    return;
  }
  if (method == "updateDragging" || method == "endDragging") {
    result->Success();
    return;
  }
  result->NotImplemented();
}

HWND WindowsNativeVideoPlugin::EnsureOverlayWindow() {
  if (overlay_window_ != nullptr) {
    return overlay_window_;
  }
  if (host_window_ == nullptr) {
    return nullptr;
  }
  if (!host_transparent_background_enabled_ &&
      !HasTransparentWindowBackgroundOverride()) {
    host_transparent_background_enabled_ =
        ApplyTransparentAccent(host_window_, "HostWindow");
  }

  RegisterOverlayWindowClass();
  overlay_window_ = ::CreateWindowExW(
      WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW,
      kOverlayWindowClassName, L"NipaPlay Native Video",
      WS_POPUP | WS_CLIPCHILDREN | WS_CLIPSIBLINGS, 0, 0, 1, 1, nullptr,
      nullptr, ::GetModuleHandle(nullptr), nullptr);

  if (overlay_window_ != nullptr) {
    const LONG_PTR ex_style =
        ::GetWindowLongPtrW(overlay_window_, GWL_EXSTYLE);
    const LONG_PTR no_activate_style =
        ex_style | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW;
    if (no_activate_style != ex_style) {
      ::SetWindowLongPtrW(overlay_window_, GWL_EXSTYLE, no_activate_style);
      ::SetWindowPos(overlay_window_, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                         SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
    ::ShowWindow(overlay_window_, SW_HIDE);
    LogNativeVideo("EnsureOverlayWindow created overlay=" +
                   std::to_string(HwndToInt64(overlay_window_)) + " host=" +
                   std::to_string(HwndToInt64(host_window_)) + " style=" +
                   std::to_string(static_cast<int64_t>(
                       ::GetWindowLongPtrW(overlay_window_, GWL_STYLE))) +
                   " exStyle=" +
                   std::to_string(static_cast<int64_t>(
                       ::GetWindowLongPtrW(overlay_window_, GWL_EXSTYLE))) +
                   " noActivate=1 hitTestTransparent=1 topLevelPopup=1");
  } else {
    LogNativeVideo("EnsureOverlayWindow failed host=" +
                   std::to_string(HwndToInt64(host_window_)) +
                   " error=" + std::to_string(::GetLastError()));
  }
  return overlay_window_;
}

void WindowsNativeVideoPlugin::HideOverlayWindow(bool reset_generation) {
  if (overlay_window_ == nullptr) {
    return;
  }
  LogNativeVideo("HideOverlayWindow overlay=" +
                 std::to_string(HwndToInt64(overlay_window_)) +
                 " generation=" +
                 OptionalInt64ToString(overlay_frame_generation_) +
                 " resetGeneration=" + std::to_string(reset_generation ? 1 : 0));
  if (reset_generation) {
    overlay_frame_generation_.reset();
    overlay_frame_rect_valid_ = false;
    overlay_physical_rect_valid_ = false;
  }
  overlay_visible_ = false;
  if (overlay_window_ != nullptr) {
    ::SetWindowPos(overlay_window_, nullptr, 0, 0, 0, 0,
                   SWP_HIDEWINDOW | SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE |
                       SWP_NOZORDER);
  }
}

void WindowsNativeVideoPlugin::UpdateOverlayFrame(
    const flutter::EncodableMap& args) {
  if (const auto flutter_view_id = ReadInt64(args, "flutterViewId")) {
    UpdateHostWindowForFlutterView(flutter_view_id.value());
  }
  const bool visible = ReadBool(args, "visible", true);
  const auto generation = ReadInt64(args, "generation");
  if (!visible && generation.has_value() &&
      overlay_frame_generation_.has_value() &&
      generation.value() != overlay_frame_generation_.value()) {
    LogNativeVideo("setOverlayFrame ignored stale hide generation=" +
                   OptionalInt64ToString(generation) + " active=" +
                   OptionalInt64ToString(overlay_frame_generation_));
    return;
  }

  const double width = ReadDouble(args, "width");
  const double height = ReadDouble(args, "height");
  if (!visible || width <= 0.0 || height <= 0.0) {
    HideOverlayWindow();
    return;
  }

  const HWND overlay = EnsureOverlayWindow();
  if (overlay == nullptr) {
    LogNativeVideo("setOverlayFrame failed: overlay unavailable");
    return;
  }

  if (!HostWindowCanShowOverlay(host_window_, host_window_active_)) {
    HideOverlayWindow(false);
    return;
  }

  const bool was_visible = overlay_visible_;
  const bool generation_changed =
      generation.has_value() &&
      (!overlay_frame_generation_.has_value() ||
       generation.value() != overlay_frame_generation_.value());
  if (generation.has_value()) {
    overlay_frame_generation_ = generation.value();
  }

  overlay_frame_rect_valid_ = true;
  overlay_frame_logical_x_ = ReadDouble(args, "x");
  overlay_frame_logical_y_ = ReadDouble(args, "y");
  overlay_frame_logical_width_ = width;
  overlay_frame_logical_height_ = height;

  SyncOverlayWindowToHost(!was_visible || generation_changed);
}

void WindowsNativeVideoPlugin::UpdateHostWindowForFlutterView(
    int64_t flutter_view_id) {
  HWND next_host = main_host_window_;
  HWND next_flutter_view = main_flutter_view_;
  if (flutter_view_id != 0) {
    next_host = ResolveFlutterRegularHostWindow();
    if (next_host == nullptr) {
      return;
    }
    next_flutter_view = ::FindWindowExW(
        next_host, nullptr, kFlutterViewWindowClassName, nullptr);
  }

  const bool next_host_active = ::GetForegroundWindow() == next_host;
  if (host_window_ == next_host) {
    host_window_active_ = next_host_active;
    active_flutter_view_id_ = flutter_view_id;
    return;
  }

  HideOverlayWindow(false);
  host_window_ = next_host;
  flutter_view_ = next_flutter_view;
  active_flutter_view_id_ = flutter_view_id;
  host_window_active_ = next_host_active;
  host_transparent_background_enabled_ = false;
  overlay_physical_rect_valid_ = false;
  LogNativeVideo("moved native video host to flutterViewId=" +
                 std::to_string(flutter_view_id) + " host=" +
                 std::to_string(HwndToInt64(host_window_)) + " flutterView=" +
                 std::to_string(HwndToInt64(flutter_view_)));
}

void WindowsNativeVideoPlugin::SyncOverlayWindowToHost(bool force_log) {
  if (overlay_window_ == nullptr || !overlay_frame_rect_valid_) {
    return;
  }

  if (!HostWindowCanShowOverlay(host_window_, host_window_active_)) {
    HideOverlayWindow(false);
    return;
  }

  POINT client_origin = {};
  if (!HostClientOriginOnScreen(host_window_, &client_origin)) {
    LogNativeVideo("syncOverlayFrame failed: ClientToScreen error=" +
                   std::to_string(::GetLastError()));
    return;
  }

  const int x =
      client_origin.x + LogicalToPhysical(host_window_, overlay_frame_logical_x_);
  const int y =
      client_origin.y + LogicalToPhysical(host_window_, overlay_frame_logical_y_);
  const int w =
      std::max(1, LogicalToPhysical(host_window_, overlay_frame_logical_width_));
  const int h =
      std::max(1, LogicalToPhysical(host_window_, overlay_frame_logical_height_));
  const bool rect_changed = !overlay_physical_rect_valid_ ||
      overlay_physical_x_ != x || overlay_physical_y_ != y ||
      overlay_physical_width_ != w || overlay_physical_height_ != h;
  const bool size_changed = !overlay_physical_rect_valid_ ||
      overlay_physical_width_ != w || overlay_physical_height_ != h;
  const bool should_update_z_order = force_log || !overlay_visible_;
  if (!rect_changed && overlay_visible_ && !should_update_z_order) {
    return;
  }

  const HWND insert_after = should_update_z_order
                                ? ResolveOverlayInsertAfter(host_window_)
                                : nullptr;
  UINT flags = SWP_NOACTIVATE | SWP_SHOWWINDOW;
  if (!should_update_z_order) {
    flags |= SWP_NOZORDER;
  }
  const BOOL moved =
      ::SetWindowPos(overlay_window_, insert_after, x, y, w, h, flags);
  if (force_log || !overlay_visible_ || !moved) {
    LogNativeVideo("setOverlayFrame visible=1 generation=" +
                   OptionalInt64ToString(overlay_frame_generation_) +
                   " logical=(" + std::to_string(overlay_frame_logical_x_) +
                   "," + std::to_string(overlay_frame_logical_y_) + "," +
                   std::to_string(overlay_frame_logical_width_) + "x" +
                   std::to_string(overlay_frame_logical_height_) +
                   ") clientOrigin=(" + std::to_string(client_origin.x) + "," +
                   std::to_string(client_origin.y) + ") screenPhysical=(" +
                   std::to_string(x) + "," + std::to_string(y) + "," +
                   std::to_string(w) + "x" + std::to_string(h) +
                   ") overlay=" + std::to_string(HwndToInt64(overlay_window_)) +
                   " flutterView=" +
                   std::to_string(HwndToInt64(flutter_view_)) + " ok=" +
                   std::to_string(moved ? 1 : 0) + " error=" +
                   std::to_string(moved ? 0 : ::GetLastError()) +
                   " zOrder=" +
                   (IsOverlayAboveFlutterEnabled() ? "above" : "below-host"));
  }
  if (moved) {
    overlay_physical_rect_valid_ = true;
    overlay_physical_x_ = x;
    overlay_physical_y_ = y;
    overlay_physical_width_ = w;
    overlay_physical_height_ = h;
  }
  overlay_visible_ = true;
  if (size_changed && video_renderer_ != nullptr) {
    video_renderer_->HostWindowDidChange();
  }
}

flutter::EncodableMap WindowsNativeVideoPlugin::BuildHandles() const {
  flutter::EncodableMap result;
  result[flutter::EncodableValue("viewId")] =
      flutter::EncodableValue(kWindowHostedVideoSurfaceId);
  result[flutter::EncodableValue("surfaceReady")] =
      flutter::EncodableValue(true);
  result[flutter::EncodableValue("viewHandle")] =
      flutter::EncodableValue(static_cast<int64_t>(
          reinterpret_cast<intptr_t>(overlay_window_)));
  result[flutter::EncodableValue("inputHandle")] =
      flutter::EncodableValue(static_cast<int64_t>(0));
  result[flutter::EncodableValue("windowHandle")] =
      flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(host_window_)));
  return result;
}

flutter::EncodableMap WindowsNativeVideoPlugin::BuildDiagnostics() const {
  flutter::EncodableMap result = BuildHandles();
  result[flutter::EncodableValue("flutterViewHandle")] =
      flutter::EncodableValue(
          static_cast<int64_t>(reinterpret_cast<intptr_t>(flutter_view_)));
  result[flutter::EncodableValue("hostWindow")] =
      flutter::EncodableValue(BuildWindowDiagnostics(host_window_));
  result[flutter::EncodableValue("flutterViewWindow")] =
      flutter::EncodableValue(BuildWindowDiagnostics(flutter_view_));
  result[flutter::EncodableValue("overlayWindow")] =
      flutter::EncodableValue(BuildWindowDiagnostics(overlay_window_));
  result[flutter::EncodableValue("hitTest")] =
      flutter::EncodableValue(
          BuildHitTestDiagnostics(host_window_, overlay_window_));
  result[flutter::EncodableValue("foregroundWindowHandle")] =
      flutter::EncodableValue(HwndToInt64(::GetForegroundWindow()));
  result[flutter::EncodableValue("activeWindowHandle")] =
      flutter::EncodableValue(HwndToInt64(::GetActiveWindow()));
  result[flutter::EncodableValue("focusWindowHandle")] =
      flutter::EncodableValue(HwndToInt64(::GetFocus()));
  result[flutter::EncodableValue("captureWindowHandle")] =
      flutter::EncodableValue(HwndToInt64(::GetCapture()));
  result[flutter::EncodableValue("attachedPlayerHandle")] =
      flutter::EncodableValue(attached_player_handle_);
  result[flutter::EncodableValue("visible")] =
      flutter::EncodableValue(overlay_visible_);
  result[flutter::EncodableValue("rendererAttached")] =
      flutter::EncodableValue(video_renderer_ != nullptr);
  result[flutter::EncodableValue("overlayFrameGeneration")] =
      flutter::EncodableValue(overlay_frame_generation_.value_or(0));
  const LONG_PTR flutter_view_style =
      flutter_view_ != nullptr
          ? ::GetWindowLongPtrW(flutter_view_, GWL_EXSTYLE)
          : 0;
  result[flutter::EncodableValue("flutterViewLayered")] =
      flutter::EncodableValue((flutter_view_style & WS_EX_LAYERED) != 0);
  result[flutter::EncodableValue("hostTransparentBackground")] =
      flutter::EncodableValue(host_transparent_background_enabled_);
  result[flutter::EncodableValue("flutterViewTransparentBackground")] =
      flutter::EncodableValue(false);
  result[flutter::EncodableValue("flutterViewColorKey")] =
      flutter::EncodableValue(false);
  result[flutter::EncodableValue("transparentHostMode")] =
      flutter::EncodableValue(host_transparent_background_enabled_
                                  ? "host-accent-transparent-background"
                                  : "disabled");

  RECT rect = {};
  if (overlay_window_ != nullptr) {
    ::GetWindowRect(overlay_window_, &rect);
  }
  flutter::EncodableMap frame;
  frame[flutter::EncodableValue("left")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.left));
  frame[flutter::EncodableValue("top")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.top));
  frame[flutter::EncodableValue("right")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.right));
  frame[flutter::EncodableValue("bottom")] =
      flutter::EncodableValue(static_cast<int32_t>(rect.bottom));
  result[flutter::EncodableValue("windowRect")] =
      flutter::EncodableValue(frame);
  return result;
}

std::string WindowsNativeVideoPlugin::BuildDiagnosticsSummary() const {
  const LONG_PTR overlay_ex_style =
      overlay_window_ != nullptr
          ? ::GetWindowLongPtrW(overlay_window_, GWL_EXSTYLE)
          : 0;
  return "host=" + std::to_string(HwndToInt64(host_window_)) +
         " flutterView=" + std::to_string(HwndToInt64(flutter_view_)) +
         " overlay=" + std::to_string(HwndToInt64(overlay_window_)) +
         " overlayExStyle=" +
         std::to_string(static_cast<int64_t>(overlay_ex_style)) +
         " overlayInputTransparent=" +
         std::to_string((overlay_ex_style & WS_EX_TRANSPARENT) != 0 ? 1 : 0) +
         " hostTransparentBackground=" +
         std::to_string(host_transparent_background_enabled_ ? 1 : 0) +
         " flutterViewTransparentBackground=" +
         std::to_string(0) +
         " transparentHostMode=" +
         (host_transparent_background_enabled_
              ? "host-accent-transparent-background"
              : "disabled") +
         " attachedPlayer=" + std::to_string(attached_player_handle_) +
         " visible=" + std::to_string(overlay_visible_ ? 1 : 0) +
         " renderer=" + std::to_string(video_renderer_ != nullptr ? 1 : 0) +
         " generation=" + OptionalInt64ToString(overlay_frame_generation_);
}
