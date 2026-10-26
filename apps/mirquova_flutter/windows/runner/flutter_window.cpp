#include "flutter_window.h"

#include <flutter/standard_method_codec.h>
#include <shellapi.h>

#include <algorithm>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

bool IsReleasePage(const std::string& url) {
  const std::string prefix =
      "https://github.com/STVN-PRDGO/Mirquova/releases/tag/";
  if (url.compare(0, prefix.size(), prefix) != 0) {
    return false;
  }
  const std::string tag = url.substr(prefix.size());
  const auto is_alphanumeric = [](char value) {
    return (value >= 'a' && value <= 'z') ||
           (value >= 'A' && value <= 'Z') ||
           (value >= '0' && value <= '9');
  };
  return !tag.empty() && tag.size() <= 128 && is_alphanumeric(tag.front()) &&
         std::all_of(tag.begin(), tag.end(), [&](char value) {
           return is_alphanumeric(value) || value == '.' || value == '_' ||
                  value == '+' || value == '-';
         });
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
  app_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "dev.mirquova/app",
          &flutter::StandardMethodCodec::GetInstance());
  app_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getBuildInfo") {
          const std::string package_version = FLUTTER_VERSION;
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("version"),
               flutter::EncodableValue(
                   package_version.substr(0, package_version.find('+')))},
              {flutter::EncodableValue("buildNumber"),
               flutter::EncodableValue(std::to_string(FLUTTER_VERSION_BUILD))},
          }));
        } else if (call.method_name() == "openReleasePage") {
          const auto* argument = call.arguments();
          const auto* url = argument ? std::get_if<std::string>(argument) : nullptr;
          if (!url || !IsReleasePage(*url)) {
            result->Error("invalid_release_url",
                          "Only Mirquova GitHub release pages can be opened.");
            return;
          }
          // Validation above permits ASCII only. Pass the URL directly to the
          // operating system browser association, without constructing a command.
          const std::wstring wide_url(url->begin(), url->end());
          const HINSTANCE opened = ShellExecuteW(nullptr, L"open", wide_url.c_str(),
                                                nullptr, nullptr, SW_SHOWNORMAL);
          if (reinterpret_cast<INT_PTR>(opened) <= 32) {
            result->Error("browser_unavailable",
                          "This release page could not be opened.");
          } else {
            result->Success();
          }
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
  app_channel_ = nullptr;
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
