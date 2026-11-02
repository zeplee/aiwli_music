; AiwliMusic Windows installer (Inno Setup 6)
; Built by CI: ISCC.exe windows/setup.iss /DAPP_VERSION=x.y.z
; Source dir: the flutter build/windows/x64/runner/Release bundle.

[Setup]
AppName=AiwliMusic
AppVersion={#APP_VERSION}
AppPublisher=zeplee
AppPublisherURL=https://github.com/zeplee/aiwli_music
DefaultDirName={autopf}\AiwliMusic
DisableProgramGroupPage=yes
; {autopf} resolves to Program Files (x64) under 64-bit install mode
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=.
OutputBaseFilename=aiwli-music-windows-setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; \
    GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourcePath}\*"; DestDir: "{app}"; \
    Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\AiwliMusic"; Filename: "{app}\aiwli_music.exe"
Name: "{autodesktop}\AiwliMusic"; Filename: "{app}\aiwli_music.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\aiwli_music.exe"; Description: "{cm:LaunchProgram,AiwliMusic}"; \
    Flags: nowait postinstall skipifsilent
