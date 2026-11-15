#include "preview_web.h"

#include <shlobj.h>
#include <shlwapi.h>

#include <memory>
#include <set>

#include "rotide_host.h"

using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kContainerClass[] = L"ROTIDE_PREVIEW";

ComPtr<ICoreWebView2Environment> g_environment;
bool g_creating = false;
std::vector<std::function<void(ICoreWebView2Environment*)>> g_waiting;

void RegisterContainer(HINSTANCE instance) {
  static bool registered = false;
  if (registered) return;
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = DefWindowProcW;
  window_class.hInstance = instance;
  window_class.lpszClassName = kContainerClass;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&window_class);
  registered = true;
}

// The page with a <base> on the virtual host that serves the document folder.
std::wstring WithBase(const std::wstring& html, const std::optional<std::wstring>& base) {
  if (!base) return html;
  std::wstring tag = std::wstring(L"<base href=\"https://") + kLocalHost + L"/\">";
  size_t head = html.find(L"<head>");
  if (head == std::wstring::npos) return tag + html;
  return html.substr(0, head + 6) + tag + html.substr(head + 6);
}

void MapFolder(ICoreWebView2* web, const std::optional<std::wstring>& base) {
  ComPtr<ICoreWebView2_3> web3;
  if (!base || FAILED(web->QueryInterface(IID_PPV_ARGS(&web3)))) return;
  web3->ClearVirtualHostNameToFolderMapping(kLocalHost);
  web3->SetVirtualHostNameToFolderMapping(kLocalHost, base->c_str(), COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_ALLOW);
}

}  // namespace

void WithWebViewEnvironment(std::function<void(ICoreWebView2Environment*)> action) {
  if (g_environment) return action(g_environment.Get());
  g_waiting.push_back(std::move(action));
  if (g_creating) return;
  g_creating = true;
  std::wstring data;
  PWSTR local = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) {
    data = std::wstring(local) + L"\\rotide.dm\\WebView2";
    CoTaskMemFree(local);
  }
  CreateCoreWebView2EnvironmentWithOptions(
      nullptr, data.empty() ? nullptr : data.c_str(), nullptr,
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([](HRESULT, ICoreWebView2Environment* environment) -> HRESULT {
        g_environment = environment;
        g_creating = false;
        auto waiting = std::move(g_waiting);
        g_waiting.clear();
        for (auto& action : waiting) {
          if (environment) action(environment);
        }
        return S_OK;
      }).Get());
}

PreviewWeb::PreviewWeb(int64_t id, HWND parent, flutter::BinaryMessenger* messenger, std::wstring script, double radius)
    : id_(id), parent_(parent), script_(std::move(script)), radius_(radius) {
  auto instance = RotideHost::Instance().instance();
  RegisterContainer(instance);
  container_ = CreateWindowExW(0, kContainerClass, L"", WS_CHILD | WS_CLIPCHILDREN, 0, 0, 1, 1, parent_, nullptr, instance, nullptr);
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(messenger, "rotide/preview/" + std::to_string(id),
                                                                       &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto* args = std::get_if<EncodableMap>(call.arguments());
    auto get = [&](const char* name) -> const EncodableValue* {
      if (!args) return nullptr;
      auto found = args->find(EncodableValue(name));
      return found == args->end() ? nullptr : &found->second;
    };
    const auto& method = call.method_name();
    if (method == "load") {
      auto html = get("html");
      auto base = get("base");
      std::wstring page = html ? Wide(std::get<std::string>(*html)) : std::wstring();
      std::optional<std::wstring> folder;
      if (base && std::holds_alternative<std::string>(*base)) folder = Wide(std::get<std::string>(*base));
      Run([this, page, folder] { Load(page, folder); });
    } else if (method == "eval") {
      auto script = get("script");
      std::wstring code = script ? Wide(std::get<std::string>(*script)) : std::wstring();
      Run([this, code] { web_->ExecuteScript(code.c_str(), nullptr); });
    } else if (method == "zoom") {
      auto value = get("value");
      double zoom = value && std::holds_alternative<double>(*value) ? std::get<double>(*value) : 1.0;
      Run([this, zoom] { controller_->put_ZoomFactor(zoom); });
    } else if (method == "blocked") {
      auto value = get("value");
      SetBlocked(value && std::holds_alternative<bool>(*value) && std::get<bool>(*value));
    } else if (method == "background") {
      auto value = get("color");
      int color = value && std::holds_alternative<int32_t>(*value) ? std::get<int32_t>(*value) : 0xFFFFFF;
      Run([this, color] {
        ComPtr<ICoreWebView2Controller2> controller2;
        if (SUCCEEDED(controller_.As(&controller2))) {
          controller2->put_DefaultBackgroundColor({255, static_cast<BYTE>((color >> 16) & 0xFF), static_cast<BYTE>((color >> 8) & 0xFF),
                                                   static_cast<BYTE>(color & 0xFF)});
        }
      });
    } else if (method == "focus") {
      Run([this] { controller_->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC); });
    }
    result->Success();
  });

  WithWebViewEnvironment([this](ICoreWebView2Environment* environment) {
    environment->CreateCoreWebView2Controller(
        container_, Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([this](HRESULT, ICoreWebView2Controller* controller) -> HRESULT {
                      if (!controller) return S_OK;
                      controller_ = controller;
                      controller_->get_CoreWebView2(&web_);
                      Ready();
                      return S_OK;
                    }).Get());
  });
}

PreviewWeb::~PreviewWeb() {
  if (channel_) channel_->SetMethodCallHandler(nullptr);
  if (controller_) controller_->Close();
  if (container_) DestroyWindow(container_);
}

void PreviewWeb::Run(std::function<void()> action) {
  if (web_) {
    action();
  } else {
    pending_.push_back(std::move(action));
  }
}

void PreviewWeb::Ready() {
  ComPtr<ICoreWebView2Settings> settings;
  if (SUCCEEDED(web_->get_Settings(&settings))) {
    settings->put_AreDefaultContextMenusEnabled(TRUE);
    settings->put_AreDevToolsEnabled(FALSE);
    settings->put_IsStatusBarEnabled(FALSE);
    settings->put_IsZoomControlEnabled(TRUE);
  }
  web_->AddScriptToExecuteOnDocumentCreated(
      (L"window.addEventListener('DOMContentLoaded', () => {" + script_ + L"});").c_str(), nullptr);
  web_->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>(
                                   [this](ICoreWebView2*, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
                                     PWSTR json = nullptr;
                                     if (SUCCEEDED(args->get_WebMessageAsJson(&json)) && json) {
                                       channel_->InvokeMethod("message", std::make_unique<EncodableValue>(Narrow(json)));
                                       CoTaskMemFree(json);
                                     }
                                     return S_OK;
                                   })
                                   .Get(),
                               nullptr);
  // The page itself is the only navigation; links go to Dart, which scrolls, opens a Markdown file or the browser.
  web_->add_NavigationStarting(Callback<ICoreWebView2NavigationStartingEventHandler>(
                                   [this](ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
                                     BOOL user = FALSE;
                                     args->get_IsUserInitiated(&user);
                                     if (!user) return S_OK;
                                     PWSTR uri = nullptr;
                                     args->get_Uri(&uri);
                                     args->put_Cancel(TRUE);
                                     if (uri) {
                                       Navigate(uri);
                                       CoTaskMemFree(uri);
                                     }
                                     return S_OK;
                                   })
                                   .Get(),
                               nullptr);
  web_->add_NewWindowRequested(Callback<ICoreWebView2NewWindowRequestedEventHandler>(
                                   [this](ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) -> HRESULT {
                                     args->put_Handled(TRUE);
                                     PWSTR uri = nullptr;
                                     if (SUCCEEDED(args->get_Uri(&uri)) && uri) {
                                       Navigate(uri);
                                       CoTaskMemFree(uri);
                                     }
                                     return S_OK;
                                   })
                                   .Get(),
                               nullptr);
  ComPtr<ICoreWebView2Controller2> controller2;
  if (SUCCEEDED(controller_.As(&controller2))) controller2->put_DefaultBackgroundColor({0, 255, 255, 255});
  if (!blocked_) ShowWindow(container_, SW_SHOWNA);
  auto pending = std::move(pending_);
  pending_.clear();
  for (auto& action : pending) action();
}

void PreviewWeb::Load(const std::wstring& html, const std::optional<std::wstring>& base) {
  base_ = base;
  MapFolder(web_.Get(), base);
  web_->NavigateToString(WithBase(html, base).c_str());
}

// Links on the virtual host are files of the document folder; Dart gets them as file URLs with their path.
void PreviewWeb::Navigate(const std::wstring& url) {
  std::wstring prefix = std::wstring(L"https://") + kLocalHost + L"/";
  std::wstring fragment;
  std::wstring address = url;
  size_t hash = address.find(L'#');
  if (hash != std::wstring::npos) {
    fragment = address.substr(hash + 1);
    address = address.substr(0, hash);
  }
  EncodableMap navigation;
  if (base_ && address.compare(0, prefix.size(), prefix) == 0) {
    std::wstring relative = address.substr(prefix.size());
    wchar_t decoded[MAX_PATH * 4];
    DWORD length = static_cast<DWORD>(std::size(decoded));
    std::wstring unescaped = SUCCEEDED(UrlUnescapeW(relative.data(), decoded, &length, 0)) ? std::wstring(decoded) : relative;
    for (auto& c : unescaped) {
      if (c == L'/') c = L'\\';
    }
    std::wstring path = *base_;
    if (!unescaped.empty()) path += (path.back() == L'\\' ? L"" : L"\\") + unescaped;
    navigation[EncodableValue("url")] = EncodableValue(Narrow(L"file:///" + path));
    navigation[EncodableValue("path")] = EncodableValue(Narrow(path));
  } else {
    navigation[EncodableValue("url")] = EncodableValue(Narrow(url));
    navigation[EncodableValue("path")] = EncodableValue(std::string());
  }
  navigation[EncodableValue("fragment")] = fragment.empty() ? EncodableValue() : EncodableValue(Narrow(fragment));
  channel_->InvokeMethod("navigate", std::make_unique<EncodableValue>(navigation));
}

void PreviewWeb::SetFrame(double x, double y, double width, double height, double scale) {
  scale_ = scale;
  int left = static_cast<int>(x * scale), top = static_cast<int>(y * scale);
  int pixel_width = static_cast<int>(width * scale), pixel_height = static_cast<int>(height * scale);
  SetWindowPos(container_, HWND_TOP, left, top, pixel_width, pixel_height, SWP_NOACTIVATE);
  int diameter = static_cast<int>(2 * radius_ * scale);
  SetWindowRgn(container_, CreateRoundRectRgn(0, 0, pixel_width + 1, pixel_height + 1, diameter, diameter), TRUE);
  if (controller_) controller_->put_Bounds({0, 0, pixel_width, pixel_height});
  Run([this, pixel_width, pixel_height] { controller_->put_Bounds({0, 0, pixel_width, pixel_height}); });
}

// A window cannot lie under Flutter's overlays (menus, settings, dialogs): while one is open, a picture of the page
// takes the web view's place and the web view is hidden.
void PreviewWeb::SetBlocked(bool blocked) {
  if (blocked == blocked_) return;
  blocked_ = blocked;
  if (!web_) return;
  if (!blocked) {
    ShowWindow(container_, SW_SHOWNA);
    channel_->InvokeMethod("snapshot", std::make_unique<EncodableValue>());
    return;
  }
  ComPtr<IStream> stream;
  if (FAILED(CreateStreamOnHGlobal(nullptr, TRUE, &stream))) {
    ShowWindow(container_, SW_HIDE);
    return;
  }
  web_->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG, stream.Get(),
                       Callback<ICoreWebView2CapturePreviewCompletedHandler>([this, stream](HRESULT result) -> HRESULT {
                         if (SUCCEEDED(result)) {
                           STATSTG stat{};
                           stream->Stat(&stat, STATFLAG_NONAME);
                           std::vector<uint8_t> bytes(static_cast<size_t>(stat.cbSize.QuadPart));
                           LARGE_INTEGER zero{};
                           stream->Seek(zero, STREAM_SEEK_SET, nullptr);
                           ULONG read = 0;
                           stream->Read(bytes.data(), static_cast<ULONG>(bytes.size()), &read);
                           channel_->InvokeMethod("snapshot", std::make_unique<EncodableValue>(bytes));
                         }
                         if (blocked_) ShowWindow(container_, SW_HIDE);
                         return S_OK;
                       }).Get());
}

namespace {

// One print or PDF job with its own hidden web view; it lives until the job is done.
struct PrintJob {
  HWND container = nullptr;
  ComPtr<ICoreWebView2Controller> controller;
  ComPtr<ICoreWebView2> web;
  std::optional<std::wstring> pdf;
  std::function<void(std::optional<std::string>)> done;
  bool finished = false;
};

std::set<std::shared_ptr<PrintJob>> g_jobs;

void Finish(const std::shared_ptr<PrintJob>& job, std::optional<std::string> error) {
  if (job->finished) return;
  job->finished = true;
  job->done(std::move(error));
  if (job->controller) job->controller->Close();
  if (job->container) DestroyWindow(job->container);
  g_jobs.erase(job);
}

}  // namespace

void PagePrinter::Start(HWND owner, std::wstring html, std::optional<std::wstring> base, std::optional<std::wstring> pdf,
                        std::function<void(std::optional<std::string>)> done) {
  auto instance = RotideHost::Instance().instance();
  RegisterContainer(instance);
  auto job = std::make_shared<PrintJob>();
  job->pdf = std::move(pdf);
  job->done = std::move(done);
  // The page is laid out at a paper-like width in a window nobody sees.
  job->container = CreateWindowExW(0, kContainerClass, L"", WS_CHILD, 0, 0, 820, 1100, owner, nullptr, instance, nullptr);
  g_jobs.insert(job);
  WithWebViewEnvironment([job, owner, html, base](ICoreWebView2Environment* environment) {
    environment->CreateCoreWebView2Controller(
        job->container,
        Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>([job, html, base, environment](HRESULT, ICoreWebView2Controller* controller) -> HRESULT {
          if (!controller) {
            Finish(job, std::string("не удалось создать страницу для печати"));
            return S_OK;
          }
          job->controller = controller;
          controller->get_CoreWebView2(&job->web);
          controller->put_Bounds({0, 0, 820, 1100});
          MapFolder(job->web.Get(), base);
          job->web->add_NavigationCompleted(
              Callback<ICoreWebView2NavigationCompletedEventHandler>([job, environment](ICoreWebView2*, ICoreWebView2NavigationCompletedEventArgs*) -> HRESULT {
                if (job->pdf) {
                  ComPtr<ICoreWebView2_7> web7;
                  ComPtr<ICoreWebView2Environment6> environment6;
                  ComPtr<ICoreWebView2PrintSettings> settings;
                  if (FAILED(job->web.As(&web7))) {
                    Finish(job, std::string("эта версия WebView2 не умеет сохранять PDF"));
                    return S_OK;
                  }
                  if (SUCCEEDED(environment->QueryInterface(IID_PPV_ARGS(&environment6))) &&
                      SUCCEEDED(environment6->CreatePrintSettings(&settings))) {
                    settings->put_MarginTop(42.0 / 72);
                    settings->put_MarginBottom(42.0 / 72);
                    settings->put_MarginLeft(48.0 / 72);
                    settings->put_MarginRight(48.0 / 72);
                    settings->put_ShouldPrintBackgrounds(TRUE);
                    settings->put_ShouldPrintHeaderAndFooter(FALSE);
                  }
                  // Print into a temporary file and move it over the destination only when it is complete.
                  std::wstring temporary = *job->pdf + L".rotide-tmp";
                  web7->PrintToPdf(temporary.c_str(), settings.Get(),
                                   Callback<ICoreWebView2PrintToPdfCompletedHandler>([job, temporary](HRESULT result, BOOL success) -> HRESULT {
                                     if (FAILED(result) || !success) {
                                       DeleteFileW(temporary.c_str());
                                       Finish(job, std::string("файл PDF не создан"));
                                     } else if (!MoveFileExW(temporary.c_str(), job->pdf->c_str(), MOVEFILE_REPLACE_EXISTING)) {
                                       DeleteFileW(temporary.c_str());
                                       Finish(job, std::string("не удалось записать файл PDF"));
                                     } else {
                                       Finish(job, std::nullopt);
                                     }
                                     return S_OK;
                                   }).Get());
                } else {
                  ComPtr<ICoreWebView2_16> web16;
                  if (FAILED(job->web.As(&web16))) {
                    Finish(job, std::string("эта версия WebView2 не умеет печатать"));
                    return S_OK;
                  }
                  web16->ShowPrintUI(COREWEBVIEW2_PRINT_DIALOG_KIND_SYSTEM);
                  // The system dialog runs on its own; the hidden page stays until the window that asked closes.
                  job->done(std::nullopt);
                  job->finished = true;
                }
                return S_OK;
              }).Get(),
              nullptr);
          job->web->NavigateToString(WithBase(html, base).c_str());
          return S_OK;
        }).Get());
    (void)owner;
  });
}
