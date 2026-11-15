// The rendered page on Windows: a WebView2 inside a child window with round corners that the Dart side positions over
// the document card. Page logic stays in Dart; this side loads pages, runs the preview script, reports messages and
// links, and takes a picture of the page while a Flutter overlay covers it. PagePrinter prints and saves PDF.
#ifndef RUNNER_PREVIEW_WEB_H_
#define RUNNER_PREVIEW_WEB_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <wrl.h>
#include <WebView2.h>

#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <vector>

class PreviewWeb {
 public:
  PreviewWeb(int64_t id, HWND parent, flutter::BinaryMessenger* messenger, std::wstring script, double radius);
  ~PreviewWeb();

  void SetFrame(double x, double y, double width, double height, double scale);

 private:
  void Ready();
  void Load(const std::wstring& html, const std::optional<std::wstring>& base);
  void SetBlocked(bool blocked);
  void Navigate(const std::wstring& url);
  void Run(std::function<void()> action);

  int64_t id_;
  HWND parent_;
  HWND container_ = nullptr;
  std::wstring script_;
  double radius_;
  double scale_ = 1;
  bool blocked_ = false;
  std::optional<std::wstring> base_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller_;
  Microsoft::WRL::ComPtr<ICoreWebView2> web_;
  std::vector<std::function<void()>> pending_;
};

class PagePrinter {
 public:
  // Prints (system dialog) or saves a PDF of the page; calls back with an error message or nothing.
  static void Start(HWND owner, std::wstring html, std::optional<std::wstring> base, std::optional<std::wstring> pdf,
                    std::function<void(std::optional<std::string>)> done);
};

// Shared WebView2 environment; created once per process.
void WithWebViewEnvironment(std::function<void(ICoreWebView2Environment*)> action);

// The virtual host that serves the document folder, so relative images and links resolve as on GitHub.
constexpr wchar_t kLocalHost[] = L"rotide.local";

#endif  // RUNNER_PREVIEW_WEB_H_
