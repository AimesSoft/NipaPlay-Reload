#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void* controller) {
    auto* flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController*>(controller);
    auto* registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });
  HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view);
  windows_native_video_plugin_ = std::make_unique<WindowsNativeVideoPlugin>(
      GetHandle(), flutter_view, flutter_controller_->engine()->messenger());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (windows_native_video_plugin_) {
    windows_native_video_plugin_->Destroy();
    windows_native_video_plugin_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_ACTIVATEAPP:
      if (windows_native_video_plugin_) {
        if (wparam != FALSE) {
          windows_native_video_plugin_->HostWindowDidActivate();
        } else {
          windows_native_video_plugin_->HostWindowDidDeactivate();
        }
      }
      break;
    case WM_WINDOWPOSCHANGED: {
      const auto* window_pos = reinterpret_cast<WINDOWPOS*>(lparam);
      if (windows_native_video_plugin_ &&
          (window_pos == nullptr || (window_pos->flags & SWP_NOZORDER) == 0)) {
        windows_native_video_plugin_->HostWindowZOrderDidChange();
      }
      break;
    }
    case WM_MOVE:
    case WM_MOVING:
    case WM_SIZE:
    case WM_SIZING:
    case WM_EXITSIZEMOVE:
    case WM_SHOWWINDOW:
    case WM_DPICHANGED:
      if (windows_native_video_plugin_) {
        windows_native_video_plugin_->HostWindowDidChange();
      }
      break;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
