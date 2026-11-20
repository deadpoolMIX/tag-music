#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <strsafe.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayCallback = WM_APP + 1;
constexpr UINT kTrayIcon = 1;

enum TrayCommand : UINT {
  kShowWindow = 1,
  kPreviousTrack,
  kTogglePlayback,
  kNextTrack,
  kExit,
};

NOTIFYICONDATAW TrayIconData(HWND window) {
  NOTIFYICONDATAW icon = {};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = kTrayIcon;
  return icon;
}

bool AddTrayIcon(HWND window) {
  auto icon = TrayIconData(window);
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  icon.uCallbackMessage = kTrayCallback;
  icon.hIcon =
      LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  StringCchCopyW(icon.szTip, ARRAYSIZE(icon.szTip), L"Tag Music");
  if (!icon.hIcon || !Shell_NotifyIconW(NIM_ADD, &icon)) {
    return false;
  }
  icon.uVersion = NOTIFYICON_VERSION_4;
  if (Shell_NotifyIconW(NIM_SETVERSION, &icon)) {
    return true;
  }
  Shell_NotifyIconW(NIM_DELETE, &icon);
  return false;
}

void RemoveTrayIcon(HWND window) {
  auto icon = TrayIconData(window);
  Shell_NotifyIconW(NIM_DELETE, &icon);
}
}  // namespace

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
  tray_controls_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "tag_music/tray",
          &flutter::StandardMethodCodec::GetInstance());
  taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
  tray_icon_added_ = AddTrayIcon(GetHandle());
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
  tray_controls_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::RestoreFromTray(HWND window) {
  ShowWindow(window, IsIconic(window) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(window);
}

void FlutterWindow::ShowTrayMenu(HWND window) {
  const HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kShowWindow, L"打开 Tag Music");
  SetMenuDefaultItem(menu, kShowWindow, FALSE);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kPreviousTrack, L"上一首");
  AppendMenuW(menu, MF_STRING, kTogglePlayback, L"播放 / 暂停");
  AppendMenuW(menu, MF_STRING, kNextTrack, L"下一首");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kExit, L"退出");

  NOTIFYICONIDENTIFIER icon = {};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = kTrayIcon;
  RECT bounds = {};
  POINT anchor = {};
  if (SUCCEEDED(Shell_NotifyIconGetRect(&icon, &bounds))) {
    anchor = {bounds.left, bounds.top};
  } else {
    GetCursorPos(&anchor);
  }
  SetForegroundWindow(window);
  const UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON;
  const auto command =
      TrackPopupMenu(menu, flags, anchor.x, anchor.y, 0, window, nullptr);
  DestroyMenu(menu);
  if (!tray_controls_) {
    return;
  }
  PostMessageW(window, WM_NULL, 0, 0);

  switch (command) {
    case kShowWindow:
      RestoreFromTray(window);
      return;
    case kPreviousTrack:
      tray_controls_->InvokeMethod("previous", nullptr);
      break;
    case kTogglePlayback:
      tray_controls_->InvokeMethod("togglePlayback", nullptr);
      break;
    case kNextTrack:
      tray_controls_->InvokeMethod("next", nullptr);
      break;
    case kExit:
      DestroyWindow(window);
      return;
  }
  auto icon_data = TrayIconData(window);
  Shell_NotifyIconW(NIM_SETFOCUS, &icon_data);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (taskbar_created_ && message == taskbar_created_) {
    if (tray_icon_added_) {
      RemoveTrayIcon(hwnd);
    }
    tray_icon_added_ = AddTrayIcon(hwnd);
    return 0;
  }
  switch (message) {
    case WM_CLOSE:
      if (!tray_icon_added_) {
        tray_icon_added_ = AddTrayIcon(hwnd);
      }
      ShowWindow(hwnd, tray_icon_added_ ? SW_HIDE : SW_MINIMIZE);
      return 0;
    case kTrayCallback:
      switch (LOWORD(lparam)) {
        case WM_LBUTTONUP:
        case NIN_SELECT:
        case NIN_KEYSELECT:
          RestoreFromTray(hwnd);
          break;
        case WM_CONTEXTMENU:
          ShowTrayMenu(hwnd);
          break;
      }
      return 0;
    case WM_DESTROY:
      if (tray_icon_added_) {
        RemoveTrayIcon(hwnd);
        tray_icon_added_ = false;
      }
      break;
  }
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
