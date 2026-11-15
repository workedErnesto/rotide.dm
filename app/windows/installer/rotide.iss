; Inno Setup script for rotide.dm on Windows. Built by .github/workflows/windows.yml:
;   iscc /DAppVersion=1.0.0 /DArch=x64 /DSourceDir=<flutter Release folder> /DOutputDir=<folder> rotide.iss
; Installs per user by default (no admin prompt); the setup offers an all-users install on its first page.
; Registers rotide.dm for Markdown files (default handler, can be unticked) and in "Open with" for .txt, .text, .docx
; and .rtf.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\" + Arch + "\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\..\build\installer"
#endif

#define AppName "rotide.dm"
#define AppExe "rotide_dm.exe"
#define MarkdownProgId "rotide.dm.markdown"
#define TextProgId "rotide.dm.text"

[Setup]
AppId={{8C1F4E2A-5B7D-4A63-9E0F-2D6B3C7A91E4}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=workedErnesto
AppPublisherURL=https://github.com/workedErnesto/rotide.dm
AppSupportURL=https://github.com/workedErnesto/rotide.dm/issues
AppUpdatesURL=https://github.com/workedErnesto/rotide.dm/releases
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.17763
ChangesAssociations=yes
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=..\runner\resources\icons\default.ico
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
OutputDir={#OutputDir}
OutputBaseFilename=rotide.dm-{#AppVersion}-win-{#Arch}-setup
LicenseFile=..\..\..\LICENSE

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
ru.AssocMarkdown=открывать файлы Markdown (.md) в rotide.dm
en.AssocMarkdown=Open Markdown files (.md) with rotide.dm
ru.AssocGroup=файлы:
en.AssocGroup=Files:
ru.DesktopIcon=ярлык на рабочем столе
en.DesktopIcon=Desktop shortcut
ru.ShortcutsGroup=ярлыки:
en.ShortcutsGroup=Shortcuts:
ru.MarkdownDoc=документ Markdown
en.MarkdownDoc=Markdown document
ru.TextDoc=текстовый документ
en.TextDoc=Text document
ru.AppDescription=читалка и редактор Markdown
en.AppDescription=Markdown reader and editor

[Tasks]
Name: "assocmarkdown"; Description: "{cm:AssocMarkdown}"; GroupDescription: "{cm:AssocGroup}"
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; GroupDescription: "{cm:ShortcutsGroup}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "app.rotide.dm"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "app.rotide.dm"; Tasks: desktopicon

[Registry]
; Program identifiers that Explorer opens files with.
Root: HKA; Subkey: "Software\Classes\{#MarkdownProgId}"; ValueType: string; ValueName: ""; ValueData: "{cm:MarkdownDoc}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#MarkdownProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKA; Subkey: "Software\Classes\{#MarkdownProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\{#TextProgId}"; ValueType: string; ValueName: ""; ValueData: "{cm:TextDoc}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#TextProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"",0"
Root: HKA; Subkey: "Software\Classes\{#TextProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""

; The application entry used by "Open with" and by Settings > Apps > Default apps.
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".markdown"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".text"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".docx"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\Applications\{#AppExe}\SupportedTypes"; ValueType: string; ValueName: ".rtf"; ValueData: ""
Root: HKA; Subkey: "Software\rotide.dm\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "{#AppName}"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\rotide.dm\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "{cm:AppDescription}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".md"; ValueData: "{#MarkdownProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".markdown"; ValueData: "{#MarkdownProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mdown"; ValueData: "{#MarkdownProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mkd"; ValueData: "{#MarkdownProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mkdn"; ValueData: "{#MarkdownProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".mdwn"; ValueData: "{#MarkdownProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".txt"; ValueData: "{#TextProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".text"; ValueData: "{#TextProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".docx"; ValueData: "{#TextProgId}"
Root: HKA; Subkey: "Software\rotide.dm\Capabilities\FileAssociations"; ValueType: string; ValueName: ".rtf"; ValueData: "{#TextProgId}"
Root: HKA; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "rotide.dm"; ValueData: "Software\rotide.dm\Capabilities"; Flags: uninsdeletevalue

; "Open with" entries for every supported extension, always.
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "{#MarkdownProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.markdown\OpenWithProgids"; ValueType: string; ValueName: "{#MarkdownProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mdown\OpenWithProgids"; ValueType: string; ValueName: "{#MarkdownProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mkd\OpenWithProgids"; ValueType: string; ValueName: "{#MarkdownProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mkdn\OpenWithProgids"; ValueType: string; ValueName: "{#MarkdownProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.mdwn\OpenWithProgids"; ValueType: string; ValueName: "{#MarkdownProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.txt\OpenWithProgids"; ValueType: string; ValueName: "{#TextProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.text\OpenWithProgids"; ValueType: string; ValueName: "{#TextProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.docx\OpenWithProgids"; ValueType: string; ValueName: "{#TextProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.rtf\OpenWithProgids"; ValueType: string; ValueName: "{#TextProgId}"; ValueData: ""; Flags: uninsdeletevalue

; Markdown opens in rotide.dm by default when the task is ticked. Windows keeps a choice the user made in
; "Open with > Always" above this value; then rotide.dm is offered in that list instead.
Root: HKA; Subkey: "Software\Classes\.md"; ValueType: string; ValueName: ""; ValueData: "{#MarkdownProgId}"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.md"; ValueType: string; ValueName: "Content Type"; ValueData: "text/markdown"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.md"; ValueType: string; ValueName: "PerceivedType"; ValueData: "text"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.markdown"; ValueType: string; ValueName: ""; ValueData: "{#MarkdownProgId}"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.mdown"; ValueType: string; ValueName: ""; ValueData: "{#MarkdownProgId}"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.mkd"; ValueType: string; ValueName: ""; ValueData: "{#MarkdownProgId}"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.mkdn"; ValueType: string; ValueName: ""; ValueData: "{#MarkdownProgId}"; Flags: uninsdeletevalue; Tasks: assocmarkdown
Root: HKA; Subkey: "Software\Classes\.mdwn"; ValueType: string; ValueName: ""; ValueData: "{#MarkdownProgId}"; Flags: uninsdeletevalue; Tasks: assocmarkdown

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
