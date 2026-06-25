#ifndef RUNNER_WINDOWS_NATIVE_VIDEO_H_
#define RUNNER_WINDOWS_NATIVE_VIDEO_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <optional>
#include <string>

#include <windows.h>

namespace flutter {
class BinaryMessenger;
template <typename T>
class MethodResult;
}  // namespace flutter

class WindowsOpenGLVideoRenderer;

class WindowsNativeVideoPlugin {
 public:
  WindowsNativeVideoPlugin(HWND host_window,
                           HWND flutter_view,
                           flutter::BinaryMessenger* messenger);
  ~WindowsNativeVideoPlugin();

  WindowsNativeVideoPlugin(const WindowsNativeVideoPlugin&) = delete;
  WindowsNativeVideoPlugin& operator=(const WindowsNativeVideoPlugin&) = delete;

  void SetFlutterView(HWND flutter_view);
  void HostWindowDidChange();
  void HostWindowDidActivate();
  void HostWindowDidDeactivate();
  void HostWindowZOrderDidChange();
  void Destroy();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND EnsureOverlayWindow();
  void HideOverlayWindow(bool reset_generation = true);
  void UpdateOverlayFrame(const flutter::EncodableMap& args);
  void SyncOverlayWindowToHost(bool force_log = false);
  flutter::EncodableMap BuildHandles() const;
  flutter::EncodableMap BuildDiagnostics() const;
  std::string BuildDiagnosticsSummary() const;

  HWND host_window_ = nullptr;
  HWND flutter_view_ = nullptr;
  HWND overlay_window_ = nullptr;
  std::optional<int64_t> overlay_frame_generation_;
  bool overlay_frame_rect_valid_ = false;
  double overlay_frame_logical_x_ = 0.0;
  double overlay_frame_logical_y_ = 0.0;
  double overlay_frame_logical_width_ = 0.0;
  double overlay_frame_logical_height_ = 0.0;
  bool overlay_physical_rect_valid_ = false;
  int overlay_physical_x_ = 0;
  int overlay_physical_y_ = 0;
  int overlay_physical_width_ = 0;
  int overlay_physical_height_ = 0;
  int64_t attached_player_handle_ = 0;
  bool overlay_visible_ = false;
  bool host_window_active_ = true;
  bool host_transparent_background_enabled_ = false;
  std::unique_ptr<WindowsOpenGLVideoRenderer> video_renderer_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_WINDOWS_NATIVE_VIDEO_H_
