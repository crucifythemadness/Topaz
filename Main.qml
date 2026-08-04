import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root
    width:  appConfig.windowWidth
    height: appConfig.windowHeight
    minimumWidth:  1280
    minimumHeight:  720
    visible: true
    title: qsTr("Topaz")
    color: Theme.surface

    // Auto-fullscreen when the monitor is exactly one of the supported resolutions.
    visibility: ((Screen.width === 1920 && Screen.height === 1080) ||
                 (Screen.width === 1920 && Screen.height === 1200) ||
                 (Screen.width === 2560 && Screen.height === 1440) ||
                 (Screen.width === 3840 && Screen.height === 2160))
                ? Window.FullScreen : Window.Windowed

    // F11 toggles between fullscreen and windowed.
    Shortcut {
        sequence: "F11"
        onActivated: root.visibility = (root.visibility === Window.FullScreen)
                     ? Window.Windowed : Window.FullScreen
    }

    // Shared data model — owns genre toggle state and mock library.
    // Passed as `lib` property to GenreBar, LibraryTree, AlbumBrowser.
    AppConfig  { id: appConfig }
    LibraryData { id: lib; appConfig: appConfig; libraryModel: libraryModel }
    LibraryModel { id: libraryModel; appConfig: appConfig }

    // Audio playback engine — owns QMediaPlayer + queue model.
    // Passed as `engine` property to AlbumBrowser, PlaybackQueue, NowPlaying.
    PlaybackEngine { id: engine; playlistManager: playlistManager; appConfig: appConfig }

    // Playlist manager — handles XSPF file creation.
    PlaylistManager { id: playlistManager }

    // Windows OS master volume control — see systemvolumecontroller.h.
    SystemVolumeController { id: systemVolume }

    // AUTO PLAY session/policy controller — see UC-16 in the architecture doc.
    // Passed as `autoPlay` property to BottomBar, AlbumBrowser, PlaybackQueue, NowPlaying.
    AutoPlayController {
        id: autoPlay
        engine:           engine
        libraryModel:     libraryModel
        appConfig:        appConfig
        activeGenreNames: lib.activeGenreNames
    }

    // Setup dialog — opened by TopBar's gear icon
    SetupDialog {
        id:        setupDialog
        appConfig: appConfig
    }

    // New-playlist dialog — opened by NowPlaying's + NEW button
    NewPlaylistDialog {
        id:              newPlaylistDialog
        playlistManager: playlistManager
        engine:          engine
    }

    // Kick off cache load + background stat-check once QML engine is ready
    Component.onCompleted: libraryModel.loadCacheAndStartStatCheck()

    // Persist layout (window size + panel widths) 500 ms after the last resize.
    // Window dimensions are only saved when not in fullscreen to avoid
    // overwriting the user's windowed size with the screen resolution.
    onWidthChanged:  saveLayoutTimer.restart()
    onHeightChanged: saveLayoutTimer.restart()

    Timer {
        id: saveLayoutTimer
        interval: 500
        repeat:   false
        onTriggered: {
            const winW = (root.visibility !== Window.FullScreen)
                         ? root.width  : appConfig.windowWidth
            const winH = (root.visibility !== Window.FullScreen)
                         ? root.height : appConfig.windowHeight
            appConfig.saveLayout(winW, winH,
                                 libraryTreePanel.width,
                                 playbackQueuePanel.width,
                                 nowPlayingPanel.width)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TopBar {
            Layout.fillWidth: true
            systemVolume: systemVolume
            onSettingsRequested: setupDialog.open()
        }

        GenreBar {
            Layout.fillWidth: true
            lib: lib
        }

        SplitView {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            orientation: Qt.Horizontal

            // Drag handle — 5 px strip that lights up on hover/press
            handle: Rectangle {
                implicitWidth:  5
                implicitHeight: 5
                color: SplitHandle.pressed ? Theme.secondary
                     : SplitHandle.hovered ? Theme.surfaceContainerHigh
                     :                       Theme.surfaceContainerLow
            }

            LibraryTree {
                id: libraryTreePanel
                SplitView.preferredWidth: appConfig.libraryTreeWidth
                SplitView.minimumWidth:   160
                lib: lib
                onWidthChanged: saveLayoutTimer.restart()
            }

            AlbumBrowser {
                SplitView.fillWidth: true
                SplitView.minimumWidth: 400
                lib: lib
                engine: engine
                autoPlay: autoPlay
            }

            PlaybackQueue {
                id: playbackQueuePanel
                SplitView.preferredWidth: appConfig.playbackQueueWidth
                SplitView.minimumWidth:   240
                engine: engine
                autoPlay: autoPlay
                onWidthChanged: saveLayoutTimer.restart()
            }

            NowPlaying {
                id: nowPlayingPanel
                SplitView.preferredWidth: appConfig.nowPlayingWidth
                SplitView.minimumWidth:   280
                engine:          engine
                playlistManager: playlistManager
                autoPlay:        autoPlay
                onWidthChanged: saveLayoutTimer.restart()
                onNewPlaylistRequested: newPlaylistDialog.open()
            }
        }

        BottomBar {
            Layout.fillWidth: true
            scanning: libraryModel.scanning
            autoPlayReady: libraryModel.ratingsReady
            autoPlay: autoPlay
            onScanRequested: libraryModel.startFullScan()
        }
    }
}
