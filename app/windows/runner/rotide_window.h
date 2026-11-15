// One rotide.dm window with its own Flutter engine. The system title bar is removed (the top bar is Flutter's, as on
// macOS), the frame keeps its resize borders, snap layouts and the Acrylic backdrop under the shell.
#ifndef RUNNER_ROTIDE_WINDOW_H_
#define RUNNER_ROTIDE_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <string>

class PreviewWeb;

class RotideWindow {
 public:
  enum class Kind { kStart, kDocument };

  RotideWindow(Kind kind, std::optional<std::wstring> path);
  ~RotideWindow();

  bool Create();
  void Show();
  void Focus();
  void Send(const std::string& method, flutter::EncodableValue arguments = flutter::EncodableValue());

  // Asks Dart whether the document may close; it shows the save question when needed.
  void AskToClose(std::function<void(bool)> reply);
  void CloseNow();

  Kind kind() const { return kind_; }
  HWND handle() const { return window_; }
  const std::optional<std::wstring>& path() const { return path_; }

 private:
  static LRESULT CALLBACK WndProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
  static LRESULT CALLBACK ChildProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam, UINT_PTR id, DWORD_PTR data);
  LRESULT Handle(UINT message, WPARAM wparam, LPARAM lparam);
  LRESULT HitTest(POINT screen) const;
  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ApplyBackdrop();
  void ApplyIcon(int resource);
  double Scale() const;
  void SetMaximizeHover(bool hover);

  Kind kind_;
  std::optional<std::wstring> path_;
  HWND window_ = nullptr;
  std::unique_ptr<flutter::FlutterViewController> flutter_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::map<int64_t, std::unique_ptr<PreviewWeb>> previews_;
  RECT maximize_button_{};
  bool maximize_hover_ = false;
  bool frost_ = true;
  bool dark_ = false;
  bool shown_ = false;
  bool close_approved_ = false;
  bool asking_ = false;
};

#endif  // RUNNER_ROTIDE_WINDOW_H_
