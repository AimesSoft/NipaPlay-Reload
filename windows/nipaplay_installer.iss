[Setup]
AppName=NipaPlay
AppVersion={#GetFileVersion("NipaPlay.exe")}
AppVerName=NipaPlay {#GetFileVersion("NipaPlay.exe")}
AppPublisher=MCDFSteve
AppPublisherURL=https://github.com/MCDFsteve/NipaPlay-Reload
AppSupportURL=https://github.com/MCDFsteve/NipaPlay-Reload/issues
AppUpdatesURL=https://github.com/MCDFsteve/NipaPlay-Reload/releases
DefaultDirName={autopf}\NipaPlay
DefaultGroupName=NipaPlay
AllowNoIcons=yes
LicenseFile=LICENSE
OutputDir=.
OutputBaseFilename=NipaPlay_{#GetFileVersion("NipaPlay.exe")}_Windows_Setup
SetupIconFile=nipaplay_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\NipaPlay.exe
UninstallDisplayName=NipaPlay
ArchitecturesInstallIn64BitMode=x64 arm64
ArchitecturesAllowed=x64 arm64

; 安装程序界面图片配置
WizardImageFile=installer_banner.bmp
WizardSmallImageFile=installer_small.bmp

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1

[Files]
Source: "NipaPlay.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "*.dll"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\NipaPlay"; Filename: "{app}\NipaPlay.exe"
Name: "{group}\{cm:UninstallProgram,NipaPlay}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\NipaPlay"; Filename: "{app}\NipaPlay.exe"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\NipaPlay"; Filename: "{app}\NipaPlay.exe"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\NipaPlay.exe"; Description: "{cm:LaunchProgram,NipaPlay}"; Flags: nowait postinstall skipifsilent

[Registry]
; 注册文件关联
Root: HKCR; Subkey: ".mp4"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mkv"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".avi"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".mov"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".wmv"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".flv"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: ".webm"; ValueType: string; ValueName: ""; ValueData: "NipaPlay.VideoFile"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "NipaPlay.VideoFile"; ValueType: string; ValueName: ""; ValueData: "NipaPlay 视频文件"; Flags: uninsdeletekey
Root: HKCR; Subkey: "NipaPlay.VideoFile\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\NipaPlay.exe,0"
Root: HKCR; Subkey: "NipaPlay.VideoFile\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\NipaPlay.exe"" ""%1"""

[Code]
function GetFileVersion(const FileName: string): string;
var
  FileVersionMS, FileVersionLS: cardinal;
  Major, Minor, Rev, Build: cardinal;
begin
  if GetVersionNumbers(FileName, FileVersionMS, FileVersionLS) then
  begin
    Major := FileVersionMS shr 16;
    Minor := FileVersionMS and $FFFF;
    Rev := FileVersionLS shr 16;
    Build := FileVersionLS and $FFFF;
    Result := IntToStr(Major) + '.' + IntToStr(Minor) + '.' + IntToStr(Rev);
  end
  else
    Result := '1.0.0';
end; 