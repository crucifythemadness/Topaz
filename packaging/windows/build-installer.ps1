# Builds the Windows installer dist\Topaz-<version>-setup.exe from deploy\.
#
# Run AFTER the usual Release build + deploy\ assembly (see CLAUDE.md, "Release build /
# deployment") -- this script does not build or deploy anything itself:
#   powershell -ExecutionPolicy Bypass -File packaging\windows\build-installer.ps1
#
# Steps: read the version from CMakeLists.txt; stage deploy\ into build-installer\stage
# (robocopy /MIR, short path -- Qt's paths exceed 260 characters) WITHOUT the user's own
# BASS DLLs, ffmpeg.exe, Hi-Res_Audio.svg and logs (same exclusions as the 7z release),
# plus LICENSE as LICENSE.txt; check the files the app cannot start without; compile
# packaging\windows\topaz.iss with Inno Setup 6 (ISCC); print path + SHA-256.

$ErrorActionPreference = 'Stop'
$root   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$deploy = Join-Path $root 'deploy'
$stage  = Join-Path $root 'build-installer\stage'
$dist   = Join-Path $root 'dist'
$iss    = Join-Path $PSScriptRoot 'topaz.iss'

# Version: project(Topaz VERSION x.y.z ...)
$cmake = Get-Content (Join-Path $root 'CMakeLists.txt') -Raw
if ($cmake -notmatch 'project\(\s*Topaz\s+VERSION\s+(\d+\.\d+\.\d+)') {
    throw 'Could not read the version from CMakeLists.txt (project(Topaz VERSION x.y.z ...))'
}
$version = $Matches[1]
Write-Host "Topaz $version"

if (-not (Test-Path (Join-Path $deploy 'Topaz.exe'))) {
    throw "deploy\Topaz.exe not found -- assemble deploy\ first (CLAUDE.md, Release build / deployment)"
}

# Stage (robocopy exit codes 0-7 = success, >= 8 = failure)
New-Item -ItemType Directory -Force $stage | Out-Null
robocopy $deploy $stage /MIR /NFL /NDL /NJH /NJS /NP `
    /XF 'bass*.dll' 'ffmpeg.exe' 'Hi-Res_Audio.svg' '*.log' | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE" }
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $stage 'LICENSE.txt') -Force

# Without Topaz\qmldir the app exits silently at startup (see CLAUDE.md).
foreach ($required in 'Topaz.exe', 'Topaz\qmldir', 'Topaz\topaz.qmltypes', 'Topaz User Guide.pdf',
                      'libprojectM-4.dll', 'libprojectM-4-playlist.dll', 'glew32.dll', 'qml') {
    if (-not (Test-Path (Join-Path $stage $required))) { throw "Missing in deploy\: $required" }
}
foreach ($forbidden in 'bass.dll', 'bass_fx.dll', 'bassflac.dll', 'bassopus.dll', 'ffmpeg.exe') {
    if (Test-Path (Join-Path $stage $forbidden)) { throw "Must not be shipped: $forbidden" }
}

# Inno Setup 6 (winget install --id JRSoftware.InnoSetup -e) installs per user or system-wide.
$iscc = @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
          "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
          "$env:ProgramFiles\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found (winget install --id JRSoftware.InnoSetup -e)' }

New-Item -ItemType Directory -Force $dist | Out-Null
& $iscc /Q "/DAppVersion=$version" "/DSourceDir=$stage" "/DOutputDir=$dist" "/DRepoDir=$root" $iss
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$setup = Join-Path $dist "Topaz-$version-setup.exe"
$hash  = (Get-FileHash $setup -Algorithm SHA256).Hash
$sizeMb = [math]::Round((Get-Item $setup).Length / 1MB, 1)
Write-Host "Installer: $setup ($sizeMb MB)"
Write-Host "SHA-256:   $hash"
