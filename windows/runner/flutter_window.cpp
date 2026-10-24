#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <cstring>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

std::string ReadArgument(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  if (found == map.end()) return {};
  const auto* value = std::get_if<std::string>(&found->second);
  return value == nullptr ? std::string() : *value;
}

bool HasArgument(const flutter::EncodableMap& map, const char* key) {
  const auto found = map.find(flutter::EncodableValue(key));
  return found != map.end() && std::get_if<std::string>(&found->second) != nullptr;
}

void WriteOffset(std::string& header, const char* key, size_t value) {
  const auto label = header.find(key);
  std::string digits = std::to_string(value);
  if (digits.size() < 8) digits.insert(0, 8 - digits.size(), '0');
  header.replace(label + std::strlen(key), 8, digits);
}

// CF_HTML offsets are bytes in the finished payload. The 8-digit fields keep
// the header length stable, so the offsets can be written before joining.
std::string HtmlClipboardPayload(const std::string& html) {
  std::string header =
      "Version:0.9\r\n"
      "StartHTML:00000000\r\n"
      "EndHTML:00000000\r\n"
      "StartFragment:00000000\r\n"
      "EndFragment:00000000\r\n";
  const std::string start = "<html>\r\n<body>\r\n<!--StartFragment-->";
  const std::string end = "<!--EndFragment-->\r\n</body>\r\n</html>";
  const size_t start_html = header.size();
  const size_t start_fragment = start_html + start.size();
  const size_t end_fragment = start_fragment + html.size();
  const size_t end_html = end_fragment + end.size();
  WriteOffset(header, "StartHTML:", start_html);
  WriteOffset(header, "EndHTML:", end_html);
  WriteOffset(header, "StartFragment:", start_fragment);
  WriteOffset(header, "EndFragment:", end_fragment);
  return header + start + html + end;
}

HGLOBAL CopyBytes(const void* bytes, size_t size) {
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, size);
  if (memory == nullptr) return nullptr;
  void* dest = GlobalLock(memory);
  if (dest == nullptr) {
    GlobalFree(memory);
    return nullptr;
  }
  std::memcpy(dest, bytes, size);
  GlobalUnlock(memory);
  return memory;
}

HGLOBAL Utf8ToClipboardText(const std::string& plain) {
  int chars = 1;
  if (!plain.empty()) {
    chars = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, plain.data(),
                                static_cast<int>(plain.size()), nullptr, 0);
    if (chars <= 0) return nullptr;
    chars += 1;
  }
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, static_cast<SIZE_T>(chars) * sizeof(wchar_t));
  if (memory == nullptr) return nullptr;
  auto* dest = static_cast<wchar_t*>(GlobalLock(memory));
  if (dest == nullptr) {
    GlobalFree(memory);
    return nullptr;
  }
  if (!plain.empty()) {
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, plain.data(),
                        static_cast<int>(plain.size()), dest, chars - 1);
  }
  dest[chars - 1] = L'\0';
  GlobalUnlock(memory);
  return memory;
}

bool SetRichClipboard(HWND owner, const std::string& plain, const std::string& html) {
  const UINT html_format = RegisterClipboardFormatW(L"HTML Format");
  if (html_format == 0) return false;
  std::string payload = HtmlClipboardPayload(html);
  payload.push_back('\0');
  HGLOBAL text_memory = Utf8ToClipboardText(plain);
  HGLOBAL html_memory = CopyBytes(payload.data(), payload.size());
  if (text_memory == nullptr || html_memory == nullptr) {
    if (text_memory != nullptr) GlobalFree(text_memory);
    if (html_memory != nullptr) GlobalFree(html_memory);
    return false;
  }
  if (!OpenClipboard(owner)) {
    GlobalFree(text_memory);
    GlobalFree(html_memory);
    return false;
  }
  EmptyClipboard();
  if (SetClipboardData(CF_UNICODETEXT, text_memory) == nullptr) {
    GlobalFree(text_memory);
    GlobalFree(html_memory);
    CloseClipboard();
    return false;
  }
  if (SetClipboardData(html_format, html_memory) == nullptr) {
    GlobalFree(html_memory);
    CloseClipboard();
    return false;
  }
  CloseClipboard();
  return true;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  InstallMenu();
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
  RegisterChannels();
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

void FlutterWindow::InstallMenu() {
  HMENU file = CreatePopupMenu();
  HMENU bar = CreateMenu();
  if (file == nullptr || bar == nullptr) {
    if (file != nullptr) DestroyMenu(file);
    if (bar != nullptr) DestroyMenu(bar);
    return;
  }
  AppendMenuW(file, MF_STRING, kNewConversationCommand,
              L"New Conversation\tCtrl+N");
  AppendMenuW(file, MF_STRING, kSettingsCommand, L"Settings...\tCtrl+,");
  AppendMenuW(bar, MF_POPUP, reinterpret_cast<UINT_PTR>(file), L"File");
  SetMenu(GetHandle(), bar);
}

void FlutterWindow::RegisterChannels() {
  auto* messenger = flutter_controller_->engine()->messenger();
  const auto& codec = flutter::StandardMethodCodec::GetInstance();
  menu_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "between_models/desktop_menu", &codec);
  clipboard_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "between_models/clipboard", &codec);
  clipboard_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setHtml") {
          result->NotImplemented();
          return;
        }
        const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr || !HasArgument(*arguments, "plain") ||
            !HasArgument(*arguments, "html")) {
          result->Error("invalid_arguments", "Missing clipboard content");
          return;
        }
        if (!SetRichClipboard(GetHandle(), ReadArgument(*arguments, "plain"),
                              ReadArgument(*arguments, "html"))) {
          result->Error("clipboard_failed", "Could not copy content");
          return;
        }
        result->Success();
      });
}

void FlutterWindow::InvokeMenu(const char* method) noexcept {
  if (!menu_channel_) return;
  try {
    menu_channel_->InvokeMethod(method, nullptr);
  } catch (...) {
  }
}

void FlutterWindow::OnDestroy() {
  clipboard_channel_ = nullptr;
  menu_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COMMAND && HIWORD(wparam) == 0) {
    switch (LOWORD(wparam)) {
      case kNewConversationCommand:
        InvokeMenu("newConversation");
        return 0;
      case kSettingsCommand:
        InvokeMenu("settings");
        return 0;
      default:
        break;
    }
  }

  if (message == WM_GETMINMAXINFO) {
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    const UINT dpi = GetDpiForWindow(hwnd);
    const double scale = dpi == 0 ? 1.0 : static_cast<double>(dpi) / 96.0;
    info->ptMinTrackSize.x = static_cast<LONG>(600 * scale);
    info->ptMinTrackSize.y = static_cast<LONG>(500 * scale);
    return 0;
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
