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

    // ── Detachable "big cover" pane ──────────────────────────────────────
    // Opened by clicking the album cover in NowPlaying (see below); see
    // FloatingPane.qml / BigCoverWindow.qml for the pane itself.
    property bool bigCoverPaneOpen: false

    // True if rect (x,y,w,h), in virtual-desktop coordinates, overlaps at
    // least one currently connected screen — used to validate a saved
    // position before restoring it (a monitor may have been unplugged or
    // rearranged since it was last saved).
    function rectIntersectsAnyScreen(x, y, w, h) {
        const screens = Qt.application.screens
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i]
            if (x < s.virtualX + s.width && x + w > s.virtualX &&
                y < s.virtualY + s.height && y + h > s.virtualY)
                return true
        }
        return false
    }

    Loader {
        id: bigCoverLoader
        active: root.bigCoverPaneOpen
        // engine is deliberately NOT set as a declarative "engine: engine"
        // binding inside the BigCoverWindow {} block below: that would be a
        // property assignment on the root object of this Loader's inline
        // Component, and BigCoverWindow declares its own "property var
        // engine: null" — in that specific position, QML resolves the
        // unqualified "engine" against the object's own just-declared
        // property instead of walking out to this file's "engine" id
        // (confirmed empirically: it read back as null; appConfig/root, which
        // have no name collision, resolved fine in the same
        // Component.onCompleted below). Setting it here in onLoaded — a plain
        // signal handler on the Loader itself, not inside the Component —
        // resolves "engine" via this file's normal scope, unambiguously.
        onLoaded: { if (item) item.engine = engine }

        sourceComponent: BigCoverWindow {
            id: bigCoverWindow

            Component.onCompleted: {
                if (appConfig.bigCoverPaneConfigured &&
                    root.rectIntersectsAnyScreen(appConfig.bigCoverPaneX, appConfig.bigCoverPaneY,
                                                  appConfig.bigCoverPaneWidth, appConfig.bigCoverPaneHeight)) {
                    width  = appConfig.bigCoverPaneWidth
                    height = appConfig.bigCoverPaneHeight
                    x      = appConfig.bigCoverPaneX
                    y      = appConfig.bigCoverPaneY
                } else {
                    width  = 400
                    height = 400
                    x = Screen.virtualX + (Screen.width  - width)  / 2
                    y = Screen.virtualY + (Screen.height - height) / 2
                }
                visible = true
                // Without this, a newly created sibling window can end up
                // hidden behind the main window when it's in exclusive
                // fullscreen (Window.FullScreen) — raise()/requestActivate()
                // ensure the pane is actually on top and focused when opened.
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveBigCoverPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.bigCoverPaneOpen = false
        }
    }

    // ── Detachable "tag info" pane ───────────────────────────────────────
    // Opened by toggling the "TAG INFORMATION" button in BottomBar; see
    // FloatingPane.qml / TagInfoWindow.qml for the pane itself. Mirrors the
    // bigCoverLoader wiring above exactly (same engine-binding scoping
    // gotcha applies — see the onLoaded comment above).
    property bool tagInfoPaneOpen: false

    Loader {
        id: tagInfoLoader
        active: root.tagInfoPaneOpen
        onLoaded: { if (item) item.engine = engine }

        sourceComponent: TagInfoWindow {
            id: tagInfoWindow

            Component.onCompleted: {
                if (appConfig.tagInfoPaneConfigured &&
                    root.rectIntersectsAnyScreen(appConfig.tagInfoPaneX, appConfig.tagInfoPaneY,
                                                  appConfig.tagInfoPaneWidth, appConfig.tagInfoPaneHeight)) {
                    width  = appConfig.tagInfoPaneWidth
                    height = appConfig.tagInfoPaneHeight
                    x      = appConfig.tagInfoPaneX
                    y      = appConfig.tagInfoPaneY
                } else {
                    width  = 500
                    height = 230
                    x = Screen.virtualX + (Screen.width  - width)  / 2
                    y = Screen.virtualY + (Screen.height - height) / 2
                }
                visible = true
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveTagInfoPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.tagInfoPaneOpen = false
        }
    }

    // ── Detachable "audio visualizer" pane ───────────────────────────────
    // Opened by toggling the "AUDIO VISUALIZER" button in BottomBar; see
    // FloatingPane.qml / AudioVisualizerWindow.qml for the pane itself, and
    // AudioVisualizerController (C++) for the FFT/analysis pipeline that
    // feeds it. Mirrors the tagInfoLoader wiring above exactly (same
    // engine-binding scoping gotcha applies — see the onLoaded comment
    // above bigCoverLoader).
    property bool audioVisualizerPaneOpen: false

    Loader {
        id: audioVisualizerLoader
        active: root.audioVisualizerPaneOpen
        onLoaded: {
            if (item) {
                item.engine           = engine
                item.visualizer       = audioVisualizer
                item.visualizerConfig = appConfig
            }
        }

        sourceComponent: AudioVisualizerWindow {
            id: audioVisualizerWindow

            Component.onCompleted: {
                if (appConfig.audioVisualizerPaneConfigured &&
                    root.rectIntersectsAnyScreen(appConfig.audioVisualizerPaneX, appConfig.audioVisualizerPaneY,
                                                  appConfig.audioVisualizerPaneWidth, appConfig.audioVisualizerPaneHeight)) {
                    width  = appConfig.audioVisualizerPaneWidth
                    height = appConfig.audioVisualizerPaneHeight
                    x      = appConfig.audioVisualizerPaneX
                    y      = appConfig.audioVisualizerPaneY
                } else {
                    width  = 500
                    height = 260
                    x = Screen.virtualX + (Screen.width  - width)  / 2
                    y = Screen.virtualY + (Screen.height - height) / 2
                }
                visible = true
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveAudioVisualizerPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.audioVisualizerPaneOpen = false
        }
    }

    // ── Detachable "milkdrop" pane ────────────────────────────────────────
    // Opened by toggling the "MILKDROP" button in BottomBar; see
    // FloatingPane.qml / MilkdropWindow.qml for the pane itself, and
    // MilkdropView (C++) for the projectM render pipeline it owns directly
    // (unlike audioVisualizerLoader above, there's no separate long-lived
    // controller object here — see UC-20). Mirrors audioVisualizerLoader's
    // wiring otherwise, including the same engine-binding scoping gotcha.
    property bool milkdropPaneOpen: false

    Loader {
        id: milkdropLoader
        active: root.milkdropPaneOpen
        onLoaded: {
            if (item) {
                item.engine         = engine
                item.milkdropConfig = appConfig
            }
        }

        sourceComponent: MilkdropWindow {
            id: milkdropWindow

            Component.onCompleted: {
                if (appConfig.milkdropPaneConfigured &&
                    root.rectIntersectsAnyScreen(appConfig.milkdropPaneX, appConfig.milkdropPaneY,
                                                  appConfig.milkdropPaneWidth, appConfig.milkdropPaneHeight)) {
                    width  = appConfig.milkdropPaneWidth
                    height = appConfig.milkdropPaneHeight
                    x      = appConfig.milkdropPaneX
                    y      = appConfig.milkdropPaneY
                } else {
                    width  = 560
                    height = 360
                    x = Screen.virtualX + (Screen.width  - width)  / 2
                    y = Screen.virtualY + (Screen.height - height) / 2
                }
                visible = true
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveMilkdropPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.milkdropPaneOpen = false
        }
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

    // Audio visualizer analysis pipeline — see UC-19 in the architecture doc.
    // Passed as `visualizer` property to AudioVisualizerWindow.
    AudioVisualizerController {
        id: audioVisualizer
        engine:    engine
        appConfig: appConfig
    }

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
                onBigCoverRequested: root.bigCoverPaneOpen = true
            }
        }

        BottomBar {
            Layout.fillWidth: true
            scanning: libraryModel.scanning
            autoPlayReady: libraryModel.ratingsReady
            autoPlay: autoPlay
            tagInfoPaneOpen: root.tagInfoPaneOpen
            audioVisualizerPaneOpen: root.audioVisualizerPaneOpen
            milkdropPaneOpen: root.milkdropPaneOpen
            onScanRequested: libraryModel.startFullScan()
            onTagInfoToggleRequested: root.tagInfoPaneOpen = !root.tagInfoPaneOpen
            onAudioVisualizerToggleRequested: root.audioVisualizerPaneOpen = !root.audioVisualizerPaneOpen
            onMilkdropToggleRequested: root.milkdropPaneOpen = !root.milkdropPaneOpen
        }
    }
}
