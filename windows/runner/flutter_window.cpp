#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

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
  RegisterWindowControls();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::RegisterWindowControls() {
  window_controls_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "tag_music/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_controls_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const HWND hwnd = GetHandle();
        const auto& method = call.method_name();
        if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
        } else if (method == "drag") {
          // Let Windows run its normal title-bar move and snap behavior.
          POINT cursor;
          const int primary_button =
              GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
          if ((GetAsyncKeyState(primary_button) & 0x8000) &&
              GetCursorPos(&cursor)) {
            ReleaseCapture();
            PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION,
                        MAKELPARAM(cursor.x, cursor.y));
          }
          result->Success();
        } else {
          WPARAM command;
          if (method == "minimize") {
            command = SC_MINIMIZE;
          } else if (method == "toggleMaximize") {
            command = IsZoomed(hwnd) ? SC_RESTORE : SC_MAXIMIZE;
          } else if (method == "close") {
            command = SC_CLOSE;
          } else {
            result->NotImplemented();
            return;
          }
          PostMessage(hwnd, WM_SYSCOMMAND, command, 0);
          result->Success();
        }
      });
}

void FlutterWindow::OnDestroy() {
  if (window_controls_) {
    window_controls_->SetMethodCallHandler(nullptr);
    window_controls_.reset();
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
  if (message == WM_SIZE && wparam != SIZE_MINIMIZED && window_controls_) {
    const bool maximized = IsZoomed(hwnd) != FALSE;
    if (maximized != maximized_) {
      maximized_ = maximized;
      window_controls_->InvokeMethod(
          "maximizedChanged",
          std::make_unique<flutter::EncodableValue>(maximized));
    }
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
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
