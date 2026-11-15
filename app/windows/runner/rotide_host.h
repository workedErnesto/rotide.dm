// The application side of rotide.dm on Windows: one top-level window per Flutter engine (the start window and every
// document), single instance, preferences shared by all windows (in the registry), the taskbar Jump List of recent
// files, the chosen application icon in every state, quitting with unsaved documents.
#ifndef RUNNER_ROTIDE_HOST_H_
#define RUNNER_ROTIDE_HOST_H_

#include <flutter/encodable_value.h>
#include <windows.h>

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

class RotideWindow;

class RotideHost {
 public:
  static RotideHost& Instance();

  // Starts the host with the files from the command line; shows the start window when there are none.
  bool Start(HINSTANCE instance, const std::vector<std::wstring>& paths);

  void OpenDocument(const std::wstring& path);
  void NewDocument();
  void ShowStart();
  void ShowOpenDialog(HWND owner);

  // Called by a window when it has been destroyed.
  void Removed(RotideWindow* window);

  // Preferences: the same keys as on macOS, stored under HKCU\Software\rotide.dm.
  flutter::EncodableMap Preferences() const;
  void SetPreference(const std::string& key, const flutter::EncodableValue& value);

  // Sends a method to every window's Dart side.
  void Broadcast(const std::string& method, const flutter::EncodableValue& arguments);

  flutter::EncodableMap Accessibility() const;
  void ApplyIcon(const std::string& name);
  int IconResource(const std::string& name) const;
  std::string CurrentIcon() const;

  // Asks each document window in turn whether it may close; quits when all agree.
  void RequestQuit();

  HINSTANCE instance() const { return instance_; }
  const std::vector<std::unique_ptr<RotideWindow>>& windows() const { return windows_; }

  static constexpr wchar_t kAppId[] = L"app.rotide.dm";
  static constexpr wchar_t kHostClass[] = L"ROTIDE_HOST";

 private:
  RotideHost() = default;
  void Add(std::unique_ptr<RotideWindow> window);
  void UpdateJumpList();
  void UpdateShortcutIcons(int resource);
  void AskNext(size_t index);
  static LRESULT CALLBACK HostProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);

  HINSTANCE instance_ = nullptr;
  HWND message_window_ = nullptr;
  std::vector<std::unique_ptr<RotideWindow>> windows_;
  std::vector<RotideWindow*> pending_close_;
  bool quitting_ = false;
};

// UTF-8 and UTF-16 conversions.
std::wstring Wide(const std::string& text);
std::string Narrow(const std::wstring& text);

#endif  // RUNNER_ROTIDE_HOST_H_
