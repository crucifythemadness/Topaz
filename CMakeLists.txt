cmake_minimum_required(VERSION 3.21)

# Full major.minor.patch (not just 0.1) — projectM's version.h.in reads
# CMAKE_PROJECT_VERSION_PATCH from the top-level project() call (us, once
# FetchContent'd as a subdirectory), and an unset patch component makes that
# substitution expand to nothing, breaking their generated version.h.
project(Topaz VERSION 1.1.0 LANGUAGES CXX C)

# RC (Windows resource compiler, for app.rc's icon) is MinGW/MSVC-only --
# Linux's cmake has no RC language support at all, so it can't be declared
# unconditionally in the project() call above (evaluated before any
# if(WIN32) guard could run) without breaking Linux configure entirely.
if (WIN32)
    enable_language(RC)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick QuickControls2 QuickDialogs2 Multimedia Widgets OpenGL Concurrent)
# Separate from Qt6::OpenGL (Qt's own wrapper module, already required
# above) -- this is CMake's own FindOpenGL module, needed for the raw
# OpenGL::GL target MilkdropView's direct glViewport/glReadPixels calls
# link against on non-Windows (see the target_link_libraries split below).
find_package(OpenGL REQUIRED)

qt_standard_project_setup()

# QTP0001: NEW changes the default QML resource prefix to ":/qt/qml/". Everything
# here loads its assets from the classic ":/Topaz/..." (qrc:/Topaz/app.ico in
# AboutDialog.qml, ":/Topaz/app.ico" in main.cpp / autoplaycontroller.cpp, the .svg
# icons, ...), so qt_add_qml_module below passes RESOURCE_PREFIX / explicitly --
# Qt's documented way to keep the old paths. (Leaving the policy unset, or setting
# it to OLD, each make Qt print a configure warning.)
qt_policy(SET QTP0001 NEW)

# ── projectM (Milkdrop-compatible visualizer, see UC-20) ──────────────────
# MilkdropView renders into an offscreen QOpenGLContext/QOpenGLFramebufferObject
# (Qt6::OpenGL), fully independent of Qt Quick's own D3D11-by-default scenegraph.
include(FetchContent)

# projectM's Windows Core-Profile path requires GLEW (find_package(GLEW REQUIRED)),
# which isn't part of the Qt/MinGW toolchain. GLEW's git repo doesn't check in its
# generated src/glew.c and include/GL/glew.h (release-only), so fetch the official
# release archive instead of the git repo, and point SOURCE_SUBDIR at its bundled
# CMake support dir. OVERRIDE_FIND_PACKAGE makes projectM's find_package(GLEW)
# transparently resolve to this fetched copy instead of searching the system.
FetchContent_Declare(
    GLEW
    URL https://github.com/nigels-com/glew/releases/download/glew-2.2.0/glew-2.2.0.zip
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
    SOURCE_SUBDIR build/cmake
    OVERRIDE_FIND_PACKAGE
)
# GLEW's own CMakeLists.txt still says cmake_minimum_required(VERSION 2.8.12), which
# makes every configure print a "Compatibility with CMake < 3.5" deprecation warning
# from third-party code we can't edit. Only the CACHE variable silences it (a normal
# variable is ignored for this message), so it's switched off just around GLEW's
# add_subdirectory and put back right after -- our own deprecation warnings stay on.
set(_topaz_prev_warn_deprecated "${CMAKE_WARN_DEPRECATED}")
set(CMAKE_WARN_DEPRECATED OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(GLEW)
if("${_topaz_prev_warn_deprecated}" STREQUAL "")
    unset(CMAKE_WARN_DEPRECATED CACHE)
else()
    set(CMAKE_WARN_DEPRECATED "${_topaz_prev_warn_deprecated}" CACHE BOOL "" FORCE)
endif()
# GLEW's raw CMakeLists.txt only defines plain `glew`/`glew_s` targets, not the
# namespaced `GLEW::glew` target projectM's CMakeLists checks for.
if(TARGET glew AND NOT TARGET GLEW::glew)
    add_library(GLEW::glew ALIAS glew)
    # GLEW's CMakeLists.txt sets its include dir via the old directory-scoped
    # include_directories(), which only affects GLEW's own sources, not targets
    # that link against it elsewhere (like projectM's MilkdropPreset). Add it
    # as a proper INTERFACE include dir so it propagates through the target.
    target_include_directories(glew INTERFACE $<BUILD_INTERFACE:${glew_SOURCE_DIR}/include>)
    # GLEW's CMakeLists.txt unconditionally redirects its own DLL output to
    # <build>/bin, separate from where Topaz.exe and the projectM DLLs land
    # (the build root, inherited from qt_standard_project_setup()) — force it
    # back so all runtime DLLs sit next to Topaz.exe with no extra deploy step.
    set_target_properties(glew PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
endif()

FetchContent_Declare(
    projectm
    GIT_REPOSITORY https://github.com/projectM-visualizer/projectm.git
    GIT_TAG v4.1.7
)
FetchContent_MakeAvailable(projectm)

qt_add_executable(topaz
    main.cpp
    appconfig.h
    appconfig.cpp
    trackinfo.h
    tagreader.h
    tagreader.cpp
    tagwriter.h
    tagwriter.cpp
    mp3converter.h
    mp3converter.cpp
    volumepath.h
    volumepath.cpp
    librarycache.h
    librarycache.cpp
    ratingcache.h
    ratingcache.cpp
    buildinfo.h
    buildinfo.cpp
    libraryscanner.h
    libraryscanner.cpp
    librarymodel.h
    librarymodel.cpp
    audiodeck.h
    ffmpegaudiodeck.h
    ffmpegaudiodeck.cpp
    basslibrary.h
    basslibrary.cpp
    bassaudiodeck.h
    bassaudiodeck.cpp
    # Auto Loudness Correction (UC-35)
    loudnessanalyzer.h
    loudnessanalyzer.cpp
    loudnesslog.h
    volumenormalizationcache.h
    volumenormalizationcache.cpp
    compressormeter.h
    compressormeter.cpp
    playbackengine.h
    playbackengine.cpp
    playlistmanager.h
    playlistmanager.cpp
    autoplaycontroller.h
    autoplaycontroller.cpp
    systemvolumecontroller.h
    systemvolumecontroller.cpp
    windowchrome.h
    windowchrome.cpp
    cursorautohider.h
    cursorautohider.cpp
    hiresaudiologo.h
    hiresaudiologo.cpp
    audiovisualizercontroller.h
    audiovisualizercontroller.cpp
    milkdropview.h
    milkdropview.cpp
    milkdroppresetchecker.h
    milkdroppresetchecker.cpp
    milkdropcleanupcontroller.h
    milkdropcleanupcontroller.cpp
    playlistexportworker.h
    playlistexportworker.cpp
    playlistexportcontroller.h
    playlistexportcontroller.cpp
    genrescancontroller.h
    genrescancontroller.cpp
    backuprestorecontroller.h
    backuprestorecontroller.cpp
    # Vendored third-party (BSD-3-Clause) — see third_party/kissfft/LICENSES/
    # BSD-3-Clause. Unmodified upstream sources; do not edit directly.
    third_party/kissfft/kiss_fft.h
    third_party/kissfft/kiss_fft.c
    third_party/kissfft/kiss_fft_log.h
    third_party/kissfft/_kiss_fft_guts.h
    third_party/kissfft/kiss_fftr.h
    third_party/kissfft/kiss_fftr.c
    # Vendored third-party (Public Domain / MIT dual-license) — see
    # third_party/miniz/LICENSE. Unmodified upstream sources; do not edit
    # directly. Amalgamated single-file distribution (v3.1.2) from
    # github.com/richgel999/miniz, used by BackupRestoreController (UC-27)
    # for the BACKUP/RESTORE feature's *.zip files.
    third_party/miniz/miniz.h
    third_party/miniz/miniz.c
)

# app.rc (the .ico embed) needs the Windows-only RC language enabled above --
# not listed in the qt_add_executable() source list itself, since that's
# evaluated unconditionally regardless of platform.
if (WIN32)
    target_sources(topaz PRIVATE app.rc)
endif()

# Mark Theme.qml as a QML singleton so the generated qmldir
# includes the "singleton" keyword, enabling `Theme.primary` access
# in all other QML files in the Topaz module.
set_source_files_properties(Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(topaz
    URI Topaz
    VERSION 1.0
    RESOURCE_PREFIX /
    QML_FILES
        Main.qml
        Theme.qml
        LibraryData.qml
        SearchData.qml
        PlaylistsData.qml
        TopBar.qml
        GenreBar.qml
        LibraryTree.qml
        SearchPanel.qml
        PlaylistsPanel.qml
        AlbumBrowser.qml
        SearchResultBrowser.qml
        PlaylistViewer.qml
        AlbumCard.qml
        PlaybackQueue.qml
        NowPlaying.qml
        BottomBar.qml
        SetupDialog.qml
        AboutDialog.qml
        NewPlaylistDialog.qml
        MessageBox.qml
        MissingTracksDialog.qml
        MissingTrackDialog.qml
        FloatingPane.qml
        BigCoverWindow.qml
        TagInfoWindow.qml
        AudioVisualizerWindow.qml
        MilkdropWindow.qml
        MilkdropCleanupDialog.qml
        ExportPlaylistDialog.qml
        ChoiceDialog.qml
        BackupDialog.qml
        RestoreDialog.qml
        ImportPlaylistDialog.qml
        ScanFoldersDialog.qml
        VolumeKnob.qml
        FoundGenresDialog.qml
    RESOURCES
        app.ico
        InfoAbout.png
        Claude_Logo.png
        CrucifyTheMadness_Logo.png
        Qt_Logo.png
        FFmpeg_Logo.png
        ProjectM_Logo.png
        Harddisk_Icon.svg
        UsbStick_Icon.svg
        TrashBin_Icon.svg
)

if (WIN32)
    # OUTPUT_NAME Topaz -> Topaz.exe -- capitalized to match the project name.
    # Windows filenames are case-insensitive, so this never collides with
    # anything. WIN32_EXECUTABLE suppresses the console window.
    set_target_properties(topaz PROPERTIES
        OUTPUT_NAME Topaz
        WIN32_EXECUTABLE TRUE
    )
else()
    # Deliberately NOT "Topaz" here (unlike Windows' Topaz.exe): on a
    # case-sensitive filesystem, an executable literally named "Topaz"
    # collides with qt_add_qml_module()'s own generated "Topaz/" companion
    # directory (URI Topaz, see below) sitting right next to it in the same
    # build directory -- the linker fails with "cannot open output file
    # Topaz: Is a directory". Windows' ".exe" suffix never hits this, since
    # "Topaz.exe" and "Topaz/" are different names there too, but even on
    # case-INsensitive NTFS they'd already differ by that suffix regardless.
    # Leaving OUTPUT_NAME unset keeps CMake's default (the target's own
    # name, "topaz", lowercase) -- distinct from "Topaz/" on ext4, and a
    # more idiomatic lowercase binary name for Linux besides.
    set_target_properties(topaz PROPERTIES OUTPUT_NAME topaz)
endif()

# Exposes CMake's own project() version to BuildInfo (buildinfo.h/cpp) for
# the About Topaz dialog, so the displayed version never drifts out of sync
# with the one place it's actually declared.
target_compile_definitions(topaz PRIVATE TOPAZ_VERSION_STRING="${PROJECT_VERSION}")

# Build date for the same dialog: a generated header, refreshed on every build
# but only rewritten when the day changed (see cmake/WriteBuildDate.cmake).
add_custom_target(topaz_build_date
    COMMAND ${CMAKE_COMMAND} -DOUT=${CMAKE_CURRENT_BINARY_DIR}/topaz_build_date.h
            -P ${CMAKE_CURRENT_SOURCE_DIR}/cmake/WriteBuildDate.cmake
    BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/topaz_build_date.h
    COMMENT "Refreshing topaz_build_date.h"
    VERBATIM)
add_dependencies(topaz topaz_build_date)
target_include_directories(topaz PRIVATE ${CMAKE_CURRENT_BINARY_DIR})

# MinGW/COFF objects cap out at ~32k sections. The QML AOT compiler generates
# one function per binding/handler, and SetupDialog.qml (by far this repo's
# largest QML file, seven Setup tabs' worth of UI) crossed that ceiling --
# "too many sections" / "file too big" from `as` when building its generated
# .rcc/qmlcache/topaz_SetupDialog_qml.cpp.obj. -Wa,-mbig-obj switches that
# object to the bigobj COFF variant (a larger section-count field), which is
# the standard fix for this MinGW-specific limit; it doesn't affect ELF/Mach-O
# builds so it's MinGW-only rather than applied unconditionally.
if (MINGW)
    target_compile_options(topaz PRIVATE -Wa,-mbig-obj)
endif()

target_link_libraries(topaz
    PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::QuickDialogs2 Qt6::Multimedia Qt6::Concurrent Qt6::Widgets Qt6::OpenGL
    PRIVATE libprojectM::projectM libprojectM::playlist
    # MilkdropView must call glewInit() itself before using projectM — see
    # UC-20's "glewInit()" note; libprojectM doesn't do this internally.
    PRIVATE GLEW::glew
)
if (WIN32)
    target_link_libraries(topaz
        PRIVATE ole32 dwmapi
        # MilkdropView calls glViewport/glReadPixels directly (core OpenGL
        # 1.1, not behind GLEW's loader) to read back projectM's rendered
        # frame -- opengl32 is the Windows-only GL loader import lib name.
        PRIVATE opengl32
    )
else()
    # Same glViewport/glReadPixels readback need as opengl32 above, via
    # CMake's own FindOpenGL module (find_package(OpenGL REQUIRED) near the
    # top of this file) rather than a Windows-only literal lib name.
    target_link_libraries(topaz PRIVATE OpenGL::GL)

    # SystemVolumeController's Linux branch is a native libpulse client
    # (PulseAudio, and PipeWire via pipewire-pulse) -- libpulse-dev provides
    # the header + the pkg-config file.
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(PULSE REQUIRED IMPORTED_TARGET libpulse)
    target_link_libraries(topaz PRIVATE PkgConfig::PULSE)
endif()

include(GNUInstallDirs)
install(TARGETS topaz
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
