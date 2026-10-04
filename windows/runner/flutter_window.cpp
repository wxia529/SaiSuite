#include "flutter_window.h"

#include <optional>
#include <thread>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

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
  desktop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "saisuite/windows",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "appInfo") {
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("version"), flutter::EncodableValue(std::to_string(FLUTTER_VERSION_MAJOR) + "." + std::to_string(FLUTTER_VERSION_MINOR) + "." + std::to_string(FLUTTER_VERSION_PATCH))},
              {flutter::EncodableValue("versionCode"), flutter::EncodableValue(FLUTTER_VERSION_BUILD)},
              {flutter::EncodableValue("variant"), flutter::EncodableValue("windows-x64")}}));
        } else if (call.method_name() == "fullScreen") {
          const bool enabled = call.arguments() && std::get_if<bool>(call.arguments()) && std::get<bool>(*call.arguments());
          if (enabled != fullscreen_) {
            HWND hwnd = GetHandle();
            if (enabled) {
              original_style_ = GetWindowLongPtrW(hwnd, GWL_STYLE);
              GetWindowPlacement(hwnd, &original_placement_);
              MONITORINFO monitor{sizeof(MONITORINFO)};
              GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &monitor);
              SetWindowLongPtrW(hwnd, GWL_STYLE, original_style_ & ~WS_OVERLAPPEDWINDOW);
              SetWindowPos(hwnd, HWND_TOP, monitor.rcMonitor.left, monitor.rcMonitor.top,
                  monitor.rcMonitor.right - monitor.rcMonitor.left, monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                  SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
            } else {
              SetWindowLongPtrW(hwnd, GWL_STYLE, original_style_);
              SetWindowPlacement(hwnd, &original_placement_);
              SetWindowPos(hwnd, nullptr, 0, 0, 0, 0, SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER);
            }
            fullscreen_ = enabled;
          }
          result->Success();
        } else if (call.method_name() == "timerAlert") {
          std::thread([]() {
            MessageBeep(MB_ICONINFORMATION);
            MessageBoxW(nullptr, L"本阶段已结束，可以回到工具箱继续下一阶段。",
                        L"赛赛工具箱 · 番茄钟", MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
          }).detach();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
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

void FlutterWindow::OnDestroy() {
  desktop_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_CLOSE:
      if (desktop_channel_ && !closing_allowed_) {
        if (!close_requested_) {
          close_requested_ = true;
          auto finish = [this, hwnd](bool allowed) {
            close_requested_ = false;
            if (allowed) {
              closing_allowed_ = true;
              PostMessageW(hwnd, WM_CLOSE, 0, 0);
            }
          };
          desktop_channel_->InvokeMethod("requestClose", nullptr,
              std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
                  [finish](const flutter::EncodableValue* value) {
                    finish(value && std::get_if<bool>(value) && std::get<bool>(*value));
                  },
                  [finish](const auto&, const auto&, const auto*) { finish(false); },
                  [finish]() { finish(true); }));
        }
        return 0;
      }
      break;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
