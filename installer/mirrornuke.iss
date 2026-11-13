; Inno Setup script: per-user install (no admin needed), Windows 10 and 11, 64-bit.
[Setup]
AppName=MirrorNuke
AppVersion=2.0.4
AppPublisher=MirrorNuke
DefaultDirName={autopf}\MirrorNuke
DefaultGroupName=MirrorNuke
OutputDir=..\dist
OutputBaseFilename=MirrorNuke-Setup
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\mirrornuke_app.exe

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "..\mirrornuke_app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall skipifsourcedoesntexist

[Icons]
Name: "{group}\MirrorNuke"; Filename: "{app}\mirrornuke_app.exe"
Name: "{autodesktop}\MirrorNuke"; Filename: "{app}\mirrornuke_app.exe"; Tasks: desktopicon

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Microsoft Visual C++ Runtime..."; Flags: waituntilterminated skipifdoesntexist
Filename: "{app}\mirrornuke_app.exe"; Description: "Launch MirrorNuke"; Flags: nowait postinstall skipifsilent
