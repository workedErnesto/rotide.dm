#include "rotide_window.h"

#include <commctrl.h>
#include <dwmapi.h>
#include <shellapi.h>
#include <shellscalingapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <windowsx.h>
#include <wrl/client.h>

#include <algorithm>

#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"
#include "preview_web.h"
#include "rotide_host.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kWindowClass[] = L"ROTIDE_WINDOW";
constexpr UINT_PTR kRevealTimer = 1;
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_SYSTEMBACKDROP_TYPE
#define DWMWA_SYSTEMBACKDROP_TYPE 38
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
constexpr int kBackdropNone = 1;
constexpr int kBackdropAcrylic = 3;  // DWMSBT_TRANSIENTWINDOW
constexpr int kRoundCorners = 2;     // DWMWCP_ROUND

const EncodableValue* Field(const EncodableValue* arguments, const char* name) {
  auto map = arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
  if (!map) return nullptr;
  auto found = map->find(EncodableValue(name));
  return found == map->end() ? nullptr : &found->second;
}

std::optional<std::string> String(const EncodableValue* arguments, const char* name) {
  auto value = Field(arguments, name);
  if (auto text = value ? std::get_if<std::string>(value) : nullptr) return *text;
  return std::nullopt;
}

double Number(const EncodableValue* arguments, const char* name, double fallback = 0) {
  auto value = Field(arguments, name);
  if (!value) return fallback;
  if (auto number = std::get_if<double>(value)) return *number;
  if (auto integer = std::get_if<int32_t>(value)) return *integer;
  if (auto integer = std::get_if<int64_t>(value)) return static_cast<double>(*integer);
  return fallback;
}

bool Boolean(const EncodableValue* arguments, const char* name, bool fallback = false) {
  auto value = Field(arguments, name);
  if (auto boolean = value ? std::get_if<bool>(value) : nullptr) return *boolean;
  return fallback;
}

std::optional<std::wstring> SaveDialog(HWND owner, const std::wstring& title, const std::optional<std::wstring>& prompt,
                                       const std::wstring& name, const std::optional<std::wstring>& directory,
                                       const std::wstring& extension) {
  ComPtr<IFileSaveDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return std::nullopt;
  std::wstring pattern = L"*." + extension;
  COMDLG_FILTERSPEC filter{extension.c_str(), pattern.c_str()};
  dialog->SetFileTypes(1, &filter);
  dialog->SetDefaultExtension(extension.c_str());
  dialog->SetFileName(name.c_str());
  if (!title.empty()) dialog->SetTitle(title.c_str());
  if (prompt) dialog->SetOkButtonLabel(prompt->c_str());
  if (directory) {
    ComPtr<IShellItem> folder;
    if (SUCCEEDED(SHCreateItemFromParsingName(directory->c_str(), nullptr, IID_PPV_ARGS(&folder)))) dialog->SetFolder(folder.Get());
  }
  if (FAILED(dialog->Show(owner))) return std::nullopt;
  ComPtr<IShellItem> item;
  PWSTR path = nullptr;
  if (FAILED(dialog->GetResult(&item)) || FAILED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) return std::nullopt;
  std::wstring result(path);
  CoTaskMemFree(path);
  return result;
}

}  // namespace

RotideWindow::RotideWindow(Kind kind, std::optional<std::wstring> path) : kind_(kind), path_(std::move(path)) {}

RotideWindow::~RotideWindow() {
  previews_.clear();
  channel_.reset();
  flutter_.reset();
}

double RotideWindow::Scale() const {
  return (window_ ? GetDpiForWindow(window_) : GetDpiForSystem()) / 96.0;
}

bool RotideWindow::Create() {
  static bool registered = false;
  auto& host = RotideHost::Instance();
  if (!registered) {
    WNDCLASSW window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClass;
    window_class.hInstance = host.instance();
    window_class.hIcon = LoadIcon(host.instance(), MAKEINTRESOURCE(host.IconResource(host.CurrentIcon())));
    window_class.lpfnWndProc = WndProc;
    RegisterClassW(&window_class);
    registered = true;
  }

  POINT cursor;
  GetCursorPos(&cursor);
  HMONITOR monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST);
  MONITORINFO info{sizeof(info)};
  GetMonitorInfoW(monitor, &info);
  UINT dpi = 96, unused = 96;
  GetDpiForMonitor(monitor, MDT_EFFECTIVE_DPI, &dpi, &unused);
  double scale = dpi / 96.0;
  RECT work = info.rcWork;
  double work_width = (work.right - work.left) / scale, work_height = (work.bottom - work.top) / scale;
  double width = 600, height = 548;
  if (kind_ == Kind::kDocument) {
    width = std::min(1320.0, std::max(860.0, work_width * 0.72));
    height = std::min(980.0, std::max(620.0, work_height * 0.86));
  }
  int pixel_width = static_cast<int>(width * scale), pixel_height = static_cast<int>(height * scale);
  int x = work.left + ((work.right - work.left) - pixel_width) / 2;
  int y = work.top + ((work.bottom - work.top) - pixel_height) / 2;
  int offset = static_cast<int>(host.windows().size() > 1 ? 24 * scale * ((host.windows().size() - 1) % 6) : 0);

  DWORD style = WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN;
  if (kind_ == Kind::kStart) style &= ~(WS_MAXIMIZEBOX | WS_THICKFRAME);
  std::wstring title = path_ ? path_->substr(path_->find_last_of(L"\\/") + 1) : L"rotide.dm";
  window_ = CreateWindowExW(WS_EX_APPWINDOW, kWindowClass, title.c_str(), style, x + offset, y + offset, pixel_width, pixel_height,
                            nullptr, nullptr, host.instance(), this);
  if (!window_) return false;

  BOOL round = kRoundCorners;
  DwmSetWindowAttribute(window_, DWMWA_WINDOW_CORNER_PREFERENCE, &round, sizeof(round));
  MARGINS margins{-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(window_, &margins);
  ApplyBackdrop();
  ApplyIcon(host.IconResource(host.CurrentIcon()));
  SetWindowPos(window_, nullptr, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

  flutter::DartProject project(L"data");
  std::string path_argument = path_ ? Narrow(*path_) : std::string();
  project.set_dart_entrypoint_arguments({kind_ == Kind::kStart ? "start" : "document", path_argument});
  RECT client;
  GetClientRect(window_, &client);
  flutter_ = std::make_unique<flutter::FlutterViewController>(client.right - client.left, client.bottom - client.top, project);
  if (!flutter_->engine() || !flutter_->view()) return false;
  RegisterPlugins(flutter_->engine());

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(flutter_->engine()->messenger(), "rotide/native",
                                                                       &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { HandleCall(call, std::move(result)); });

  HWND view = flutter_->view()->GetNativeWindow();
  SetParent(view, window_);
  MoveWindow(view, 0, 0, client.right - client.left, client.bottom - client.top, TRUE);
  SetWindowSubclass(view, ChildProc, 1, reinterpret_cast<DWORD_PTR>(this));
  SetFocus(view);
  // The window appears with Dart's first frame; the timer only guards against a window that never shows.
  SetTimer(window_, kRevealTimer, 2000, nullptr);
  return true;
}

void RotideWindow::Show() {
  if (shown_ || !window_) return;
  shown_ = true;
  KillTimer(window_, kRevealTimer);
  ShowWindow(window_, SW_SHOWNORMAL);
  SetForegroundWindow(window_);
  flutter_->ForceRedraw();
}

void RotideWindow::Focus() {
  if (!window_) return;
  if (IsIconic(window_)) ShowWindow(window_, SW_RESTORE);
  SetForegroundWindow(window_);
}

void RotideWindow::Send(const std::string& method, EncodableValue arguments) {
  if (channel_) channel_->InvokeMethod(method, std::make_unique<EncodableValue>(std::move(arguments)));
}

void RotideWindow::AskToClose(std::function<void(bool)> reply) {
  if (kind_ != Kind::kDocument || !channel_) {
    reply(true);
    return;
  }
  Focus();
  auto handler = std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
      [this, reply](const EncodableValue* value) {
        bool allowed = true;
        if (auto boolean = value ? std::get_if<bool>(value) : nullptr) allowed = *boolean;
        if (allowed) close_approved_ = true;
        reply(allowed);
      },
      [reply](const std::string&, const std::string&, const EncodableValue*) { reply(true); },
      [reply]() { reply(true); });
  channel_->InvokeMethod("shouldClose", nullptr, std::move(handler));
}

void RotideWindow::CloseNow() {
  close_approved_ = true;
  if (window_) DestroyWindow(window_);
}

void RotideWindow::ApplyBackdrop() {
  if (!window_) return;
  BOOL dark = dark_;
  DwmSetWindowAttribute(window_, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark, sizeof(dark));
  int backdrop = frost_ ? kBackdropAcrylic : kBackdropNone;
  DwmSetWindowAttribute(window_, DWMWA_SYSTEMBACKDROP_TYPE, &backdrop, sizeof(backdrop));
}

void RotideWindow::ApplyIcon(int resource) {
  auto instance = RotideHost::Instance().instance();
  HICON big = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(resource), IMAGE_ICON, GetSystemMetrics(SM_CXICON),
                                            GetSystemMetrics(SM_CYICON), LR_DEFAULTCOLOR));
  HICON small_icon = static_cast<HICON>(LoadImageW(instance, MAKEINTRESOURCEW(resource), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                                              GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
  SendMessageW(window_, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(big));
  SendMessageW(window_, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(small_icon));
}

void RotideWindow::SetMaximizeHover(bool hover) {
  if (hover == maximize_hover_) return;
  maximize_hover_ = hover;
  Send("maximizeHover", EncodableValue(hover));
}

LRESULT CALLBACK RotideWindow::WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_NCCREATE) {
    auto create = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
    reinterpret_cast<RotideWindow*>(create->lpCreateParams)->window_ = window;
    EnableNonClientDpiScaling(window);
  }
  auto self = reinterpret_cast<RotideWindow*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (!self) return DefWindowProc(window, message, wparam, lparam);
  if (message == WM_NCDESTROY) {
    SetWindowLongPtr(window, GWLP_USERDATA, 0);
    self->window_ = nullptr;
    LRESULT result = DefWindowProc(window, message, wparam, lparam);
    RotideHost::Instance().Removed(self);  // Deletes self.
    return result;
  }
  return self->Handle(message, wparam, lparam);
}

LRESULT CALLBACK RotideWindow::ChildProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR, DWORD_PTR data) {
  // The Flutter view covers the whole client area; resize borders and the maximize button belong to the frame.
  if (message == WM_NCHITTEST) {
    auto self = reinterpret_cast<RotideWindow*>(data);
    POINT point{GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    if (self->HitTest(point) != HTCLIENT) return HTTRANSPARENT;
  }
  return DefSubclassProc(window, message, wparam, lparam);
}

LRESULT RotideWindow::HitTest(POINT screen) const {
  POINT point = screen;
  ScreenToClient(window_, &point);
  RECT client;
  GetClientRect(window_, &client);
  double scale = Scale();
  if (kind_ == Kind::kDocument && !IsZoomed(window_)) {
    int border = static_cast<int>(6 * scale);
    bool left = point.x < border, right = point.x >= client.right - border;
    bool top = point.y < border, bottom = point.y >= client.bottom - border;
    if (top && left) return HTTOPLEFT;
    if (top && right) return HTTOPRIGHT;
    if (bottom && left) return HTBOTTOMLEFT;
    if (bottom && right) return HTBOTTOMRIGHT;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
    if (top) return HTTOP;
    if (bottom) return HTBOTTOM;
  }
  if (PtInRect(&maximize_button_, point)) return HTMAXBUTTON;
  return HTCLIENT;
}

LRESULT RotideWindow::Handle(UINT message, WPARAM wparam, LPARAM lparam) {
  if (flutter_) {
    if (auto result = flutter_->HandleTopLevelWindowProc(window_, message, wparam, lparam)) return *result;
  }
  switch (message) {
    case WM_NCCALCSIZE:
      if (wparam) {
        // No system title bar or border; a maximized window keeps inside the screen.
        if (IsZoomed(window_)) {
          auto params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
          UINT dpi = GetDpiForWindow(window_);
          int frame = GetSystemMetricsForDpi(SM_CXFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
          params->rgrc[0].left += frame;
          params->rgrc[0].right -= frame;
          params->rgrc[0].top += frame;
          params->rgrc[0].bottom -= frame;
        }
        return 0;
      }
      break;
    case WM_NCHITTEST: {
      LRESULT hit = HitTest({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
      return hit;
    }
    case WM_NCMOUSEMOVE:
      SetMaximizeHover(wparam == HTMAXBUTTON);
      if (wparam == HTMAXBUTTON) {
        TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE | TME_NONCLIENT, window_, 0};
        TrackMouseEvent(&track);
      }
      break;
    case WM_NCMOUSELEAVE:
      SetMaximizeHover(false);
      break;
    case WM_NCLBUTTONDOWN:
      if (wparam == HTMAXBUTTON) return 0;
      break;
    case WM_NCLBUTTONUP:
      if (wparam == HTMAXBUTTON) {
        ShowWindow(window_, IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
        return 0;
      }
      break;
    case WM_SIZE: {
      if (flutter_ && flutter_->view()) {
        MoveWindow(flutter_->view()->GetNativeWindow(), 0, 0, LOWORD(lparam), HIWORD(lparam), TRUE);
      }
      Send("maximized", EncodableValue(wparam == SIZE_MAXIMIZED));
      return 0;
    }
    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      double scale = Scale();
      info->ptMinTrackSize.x = static_cast<LONG>(560 * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(420 * scale);
      return 0;
    }
    case WM_DPICHANGED: {
      auto rect = reinterpret_cast<RECT*>(lparam);
      SetWindowPos(window_, nullptr, rect->left, rect->top, rect->right - rect->left, rect->bottom - rect->top, SWP_NOZORDER | SWP_NOACTIVATE);
      return 0;
    }
    case WM_ACTIVATE:
      Send("key", EncodableValue(LOWORD(wparam) != WA_INACTIVE));
      if (LOWORD(wparam) != WA_INACTIVE && flutter_ && flutter_->view()) SetFocus(flutter_->view()->GetNativeWindow());
      return 0;
    case WM_TIMER:
      if (wparam == kRevealTimer) Show();
      return 0;
    case WM_SETTINGCHANGE:
      RotideHost::Instance().Broadcast("accessibility", EncodableValue(RotideHost::Instance().Accessibility()));
      break;
    case WM_CLOSE:
      if (close_approved_ || kind_ == Kind::kStart) {
        DestroyWindow(window_);
      } else if (!asking_) {
        asking_ = true;
        AskToClose([this](bool allowed) {
          asking_ = false;
          if (allowed) DestroyWindow(window_);
        });
      }
      return 0;
  }
  return DefWindowProc(window_, message, wparam, lparam);
}

void RotideWindow::HandleCall(const flutter::MethodCall<EncodableValue>& call,
                              std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto& host = RotideHost::Instance();
  const auto& method = call.method_name();
  const EncodableValue* args = call.arguments();
  if (method == "launch") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("kind"), EncodableValue(kind_ == Kind::kStart ? "start" : "document")},
        {EncodableValue("path"), path_ ? EncodableValue(Narrow(*path_)) : EncodableValue()},
        {EncodableValue("preferences"), EncodableValue(host.Preferences())},
        {EncodableValue("accessibility"), EncodableValue(host.Accessibility())},
        {EncodableValue("fullScreen"), EncodableValue(false)},
        {EncodableValue("version"), EncodableValue(std::string(FLUTTER_VERSION))},
    }));
  } else if (method == "ready") {
    Show();
    result->Success();
  } else if (method == "setFrost") {
    frost_ = Boolean(args, "enabled", true);
    ApplyBackdrop();
    result->Success();
  } else if (method == "setDark") {
    dark_ = Boolean(args, "dark");
    ApplyBackdrop();
    result->Success();
  } else if (method == "setDocument") {
    if (auto path = String(args, "path")) path_ = Wide(*path);
    if (auto title = String(args, "title")) SetWindowTextW(window_, Wide(*title).c_str());
    result->Success();
  } else if (method == "setState") {
    result->Success();
  } else if (method == "drag") {
    ReleaseCapture();
    SendMessageW(window_, WM_NCLBUTTONDOWN, HTCAPTION, 0);
    result->Success();
  } else if (method == "doubleClick") {
    if (kind_ == Kind::kDocument) ShowWindow(window_, IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
    result->Success();
  } else if (method == "minimize") {
    ShowWindow(window_, SW_MINIMIZE);
    result->Success();
  } else if (method == "close") {
    // Closing without the save question: the document could not be opened.
    close_approved_ = true;
    result->Success();
    PostMessageW(window_, WM_CLOSE, 0, 0);
  } else if (method == "performClose") {
    result->Success();
    PostMessageW(window_, WM_CLOSE, 0, 0);
  } else if (method == "openDocument") {
    if (auto path = String(args, "path")) host.OpenDocument(Wide(*path));
    result->Success();
  } else if (method == "newDocument") {
    host.NewDocument();
    result->Success();
  } else if (method == "showStart") {
    host.ShowStart();
    result->Success();
  } else if (method == "openPanel") {
    result->Success();
    host.ShowOpenDialog(window_);
  } else if (method == "savePanel") {
    auto directory = String(args, "directory");
    auto prompt = String(args, "prompt");
    auto chosen = SaveDialog(window_, Wide(String(args, "title").value_or("")), prompt ? std::optional(Wide(*prompt)) : std::nullopt,
                             Wide(String(args, "name").value_or("")), directory ? std::optional(Wide(*directory)) : std::nullopt,
                             Wide(String(args, "extension").value_or("md")));
    result->Success(chosen ? EncodableValue(Narrow(*chosen)) : EncodableValue());
  } else if (method == "preferences") {
    result->Success(EncodableValue(host.Preferences()));
  } else if (method == "setPreference") {
    auto key = String(args, "key");
    auto value = Field(args, "value");
    if (key) host.SetPreference(*key, value ? *value : EncodableValue());
    result->Success();
  } else if (method == "setIcon") {
    host.ApplyIcon(String(args, "name").value_or("default"));
    result->Success();
  } else if (method == "symbols") {
    // Windows draws its icon font instead of SF Symbols.
    EncodableList empty;
    if (auto requests = Field(args, "requests")) {
      if (auto list = std::get_if<EncodableList>(requests)) empty.resize(list->size());
    }
    result->Success(EncodableValue(empty));
  } else if (method == "textWidths") {
    result->Success(EncodableValue(EncodableList{}));
  } else if (method == "openURL") {
    if (auto url = String(args, "url")) ShellExecuteW(window_, L"open", Wide(*url).c_str(), nullptr, nullptr, SW_SHOWNORMAL);
    result->Success();
  } else if (method == "reveal") {
    if (auto path = String(args, "path")) {
      PIDLIST_ABSOLUTE item = ILCreateFromPathW(Wide(*path).c_str());
      if (item) {
        SHOpenFolderAndSelectItems(item, 0, nullptr, 0);
        ILFree(item);
      }
    }
    result->Success();
  } else if (method == "print" || method == "pdf") {
    auto base = String(args, "base");
    auto destination = method == "pdf" ? String(args, "path") : std::nullopt;
    std::shared_ptr<flutter::MethodResult<EncodableValue>> shared(result.release());
    PagePrinter::Start(window_, Wide(String(args, "html").value_or("")), base ? std::optional(Wide(*base)) : std::nullopt,
                       destination ? std::optional(Wide(*destination)) : std::nullopt, [shared](std::optional<std::string> error) {
                         shared->Success(error ? EncodableValue(*error) : EncodableValue());
                       });
  } else if (method == "beep") {
    MessageBeep(MB_OK);
    result->Success();
  } else if (method == "captionButtons") {
    double scale = Scale();
    if (auto rect = Field(args, "maximize")) {
      if (auto list = std::get_if<EncodableList>(rect); list && list->size() == 4) {
        auto at = [&](size_t i) { return std::get<double>((*list)[i]) * scale; };
        maximize_button_ = {static_cast<LONG>(at(0)), static_cast<LONG>(at(1)), static_cast<LONG>(at(0) + at(2)), static_cast<LONG>(at(1) + at(3))};
      }
    }
    result->Success();
  } else if (method == "previewCreate") {
    static int64_t next = 1;
    int64_t id = next++;
    previews_[id] = std::make_unique<PreviewWeb>(id, window_, flutter_->engine()->messenger(), Wide(String(args, "script").value_or("")),
                                                 Number(args, "radius", 10));
    result->Success(EncodableValue(id));
  } else if (method == "previewFrame") {
    auto found = previews_.find(static_cast<int64_t>(Number(args, "id")));
    if (found != previews_.end()) {
      found->second->SetFrame(Number(args, "x"), Number(args, "y"), Number(args, "width"), Number(args, "height"), Number(args, "scale", 1));
    }
    result->Success();
  } else if (method == "previewDestroy") {
    previews_.erase(static_cast<int64_t>(Number(args, "id")));
    result->Success();
  } else {
    result->NotImplemented();
  }
}
