; Compile with ISCC /DAppVersion=... /DBuildNumber=... /DSourceDir=... /DOutputDir=...
#ifndef AppVersion
  #error AppVersion must be supplied
#endif
#ifndef BuildNumber
  #error BuildNumber must be supplied
#endif
#ifndef SourceDir
  #error SourceDir must be supplied
#endif
#ifndef OutputDir
  #error OutputDir must be supplied
#endif

[Setup]
AppId={{A7FA1833-586A-4EEA-AB98-245192FDF287}
AppName=背诵助手
AppVersion={#AppVersion}
AppPublisher=BibleRecite
DefaultDirName={localappdata}\Programs\BibleRecite
DefaultGroupName=背诵助手
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19041
OutputDir={#OutputDir}
OutputBaseFilename=BibleRecite-Windows-{#AppVersion}-build-{#BuildNumber}-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\bible_recite.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\背诵助手"; Filename: "{app}\bible_recite.exe"; AppUserModelID: "app.biblerecite.desktop"
Name: "{autodesktop}\背诵助手"; Filename: "{app}\bible_recite.exe"; AppUserModelID: "app.biblerecite.desktop"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\bible_recite.exe"; Description: "Launch BibleRecite"; Flags: nowait postinstall skipifsilent
