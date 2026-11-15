; Inno Setup 6 script for the Topaz Windows installer. Built by
; packaging\windows\build-installer.ps1, which stages deploy\ (without BASS / ffmpeg)
; and calls:
;   ISCC.exe /DAppVersion=1.2.0 /DSourceDir=<stage> /DOutputDir=<dist> /DRepoDir=<repo> topaz.iss
;
; Installs per user by default (no admin rights; "for all users" can be chosen) into
; %LOCALAPPDATA%\Programs\Topaz. Running a newer setup over an existing installation
; updates it in place (same AppId -> same folder, same tasks; a running Topaz is closed
; first). The data folder %LOCALAPPDATA%\Topaz (library, playlists, ratings, settings)
; is never touched, not even by the uninstaller. BASS (bass*.dll) and ffmpeg.exe are
; never shipped; copies the user put into the install folder survive updates.

#ifndef AppVersion
  #error Define AppVersion, SourceDir, OutputDir and RepoDir on the command line
#endif

[Setup]
; Never change the AppId: updates find the existing installation by it.
AppId={{779F9DF9-5B1C-4083-AC20-A19404DF8FC1}
AppName=Topaz
AppVersion={#AppVersion}
AppVerName=Topaz {#AppVersion}
AppPublisher=CrucifyTheMadness
AppPublisherURL=https://github.com/crucifythemadness/Topaz
AppSupportURL=https://github.com/crucifythemadness/Topaz
AppUpdatesURL=https://github.com/crucifythemadness/Topaz/releases
AppComments=Audio jukebox for FLAC, MP3 and Opus libraries
DefaultDirName={autopf}\Topaz
DefaultGroupName=Topaz
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
LicenseFile={#SourceDir}\LICENSE.txt
OutputDir={#OutputDir}
OutputBaseFilename=Topaz-{#AppVersion}-setup
SetupIconFile={#RepoDir}\app.ico
UninstallDisplayIcon={app}\Topaz.exe
UninstallDisplayName=Topaz {#AppVersion}
VersionInfoVersion={#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "german"; MessagesFile: "compiler:Languages\German.isl"

[CustomMessages]
english.UserGuide=Topaz User Guide
german.UserGuide=Topaz Benutzerhandbuch (englisch)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; On an update, Qt's generated folders are replaced as a whole, so modules or plugins
; of an older Qt version never linger next to the new ones. Only these folders: the
; root folder may hold the user's own bass*.dll / bass_fx.dll / ffmpeg.exe.
Type: filesandordirs; Name: "{app}\qml"
Type: filesandordirs; Name: "{app}\Topaz"
Type: filesandordirs; Name: "{app}\platforms"
Type: filesandordirs; Name: "{app}\imageformats"
Type: filesandordirs; Name: "{app}\iconengines"
Type: filesandordirs; Name: "{app}\multimedia"
Type: filesandordirs; Name: "{app}\styles"
Type: filesandordirs; Name: "{app}\tls"
Type: filesandordirs; Name: "{app}\generic"
Type: filesandordirs; Name: "{app}\networkinformation"
Type: filesandordirs; Name: "{app}\qmltooling"
Type: filesandordirs; Name: "{app}\translations"

[Files]
; Excludes = second safety net (build-installer.ps1 already leaves these out of the
; stage): BASS and ffmpeg are never bundled.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Excludes: "bass*.dll,ffmpeg.exe,*.log"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Topaz"; Filename: "{app}\Topaz.exe"
Name: "{autoprograms}\{cm:UserGuide}"; Filename: "{app}\Topaz User Guide.pdf"
Name: "{autodesktop}\Topaz"; Filename: "{app}\Topaz.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Topaz.exe"; Description: "{cm:LaunchProgram,Topaz}"; Flags: nowait postinstall skipifsilent
