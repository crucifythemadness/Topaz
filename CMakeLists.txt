cmake_minimum_required(VERSION 3.21)

# Full major.minor.patch (not just 0.1) — projectM's version.h.in reads
# CMAKE_PROJECT_VERSION_PATCH from the top-level project() call (us, once
# FetchContent'd as a subdirectory), and an unset patch component makes that
# substitution expand to nothing, breaking their generated version.h.
project(Topaz VERSION 0.1.0 LANGUAGES CXX C RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick QuickControls2 QuickDialogs2 Multimedia Widgets OpenGL)

qt_standard_project_setup()

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
FetchContent_MakeAvailable(GLEW)
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
    volumepath.h
    volumepath.cpp
    librarycache.h
    librarycache.cpp
    ratingcache.h
    ratingcache.cpp
    libraryscanner.h
    libraryscanner.cpp
    librarymodel.h
    librarymodel.cpp
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
    audiovisualizercontroller.h
    audiovisualizercontroller.cpp
    milkdropview.h
    milkdropview.cpp
    # Vendored third-party (BSD-3-Clause) — see third_party/kissfft/LICENSES/
    # BSD-3-Clause. Unmodified upstream sources; do not edit directly.
    third_party/kissfft/kiss_fft.h
    third_party/kissfft/kiss_fft.c
    third_party/kissfft/kiss_fft_log.h
    third_party/kissfft/_kiss_fft_guts.h
    third_party/kissfft/kiss_fftr.h
    third_party/kissfft/kiss_fftr.c
    app.rc
)

# Mark Theme.qml as a QML singleton so the generated qmldir
# includes the "singleton" keyword, enabling `Theme.primary` access
# in all other QML files in the Topaz module.
set_source_files_properties(Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(topaz
    URI Topaz
    VERSION 1.0
    QML_FILES
        Main.qml
        Theme.qml
        LibraryData.qml
        TopBar.qml
        GenreBar.qml
        LibraryTree.qml
        AlbumBrowser.qml
        AlbumCard.qml
        PlaybackQueue.qml
        NowPlaying.qml
        BottomBar.qml
        SetupDialog.qml
        NewPlaylistDialog.qml
        MessageBox.qml
        FloatingPane.qml
        BigCoverWindow.qml
        TagInfoWindow.qml
        AudioVisualizerWindow.qml
        MilkdropWindow.qml
    RESOURCES
        app.ico
)

set_target_properties(topaz PROPERTIES
    OUTPUT_NAME Topaz
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(topaz
    PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::QuickDialogs2 Qt6::Multimedia Qt6::Concurrent Qt6::Widgets Qt6::OpenGL
    PRIVATE ole32 dwmapi
    PRIVATE libprojectM::projectM libprojectM::playlist
    # MilkdropView must call glewInit() itself before using projectM — see
    # UC-20's "glewInit()" note; libprojectM doesn't do this internally.
    PRIVATE GLEW::glew
    # MilkdropView calls glViewport/glReadPixels directly (core OpenGL 1.1,
    # not behind GLEW's loader) to read back projectM's rendered frame.
    PRIVATE opengl32
)

include(GNUInstallDirs)
install(TARGETS topaz
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
