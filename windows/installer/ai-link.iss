#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef BuildNumber
  #error BuildNumber is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef RuntimePath
  #error RuntimePath is required
#endif

[Setup]
AppId=com.maxhall.ailink.windows
AppName=AI Link
AppVersion={#AppVersion}+{#BuildNumber}
AppPublisher=Max Hall
AppPublisherURL=https://www.tools24.uk/app/ai-link
VersionInfoVersion={#AppVersion}.{#BuildNumber}
VersionInfoDescription=AI Link Setup
DefaultDirName={autopf}\AI Link
DefaultGroupName=AI Link
DisableProgramGroupPage=yes
OutputDir={#OutputDir}
OutputBaseFilename=AI-Link-Setup-{#AppVersion}+{#BuildNumber}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mulit_ai_flutter.exe
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
PrivilegesRequired=admin
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#RuntimePath}"; DestName: "vc_redist.x64.exe"; Flags: dontcopy

[Icons]
Name: "{group}\AI Link"; Filename: "{app}\mulit_ai_flutter.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\AI Link"; Filename: "{app}\mulit_ai_flutter.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\mulit_ai_flutter.exe"; Description: "Launch AI Link"; Flags: nowait postinstall skipifsilent runasoriginaluser

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
begin
  Result := '';
  ExtractTemporaryFile('vc_redist.x64.exe');
  if not Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'),
    '/install /quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) then
  begin
    Result := 'Could not start the Microsoft Visual C++ Runtime installer.';
    Exit;
  end;
  // 1638 means a newer redistributable is already installed.
  if (ExitCode <> 0) and (ExitCode <> 1638) and (ExitCode <> 3010) then
    Result := 'Microsoft Visual C++ Runtime installation failed (' + IntToStr(ExitCode) + ').';
  if ExitCode = 3010 then
    NeedsRestart := True;
end;
