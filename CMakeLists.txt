cmake_minimum_required(VERSION 3.16)

project(Topaz VERSION 0.1 LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick QuickControls2 QuickDialogs2 Multimedia)

qt_standard_project_setup()

qt_add_executable(topaz
    main.cpp
    appconfig.h
    appconfig.cpp
    trackinfo.h
    tagreader.h
    tagreader.cpp
    librarycache.h
    librarycache.cpp
    libraryscanner.h
    libraryscanner.cpp
    librarymodel.h
    librarymodel.cpp
    playbackengine.h
    playbackengine.cpp
    playlistmanager.h
    playlistmanager.cpp
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
)

set_target_properties(topaz PROPERTIES
    OUTPUT_NAME Topaz
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(topaz
    PRIVATE Qt6::Core Qt6::Gui Qt6::Quick Qt6::QuickControls2 Qt6::QuickDialogs2 Qt6::Multimedia Qt6::Concurrent
)

include(GNUInstallDirs)
install(TARGETS topaz
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
