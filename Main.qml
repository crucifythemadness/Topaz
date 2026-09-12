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

    // Startup fullscreen/windowed is a user preference (Setup > MISC), not
    // resolution-driven -- see AudioJukeboxTopaz.md's "Supported Resolutions"
    // section.
    visibility: appConfig.startFullscreen ? Window.FullScreen : Window.Windowed

    // F11 toggles between fullscreen and windowed.
    Shortcut {
        sequence: "F11"
        onActivated: root.visibility = (root.visibility === Window.FullScreen)
                     ? Window.Windowed : Window.FullScreen
    }

    // Vetoes closing while MilkdropCleanupController is mid-scan (see UC-25) --
    // the only long-running operation in this app that keeps pumping the
    // event loop (via processEvents()) while it runs, unlike LibraryScanner's
    // scan (which simply freezes the window solid, so a close event has no
    // chance to land mid-loop there). Without this veto, a close delivered
    // while startCleanup() is still on the call stack risks tearing down the
    // QML engine (and this controller) out from under it mid-loop.
    onClosing: (close) => {
        if (milkdropCleanupController.cleaning)
            close.accepted = false
    }

    // Which of TopBar's three navigation tabs is active. Shell-level state
    // (not library- or search-specific), same precedent as the pane-open
    // properties below. Drives which components the SplitView's first two
    // Loaders load — see UC-21 (search) / UC-22 (playlists).
    property string activeTab: "library"

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
    LibraryData { id: lib; appConfig: appConfig; libraryModel: libraryModel; activeTab: root.activeTab }
    LibraryModel { id: libraryModel; appConfig: appConfig }

    // Search state -- deliberately independent of LibraryData (see
    // SearchData.qml). activeGenreNames/enabledGenreNames are the two
    // read-only exceptions, needed for the SEARCH tab's "Consider Genre"
    // checkbox and its enabled-genres baseline respectively.
    SearchData {
        id: search
        libraryModel:      libraryModel
        activeGenreNames:  lib.activeGenreNames
        enabledGenreNames: appConfig.enabledGenres
    }

    // Audio playback engine — owns QMediaPlayer + queue model.
    // Passed as `engine` property to AlbumBrowser, PlaybackQueue, NowPlaying.
    PlaybackEngine { id: engine; playlistManager: playlistManager; appConfig: appConfig }

    // Startup notice for PlaybackEngine's silent BASS->FFmpeg fallback (see
    // UC-15 "Step 2b") -- a separate top-level instance from SetupDialog's
    // own PLAYBACK-tab MessageBoxes since it must work even if Setup isn't
    // open when the fallback happens.
    MessageBox {
        id: bassFallbackNoticeBox
        title: "PLAYBACK ENGINE"
        message: "BASS Audio Library was selected, but its files could not be found.<br><br>" +
                 "Topaz switched back to <b>FFmpeg</b> for this session.<br><br>" +
                 "To use BASS Audio Library, download <b>bass.dll</b>, <b>bassflac.dll</b> and " +
                 "<b>bassopus.dll</b> and place them next to Topaz.exe, then reselect it in Setup." +
                 "<br><br><a href=\"https://www.un4seen.com/\">https://www.un4seen.com/</a>"
    }
    Connections {
        target: engine
        function onBassUnavailableFallback() { bassFallbackNoticeBox.open() }
    }

    // "MISSING TRACK" alert -- see UC-31. Genuine always-on-top top-level
    // Window (not a Popup), so it renders above Milkdrop/AudioVisualizer/
    // BigCover/TagInfo even if one of those is floating full-screen on
    // another monitor when this fires. Kicks off the targeted single-folder
    // rescan here too, keeping PlaybackEngine decoupled from LibraryModel/
    // AppConfig folder concerns -- same split as missingPlaylistTracks/UC-10.
    MissingTrackDialog { id: missingTrackDialog }
    Connections {
        target: engine
        function onTrackMissing(artist, album, title, filePath) {
            missingTrackDialog.artistText = artist
            missingTrackDialog.albumText  = album
            missingTrackDialog.titleText  = title
            missingTrackDialog.openCentered(root)
            libraryModel.rescanFolderContaining(filePath)
        }
    }

    // Playlist manager — handles XSPF file creation.
    PlaylistManager { id: playlistManager }

    // Playlists tab state -- deliberately independent of LibraryData/
    // SearchData (see PlaylistsData.qml). engine is the one read-only
    // exception, needed to recognize the playlist currently loaded into the
    // queue so it can be excluded from selection — see UC-22.
    PlaylistsData {
        id: playlistsData
        playlistManager: playlistManager
        libraryModel:    libraryModel
        engine:          engine
    }

    // Windows OS master volume control — see systemvolumecontroller.h.
    SystemVolumeController { id: systemVolume }

    // MISC tab's "Cleanup Incompatible Milkdrop Presets" feature — see
    // UC-25. Instantiated here (not locally inside MilkdropCleanupDialog)
    // so the onClosing veto above has direct visibility into `cleaning`.
    MilkdropCleanupController { id: milkdropCleanupController; appConfig: appConfig }

    // Backup/Restore Topaz Environment (MISC tab) — see UC-27. Purely
    // synchronous (small config/playlist/rating files only) — no worker
    // thread, unlike PlaylistExportController.
    BackupRestoreController { id: backupRestoreController
                               playlistManager: playlistManager
                               appConfig: appConfig }

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
        id:                setupDialog
        appConfig:         appConfig
        libraryModel:      libraryModel
        playbackEngine:    engine
        cleanupController: milkdropCleanupController
        backupRestoreController: backupRestoreController
    }

    // About Topaz dialog — opened by TopBar's rightmost (info) icon
    AboutDialog {
        id: aboutDialog
        libraryModel: libraryModel
    }

    // New-playlist dialog — opened by NowPlaying's + NEW button
    NewPlaylistDialog {
        id:              newPlaylistDialog
        playlistManager: playlistManager
        engine:          engine
        // Keeps the PLAYLISTS tab's list live even while it's already the
        // active tab — PlaylistsPanel otherwise only refreshes when the
        // Loader (re)creates it on tab switch (see UC-22).
        onPlaylistCreated: playlistsData.refreshPlaylists()
    }

    // Export-playlist controller/dialog — opened by NowPlaying's EXPORT
    // button. See UC-26 in the architecture doc.
    PlaylistExportController { id: exportController }
    ExportPlaylistDialog {
        id:               exportPlaylistDialog
        exportController: exportController
    }

    // Missing-playlist-tracks notice — opened after a LOAD (NowPlaying or
    // PlaylistViewer) finds tracks whose file no longer exists. See UC-10/UC-22.
    MissingTracksDialog {
        id: missingTracksDialog
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

    // Components loaded into the SplitView's first two slots, switched by
    // root.activeTab (see the two Loaders below). Deliberately no property
    // bindings declared inside these Component blocks -- LibraryTree/
    // AlbumBrowser/SearchResultBrowser/PlaylistsPanel/PlaylistViewer each
    // declare their own "lib"/"engine"/"autoPlay"/"playlistsData" property,
    // so a declarative "lib: lib" etc. here would resolve against the
    // object's own just-declared property instead of walking out to this
    // file's ids (same collision already documented above for
    // BigCoverWindow's "engine" binding). Assigned imperatively instead,
    // via onLoaded on each Loader.
    Component { id: libraryTreeComponent; LibraryTree {} }
    Component { id: searchPanelComponent; SearchPanel {} }
    Component { id: playlistsPanelComponent; PlaylistsPanel {} }
    Component { id: albumBrowserComponent; AlbumBrowser {} }
    Component { id: searchResultComponent; SearchResultBrowser {} }
    Component { id: playlistViewerComponent; PlaylistViewer {} }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        TopBar {
            Layout.fillWidth: true
            systemVolume: systemVolume
            activeTab: root.activeTab
            onSettingsRequested: setupDialog.open()
            onAboutRequested:    aboutDialog.open()
            onLibrarySelected:   root.activeTab = "library"
            onPlaylistsSelected: root.activeTab = "playlists"
            onSearchSelected:    root.activeTab = "search"
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

            // Swaps between LibraryTree/SearchPanel/PlaylistsPanel based on
            // root.activeTab. SplitView.* attached properties and the
            // width-persistence debounce live on the Loader itself (the
            // actual SplitView child), not on the loaded item, since
            // attached properties must sit on the direct child. A Loader
            // (rather than keeping all three permanently instantiated with
            // `visible` toggling) avoids heavy virtualized trees coexisting
            // and sidesteps relying on undocumented SplitView behavior for
            // invisible children -- the accepted tradeoff is that
            // LibraryTree's local transient state (expanded artists, scroll
            // position) resets when the user leaves and returns to LIBRARY;
            // actual selection state lives in `lib`, unaffected. SearchData/
            // PlaylistsData likewise live outside this Loader, so leaving
            // and returning to SEARCH/PLAYLISTS preserves the last query/
            // mode/results or selected playlist and scroll position.
            Loader {
                id: libraryTreePanel
                SplitView.preferredWidth: appConfig.libraryTreeWidth
                SplitView.minimumWidth:   160
                onWidthChanged: saveLayoutTimer.restart()
                sourceComponent: root.activeTab === "search"    ? searchPanelComponent
                                : root.activeTab === "playlists" ? playlistsPanelComponent
                                :                                  libraryTreeComponent
                onLoaded: {
                    if (!item) return
                    if (root.activeTab === "search")         item.searchData    = search
                    else if (root.activeTab === "playlists") item.playlistsData = playlistsData
                    else                                      item.lib          = lib
                }
            }

            Loader {
                SplitView.fillWidth: true
                SplitView.minimumWidth: 400
                sourceComponent: root.activeTab === "search"    ? searchResultComponent
                                : root.activeTab === "playlists" ? playlistViewerComponent
                                :                                  albumBrowserComponent
                onLoaded: {
                    if (!item) return
                    item.engine   = engine
                    item.autoPlay = autoPlay
                    if (root.activeTab === "search") {
                        item.searchData = search
                    } else if (root.activeTab === "playlists") {
                        item.playlistsData = playlistsData
                        item.missingPlaylistTracks.connect(function(missing) {
                            missingTracksDialog.missingTracks = missing
                            missingTracksDialog.open()
                        })
                        item.exportPlaylistRequested.connect(function() {
                            // item.currentRawTracks, not
                            // playlistsData.selectedRawTracks -- the latter
                            // is stale while previewing the playlist active
                            // in the queue (see PlaylistViewer.qml).
                            exportPlaylistDialog.tracks = item.currentRawTracks
                            exportPlaylistDialog.open()
                        })
                    } else {
                        item.lib = lib
                    }
                }
            }

            PlaybackQueue {
                id: playbackQueuePanel
                SplitView.preferredWidth: appConfig.playbackQueueWidth
                SplitView.minimumWidth:   240
                engine: engine
                autoPlay: autoPlay
                appConfig: appConfig
                onWidthChanged: saveLayoutTimer.restart()
            }

            NowPlaying {
                id: nowPlayingPanel
                SplitView.preferredWidth: appConfig.nowPlayingWidth
                SplitView.minimumWidth:   280
                engine:          engine
                playlistManager: playlistManager
                autoPlay:        autoPlay
                appConfig:       appConfig
                onWidthChanged: saveLayoutTimer.restart()
                onNewPlaylistRequested: newPlaylistDialog.open()
                onExportPlaylistRequested: {
                    exportPlaylistDialog.tracks = engine.trackList()
                    exportPlaylistDialog.open()
                }
                onBigCoverRequested: root.bigCoverPaneOpen = true
                onMissingPlaylistTracks: (missing) => {
                    missingTracksDialog.missingTracks = missing
                    missingTracksDialog.open()
                }
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
