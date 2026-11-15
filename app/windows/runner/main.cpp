#include <flutter/dart_project.h>
#include <windows.h>

#include <shellapi.h>

#include <string>
#include <vector>

#include "rotide_host.h"
#include "utils.h"

// One rotide.dm process: a second launch hands its files (or a request for the start window) to the running one.
int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev, _In_ wchar_t* command_line, _In_ int show_command) {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) CreateAndAttachConsole();

  std::vector<std::wstring> paths;
  int count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  for (int i = 1; arguments && i < count; i++) {
    std::wstring argument = arguments[i];
    if (!argument.empty() && argument[0] != L'-') paths.push_back(argument);
  }
  if (arguments) LocalFree(arguments);

  HANDLE single = CreateMutexW(nullptr, TRUE, L"Local\\app.rotide.dm");
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND running = FindWindowExW(HWND_MESSAGE, nullptr, RotideHost::kHostClass, nullptr);
    if (running) {
      std::wstring joined;
      for (const auto& path : paths) {
        wchar_t full[MAX_PATH * 4];
        DWORD length = GetFullPathNameW(path.c_str(), static_cast<DWORD>(std::size(full)), full, nullptr);
        joined += (length ? std::wstring(full, length) : path) + L"\n";
      }
      COPYDATASTRUCT data{1, static_cast<DWORD>(joined.size() * sizeof(wchar_t)), joined.data()};
      DWORD process = 0;
      GetWindowThreadProcessId(running, &process);
      AllowSetForegroundWindow(process);
      SendMessageW(running, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data));
      return EXIT_SUCCESS;
    }
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (!RotideHost::Instance().Start(instance, paths)) {
    ::CoUninitialize();
    return EXIT_FAILURE;
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }
  ::CoUninitialize();
  if (single) CloseHandle(single);
  return EXIT_SUCCESS;
}
