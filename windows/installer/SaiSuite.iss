; Build parameters come from tools/build_windows_installer.py.
[Setup]
AppId=io.github.wxia529.SaiSuite.Windows
AppName=赛赛工具箱
AppVersion={#AppVersion}+{#BuildNumber}
AppVerName=赛赛工具箱 {#AppVersion}
AppPublisher=SaiSuite
AppPublisherURL=https://github.com/wxia529/SaiSuite
AppSupportURL=https://github.com/wxia529/SaiSuite/issues
AppUpdatesURL=https://github.com/wxia529/SaiSuite/releases
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoDescription=赛赛工具箱安装程序
DefaultDirName={localappdata}\Programs\SaiSuite
DefaultGroupName=赛赛工具箱
DisableDirPage=no
DisableProgramGroupPage=no
PrivilegesRequired=lowest
MinVersion=10.0
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=SaiSuite-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\saisuite.exe
WizardStyle=modern
Compression=lzma2/normal
SolidCompression=yes
AppMutex=SaiSuite.Desktop
CloseApplications=no
RestartApplications=no
Uninstallable=yes
UninstallDisplayName=赛赛工具箱
SetupLogging=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\赛赛工具箱"; Filename: "{app}\saisuite.exe"; WorkingDir: "{app}"
Name: "{group}\卸载赛赛工具箱"; Filename: "{uninstallexe}"
Name: "{autodesktop}\赛赛工具箱"; Filename: "{app}\saisuite.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\saisuite.exe"; Description: "启动赛赛工具箱"; Flags: nowait postinstall skipifsilent

; No UninstallDelete: exports, preferences and files the user added are retained.
