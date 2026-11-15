#include "rotide_host.h"

#include <propkey.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <wrl/client.h>

#include <algorithm>

#include "resource.h"
#include "rotide_window.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

namespace {

constexpr wchar_t kPreferencesKey[] = L"Software\\rotide.dm";

const std::vector<std::pair<std::string, int>> kIcons = {
    {"default", IDI_APP_ICON}, {"stone", IDI_ICON_STONE},       {"blue", IDI_ICON_BLUE},
    {"green", IDI_ICON_GREEN}, {"lavender", IDI_ICON_LAVENDER}, {"terracotta", IDI_ICON_TERRACOTTA},
};

std::wstring ExecutablePath() {
  wchar_t buffer[MAX_PATH * 4];
  DWORD length = GetModuleFileNameW(nullptr, buffer, static_cast<DWORD>(std::size(buffer)));
  return std::wstring(buffer, length);
}

// Values are stored as text with a type prefix ("b:", "d:", "s:"), lists of strings as REG_MULTI_SZ.
std::optional<EncodableValue> ReadValue(HKEY key, const std::wstring& name, DWORD type, const std::vector<wchar_t>& data) {
  if (type == REG_MULTI_SZ) {
    EncodableList list;
    const wchar_t* cursor = data.data();
    while (*cursor) {
      std::wstring item(cursor);
      list.push_back(EncodableValue(Narrow(item)));
      cursor += item.size() + 1;
    }
    return EncodableValue(list);
  }
  if (type != REG_SZ) return std::nullopt;
  std::wstring text(data.data());
  if (text.size() < 2) return std::nullopt;
  std::wstring body = text.substr(2);
  switch (text[0]) {
    case L'b':
      return EncodableValue(body == L"true");
    case L'd':
      return EncodableValue(_wtof(body.c_str()));
    case L's':
      return EncodableValue(Narrow(body));
  }
  return std::nullopt;
}

}  // namespace

std::wstring Wide(const std::string& text) {
  if (text.empty()) return std::wstring();
  int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), length);
  return result;
}

std::string Narrow(const std::wstring& text) {
  if (text.empty()) return std::string();
  int length = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), result.data(), length, nullptr, nullptr);
  return result;
}

RotideHost& RotideHost::Instance() {
  static RotideHost host;
  return host;
}

bool RotideHost::Start(HINSTANCE instance, const std::vector<std::wstring>& paths) {
  instance_ = instance;
  SetCurrentProcessExplicitAppUserModelID(kAppId);

  WNDCLASSW host_class{};
  host_class.lpfnWndProc = HostProc;
  host_class.hInstance = instance;
  host_class.lpszClassName = kHostClass;
  RegisterClassW(&host_class);
  message_window_ = CreateWindowExW(0, kHostClass, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, instance, nullptr);

  ApplyIcon(CurrentIcon());
  UpdateJumpList();
  for (const auto& path : paths) OpenDocument(path);
  if (windows_.empty()) ShowStart();
  return !windows_.empty();
}

LRESULT CALLBACK RotideHost::HostProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto& host = Instance();
  if (message == WM_COPYDATA) {
    // A second launch passes its files here: one path per line, or nothing to bring up the start window.
    auto* data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
    std::wstring text(reinterpret_cast<const wchar_t*>(data->lpData), data->cbData / sizeof(wchar_t));
    size_t start = 0;
    bool opened = false;
    while (start < text.size()) {
      size_t end = text.find(L'\n', start);
      if (end == std::wstring::npos) end = text.size();
      std::wstring path = text.substr(start, end - start);
      if (!path.empty()) {
        host.OpenDocument(path);
        opened = true;
      }
      start = end + 1;
    }
    if (!opened) {
      if (host.windows_.empty()) {
        host.ShowStart();
      } else {
        host.windows_.front()->Focus();
      }
    }
    return TRUE;
  }
  if (message == WM_SETTINGCHANGE) {
    host.Broadcast("accessibility", EncodableValue(host.Accessibility()));
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void RotideHost::OpenDocument(const std::wstring& path) {
  wchar_t full[MAX_PATH * 4];
  DWORD length = GetFullPathNameW(path.c_str(), static_cast<DWORD>(std::size(full)), full, nullptr);
  std::wstring standard = length ? std::wstring(full, length) : path;
  for (const auto& window : windows_) {
    if (window->kind() == RotideWindow::Kind::kDocument && window->path() && _wcsicmp(window->path()->c_str(), standard.c_str()) == 0) {
      window->Focus();
      return;
    }
  }
  Add(std::make_unique<RotideWindow>(RotideWindow::Kind::kDocument, standard));
}

void RotideHost::NewDocument() { Add(std::make_unique<RotideWindow>(RotideWindow::Kind::kDocument, std::nullopt)); }

void RotideHost::ShowStart() {
  for (const auto& window : windows_) {
    if (window->kind() == RotideWindow::Kind::kStart) {
      window->Focus();
      return;
    }
  }
  Add(std::make_unique<RotideWindow>(RotideWindow::Kind::kStart, std::nullopt));
}

void RotideHost::Add(std::unique_ptr<RotideWindow> window) {
  RotideWindow* created = window.get();
  windows_.push_back(std::move(window));
  if (!created->Create()) {
    Removed(created);
    return;
  }
  if (created->kind() == RotideWindow::Kind::kDocument) {
    for (const auto& other : windows_) {
      if (other->kind() == RotideWindow::Kind::kStart) {
        other->CloseNow();
        break;
      }
    }
  }
}

void RotideHost::Removed(RotideWindow* window) {
  // Called last from the window's WM_NCDESTROY: the object is deleted here and is not touched afterwards.
  auto found = std::find_if(windows_.begin(), windows_.end(), [&](const auto& item) { return item.get() == window; });
  if (found != windows_.end()) windows_.erase(found);
  if (windows_.empty()) PostQuitMessage(0);
}

void RotideHost::ShowOpenDialog(HWND owner) {
  ComPtr<IFileOpenDialog> dialog;
  if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog)))) return;
  COMDLG_FILTERSPEC filters[] = {
      {L"Markdown", L"*.md;*.markdown;*.mdown;*.mkd;*.mkdn;*.mdwn;*.mdtxt;*.mdtext"},
      {L"Текст", L"*.txt;*.text"},
  };
  dialog->SetFileTypes(2, filters);
  DWORD options = 0;
  dialog->GetOptions(&options);
  dialog->SetOptions(options | FOS_ALLOWMULTISELECT | FOS_FILEMUSTEXIST | FOS_FORCEFILESYSTEM);
  if (FAILED(dialog->Show(owner))) return;
  ComPtr<IShellItemArray> items;
  if (FAILED(dialog->GetResults(&items))) return;
  DWORD count = 0;
  items->GetCount(&count);
  for (DWORD i = 0; i < count; i++) {
    ComPtr<IShellItem> item;
    PWSTR path = nullptr;
    if (SUCCEEDED(items->GetItemAt(i, &item)) && SUCCEEDED(item->GetDisplayName(SIGDN_FILESYSPATH, &path))) {
      OpenDocument(path);
      CoTaskMemFree(path);
    }
  }
}

EncodableMap RotideHost::Preferences() const {
  EncodableMap values;
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kPreferencesKey, 0, KEY_READ, &key) != ERROR_SUCCESS) return values;
  for (DWORD index = 0;; index++) {
    wchar_t name[256];
    DWORD name_length = static_cast<DWORD>(std::size(name));
    DWORD type = 0, size = 0;
    if (RegEnumValueW(key, index, name, &name_length, nullptr, &type, nullptr, &size) != ERROR_SUCCESS) break;
    std::vector<wchar_t> data(size / sizeof(wchar_t) + 2, L'\0');
    name_length = static_cast<DWORD>(std::size(name));
    DWORD data_size = size;
    if (RegEnumValueW(key, index, name, &name_length, nullptr, &type, reinterpret_cast<BYTE*>(data.data()), &data_size) != ERROR_SUCCESS) continue;
    if (auto value = ReadValue(key, name, type, data)) values[EncodableValue(Narrow(name))] = *value;
  }
  RegCloseKey(key);
  return values;
}

void RotideHost::SetPreference(const std::string& key_name, const EncodableValue& value) {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kPreferencesKey, 0, nullptr, 0, KEY_WRITE, nullptr, &key, nullptr) == ERROR_SUCCESS) {
    std::wstring name = Wide(key_name);
    std::wstring text;
    bool multi = false;
    if (std::holds_alternative<std::monostate>(value)) {
      RegDeleteValueW(key, name.c_str());
    } else if (auto boolean = std::get_if<bool>(&value)) {
      text = std::wstring(L"b:") + (*boolean ? L"true" : L"false");
    } else if (auto number = std::get_if<double>(&value)) {
      text = L"d:" + std::to_wstring(*number);
    } else if (auto integer = std::get_if<int32_t>(&value)) {
      text = L"d:" + std::to_wstring(*integer);
    } else if (auto string = std::get_if<std::string>(&value)) {
      text = L"s:" + Wide(*string);
    } else if (auto list = std::get_if<EncodableList>(&value)) {
      multi = true;
      for (const auto& item : *list) {
        if (auto entry = std::get_if<std::string>(&item)) {
          text += Wide(*entry);
          text.push_back(L'\0');
        }
      }
      text.push_back(L'\0');
    }
    if (!text.empty()) {
      RegSetValueExW(key, name.c_str(), 0, multi ? REG_MULTI_SZ : REG_SZ, reinterpret_cast<const BYTE*>(text.data()),
                     static_cast<DWORD>((multi ? text.size() : text.size() + 1) * sizeof(wchar_t)));
    }
    RegCloseKey(key);
  }
  EncodableMap change{{EncodableValue("key"), EncodableValue(key_name)}, {EncodableValue("value"), value}};
  Broadcast("preference", EncodableValue(change));
  if (key_name == "recentDocumentPaths") UpdateJumpList();
}

void RotideHost::Broadcast(const std::string& method, const EncodableValue& arguments) {
  for (const auto& window : windows_) window->Send(method, arguments);
}

EncodableMap RotideHost::Accessibility() const {
  BOOL animations = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &animations, 0);
  HIGHCONTRASTW contrast{sizeof(contrast)};
  SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
  DWORD transparency = 1, size = sizeof(transparency);
  RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", L"EnableTransparency",
               RRF_RT_REG_DWORD, nullptr, &transparency, &size);
  return EncodableMap{
      {EncodableValue("reduceMotion"), EncodableValue(!animations)},
      {EncodableValue("reduceTransparency"), EncodableValue(transparency == 0)},
      {EncodableValue("increaseContrast"), EncodableValue((contrast.dwFlags & HCF_HIGHCONTRASTON) != 0)},
  };
}

std::string RotideHost::CurrentIcon() const {
  auto values = Preferences();
  auto found = values.find(EncodableValue("appIcon"));
  if (found != values.end()) {
    if (auto name = std::get_if<std::string>(&found->second)) return *name;
  }
  return "default";
}

int RotideHost::IconResource(const std::string& name) const {
  for (const auto& [variant, resource] : kIcons) {
    if (variant == name) return resource;
  }
  return IDI_APP_ICON;
}

// The chosen icon everywhere Windows shows the app: the windows (taskbar buttons, Alt+Tab), the Start menu and pinned
// taskbar shortcuts (shown while the app is closed), and the icon a new pin takes. The .exe in Explorer keeps its
// first icon, as Finder keeps the bundle's on macOS without a custom icon.
void RotideHost::ApplyIcon(const std::string& name) {
  int resource = IconResource(name);
  for (const auto& window : windows_) {
    HWND handle = window->handle();
    if (!handle) continue;
    HICON big = static_cast<HICON>(LoadImageW(instance_, MAKEINTRESOURCEW(resource), IMAGE_ICON, GetSystemMetrics(SM_CXICON),
                                              GetSystemMetrics(SM_CYICON), LR_DEFAULTCOLOR));
    HICON small_icon = static_cast<HICON>(LoadImageW(instance_, MAKEINTRESOURCEW(resource), IMAGE_ICON, GetSystemMetrics(SM_CXSMICON),
                                                GetSystemMetrics(SM_CYSMICON), LR_DEFAULTCOLOR));
    SendMessageW(handle, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(big));
    SendMessageW(handle, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(small_icon));
  }
  UpdateShortcutIcons(resource);
}

void RotideHost::UpdateShortcutIcons(int resource) {
  std::wstring exe = ExecutablePath();
  std::vector<std::wstring> folders;
  PWSTR folder = nullptr;
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr, &folder))) {
    folders.push_back(folder);
    CoTaskMemFree(folder);
  }
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr, &folder))) {
    folders.push_back(std::wstring(folder) + L"\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned\\TaskBar");
    CoTaskMemFree(folder);
  }
  if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &folder))) {
    folders.push_back(folder);
    CoTaskMemFree(folder);
  }
  bool changed = false;
  for (const auto& directory : folders) {
    WIN32_FIND_DATAW found;
    HANDLE search = FindFirstFileW((directory + L"\\*.lnk").c_str(), &found);
    if (search == INVALID_HANDLE_VALUE) continue;
    do {
      std::wstring file = directory + L"\\" + found.cFileName;
      ComPtr<IShellLinkW> link;
      ComPtr<IPersistFile> persist;
      if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) continue;
      if (FAILED(link.As(&persist)) || FAILED(persist->Load(file.c_str(), STGM_READWRITE))) continue;
      wchar_t target[MAX_PATH * 4];
      if (FAILED(link->GetPath(target, static_cast<int>(std::size(target)), nullptr, SLGP_RAWPATH))) continue;
      if (_wcsicmp(target, exe.c_str()) != 0) continue;
      link->SetIconLocation(exe.c_str(), -resource);
      if (SUCCEEDED(persist->Save(file.c_str(), TRUE))) {
        SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW, file.c_str(), nullptr);
        changed = true;
      }
    } while (FindNextFileW(search, &found));
    FindClose(search);
  }
  if (changed) SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

// The taskbar's right-click menu: recent files, kept by Windows while the app is closed.
void RotideHost::UpdateJumpList() {
  ComPtr<ICustomDestinationList> list;
  if (FAILED(CoCreateInstance(CLSID_DestinationList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&list)))) return;
  list->SetAppID(kAppId);
  UINT slots = 0;
  ComPtr<IObjectArray> removed;
  if (FAILED(list->BeginList(&slots, IID_PPV_ARGS(&removed)))) return;
  ComPtr<IObjectCollection> items;
  if (FAILED(CoCreateInstance(CLSID_EnumerableObjectCollection, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&items)))) {
    list->AbortList();
    return;
  }
  std::wstring exe = ExecutablePath();
  auto values = Preferences();
  auto found = values.find(EncodableValue("recentDocumentPaths"));
  UINT added = 0;
  if (found != values.end()) {
    if (auto paths = std::get_if<EncodableList>(&found->second)) {
      for (const auto& item : *paths) {
        auto path = std::get_if<std::string>(&item);
        if (!path || added >= slots) continue;
        std::wstring wide = Wide(*path);
        ComPtr<IShellLinkW> link;
        if (FAILED(CoCreateInstance(CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) continue;
        link->SetPath(exe.c_str());
        link->SetArguments((L"\"" + wide + L"\"").c_str());
        link->SetDescription(wide.c_str());
        link->SetIconLocation(L"%SystemRoot%\\System32\\imageres.dll", 2);
        ComPtr<IPropertyStore> store;
        if (SUCCEEDED(link.As(&store))) {
          PROPVARIANT title;
          std::wstring name = wide.substr(wide.find_last_of(L"\\/") + 1);
          if (SUCCEEDED(InitPropVariantFromString(name.c_str(), &title))) {
            store->SetValue(PKEY_Title, title);
            store->Commit();
            PropVariantClear(&title);
          }
        }
        items->AddObject(link.Get());
        added++;
      }
    }
  }
  ComPtr<IObjectArray> array;
  if (added > 0 && SUCCEEDED(items.As(&array))) list->AppendCategory(L"недавние", array.Get());
  list->CommitList();
}

void RotideHost::RequestQuit() {
  if (quitting_) return;
  quitting_ = true;
  pending_close_.clear();
  for (const auto& window : windows_) pending_close_.push_back(window.get());
  AskNext(0);
}

void RotideHost::AskNext(size_t index) {
  if (index >= pending_close_.size()) {
    quitting_ = false;
    for (auto* window : pending_close_) window->CloseNow();
    pending_close_.clear();
    return;
  }
  pending_close_[index]->AskToClose([this, index](bool allowed) {
    if (allowed) {
      AskNext(index + 1);
    } else {
      quitting_ = false;
      pending_close_.clear();
    }
  });
}
