import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: root
    minimumWidth:  1280
    minimumHeight:  720
    title: qsTr("Topaz")
    color: Theme.surface

    // Deliberately hidden for now, and no width/height bindings: a QML Window
    // is created and shown in its own componentComplete(), which runs BEFORE
    // Component.onCompleted. Restoring the saved screen/position/size from
    // there was therefore too late -- the native window already existed on the
    // primary display, Window.screen assigned after creation moves nothing, and
    // a position for a display with a different scale factor was converted with
    // the primary's (wrong position and size after reopening on the additional
    // display). The restore in Component.onCompleted below now runs first and
    // then shows the window by assigning `visibility`, the same idea as the
    // detachable panes (FloatingPane.qml), which start hidden and show
    // themselves once positioned.
    //
    // Hidden via `visibility`, NOT `visible: false`: declaring both `visible`
    // and (later) assigning `visibility` makes Qt log "Conflicting properties
    // 'visible' and 'visibility'" and the window came up minimized.
    //
    // Startup fullscreen/windowed is a user preference (Setup > MISC, takes
    // effect on the next launch -- UC-28), not resolution-driven.
    visibility: Window.Hidden

    // True once the startup geometry has settled (see settleTimer below) --
    // until then saveLayoutTimer must not persist anything, so transient
    // startup geometry (DPI re-scale, layout squeeze) never overwrites what
    // the user configured.
    property bool layoutSettled: false

    // Windowed and full-screen mode each keep their own panel widths
    // (AppConfig libraryTreeWidth/... vs. fullscreenLibraryTreeWidth/...).
    // layoutFullscreen = the mode whose widths are currently applied; only a
    // real windowed <-> full-screen flip switches the set (Hidden/Minimized/
    // Maximized don't count), which also covers the start-up show.
    property bool layoutFullscreen: false
    onVisibilityChanged: {
        // TopBar's Minimize button from full screen (see minimizeWindow()).
        // showMinimized() replaces the window state: Qt first LEAVES full
        // screen (restoring the frame) and only then minimizes, which reports
        // a transient Windowed in between. Reacting to that transient (as the
        // first version did, by re-entering FullScreen mid-minimize) left the
        // restored window without its frame. So: ignore everything until the
        // window really is Minimized, and only then arm the restore.
        if (root.minimizeFromFullscreenPending) {
            if (root.visibility === Window.Minimized) {
                root.minimizeFromFullscreenPending = false
                minimizePendingTimer.stop()
                root.restoreFullscreenAfterMinimize = true
            }
            return
        }
        if (root.visibility === Window.Hidden || root.visibility === Window.Minimized)
            return
        // Restored after that minimize: a taskbar restore comes back Windowed --
        // go back to full screen. Deferred a tick so it doesn't run inside Qt's
        // own restore handling, and returns before the panel-width switch below
        // would swap to the windowed set.
        if (root.restoreFullscreenAfterMinimize) {
            root.restoreFullscreenAfterMinimize = false
            if (root.visibility !== Window.FullScreen) {
                Qt.callLater(function() { root.visibility = Window.FullScreen })
                return
            }
        }
        const full = (root.visibility === Window.FullScreen)
        if (full === root.layoutFullscreen) return
        root.layoutFullscreen = full
        root.applyPanelWidths(full)
    }

    // Assigned imperatively: a splitter drag writes SplitView.preferredWidth
    // itself, so the declarative bindings below stop tracking appConfig after
    // the first drag. A full-screen width of 0 (never set) keeps the current
    // width -- the first full-screen use behaves exactly as before.
    // Also applies the mode's heights of the free areas above/below the queue
    // that hold a docked pane (applyDockHeights(), UC-38).
    function applyPanelWidths(full) {
        const lib   = full ? appConfig.fullscreenLibraryTreeWidth   : appConfig.libraryTreeWidth
        const queue = full ? appConfig.fullscreenPlaybackQueueWidth : appConfig.playbackQueueWidth
        const np    = full ? appConfig.fullscreenNowPlayingWidth    : appConfig.nowPlayingWidth
        if (lib   > 0) libraryTreePanel.SplitView.preferredWidth   = lib
        if (queue > 0) queueColumn.SplitView.preferredWidth        = queue
        if (np    > 0) nowPlayingColumn.SplitView.preferredWidth   = np

        root.applyDockHeights(full)
    }

    // The stored height of a docked pane for one mode (-1 = not set yet).
    function savedDockHeight(id, full) {
        const h = appConfig.dockPaneHeights[id]
        if (!h) return -1
        return full ? h.fullscreen : h.window
    }

    // Gives each docked pane's slot the mode's stored height (if it fits the
    // pane's minimum; else keeps the current height if that does, else the
    // pane's default). Free areas keep their current size during a session --
    // they only start collapsed (see the free areas' preferredHeight).
    function applyDockHeights(full) {
        for (let z = 0; z < root.dockZoneKeys.length; z++) {
            const zone  = root.dockZoneKeys[z]
            const list  = root.dockZones[zone]
            const slots = root.zoneSlots(zone)
            for (let i = 0; i < list.length; i++) {
                const entry = root.dockablePanes[list[i]]
                const saved = root.savedDockHeight(list[i], full)
                if (saved >= entry.minDockHeight)
                    slots[i].SplitView.preferredHeight = saved
                else if (slots[i].SplitView.preferredHeight < entry.minDockHeight)
                    slots[i].SplitView.preferredHeight = entry.defaultDockHeight
            }
        }
    }

    // F11 and TopBar's fullscreen/window button toggle between fullscreen and windowed.
    function toggleFullscreen() {
        root.visibility = (root.visibility === Window.FullScreen)
                          ? Window.Windowed : Window.FullScreen
    }
    Shortcut {
        sequence: "F11"
        onActivated: root.toggleFullscreen()
    }

    // TopBar's Minimize button (full screen only); see onVisibilityChanged.
    property bool minimizeFromFullscreenPending: false   // showMinimized() in progress
    property bool restoreFullscreenAfterMinimize: false  // minimized; re-enter FullScreen on restore
    function minimizeWindow() {
        root.restoreFullscreenAfterMinimize = false
        root.minimizeFromFullscreenPending = (root.visibility === Window.FullScreen)
        if (root.minimizeFromFullscreenPending) minimizePendingTimer.restart()
        root.showMinimized()
    }
    // Safety net: if the window never reports Minimized (shouldn't happen),
    // don't leave onVisibilityChanged ignoring every later change.
    Timer {
        id: minimizePendingTimer
        interval: 2000
        onTriggered: root.minimizeFromFullscreenPending = false
    }

    // While fullscreen (F11 or "Start Topaz in Full Screen") the mouse cursor
    // hides after 5 s without mouse activity and comes back as soon as the
    // mouse is used, so it doesn't sit over the artwork on a kiosk display.
    // Off (and the cursor restored at once) when leaving fullscreen. See
    // cursorautohider.h.
    CursorAutoHider {
        id: cursorAutoHider
        enabled: root.visibility === Window.FullScreen
        idleSeconds: 5
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

    // Fraction (0..1) of rect (x, y, w, h), in virtual-desktop coordinates, that
    // lies on the currently connected screens. A saved position only counts as
    // usable when at least half of it is visible (see restorePaneGeometry() and
    // the main window's restore): a monitor may have been unplugged or
    // rearranged since it was last saved, and an "overlaps at all" test restored
    // a window saved on an unplugged left display as a barely reachable sliver
    // on the remaining one.
    function visibleFraction(x, y, w, h) {
        if (w <= 0 || h <= 0) return 0
        // qmllint disable missing-property
        const screens = Qt.application.screens
        // qmllint enable missing-property
        let area = 0
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i]
            const ox = Math.max(0, Math.min(x + w, s.virtualX + s.width)  - Math.max(x, s.virtualX))
            const oy = Math.max(0, Math.min(y + h, s.virtualY + s.height) - Math.max(y, s.virtualY))
            area += ox * oy
        }
        return area / (w * h)
    }

    // Restores a detachable pane's saved geometry (or its centered default) onto
    // `win` while it is still hidden. The saved size is clamped to the screen the
    // pane lands on (never below its minimum; scaled uniformly for an
    // aspect-locked pane so it stays square), and a saved spot that is less than
    // half visible on the connected screens is treated as unusable (monitor
    // unplugged or rearranged) and falls back to the default, centered on the
    // primary display.
    function restorePaneGeometry(win, configured, sx, sy, sw, sh, defaultW, defaultH) {
        // qmllint disable missing-property
        const screens = Qt.application.screens
        // qmllint enable missing-property
        if (configured && sw > 0 && sh > 0 && screens.length > 0) {
            const scr = root.screenAtPoint(sx + sw / 2, sy + sh / 2) || screens[0]
            let w = sw
            let h = sh
            if (win.fixedAspectRatio > 0) {
                const k = Math.min(1, scr.width / sw, scr.height / sh)
                w = sw * k
                h = sh * k
            } else {
                w = Math.min(sw, scr.width)
                h = Math.min(sh, scr.height)
            }
            w = Math.max(win.minPaneWidth,  w)
            h = Math.max(win.minPaneHeight, h)
            if (root.visibleFraction(sx, sy, w, h) >= 0.5) {
                win.width  = w
                win.height = h
                win.x      = sx
                win.y      = sy
                return
            }
        }
        const primary = screens[0]
        win.width  = defaultW
        win.height = defaultH
        win.x = primary.virtualX + (primary.width  - defaultW) / 2
        win.y = primary.virtualY + (primary.height - defaultH) / 2
    }

    // Resolves a saved Screen.name (e.g. from appConfig.windowScreenName) back
    // to a live Screen object among the currently connected monitors — used to
    // restore which monitor the main window (re-)enters Window.FullScreen on
    // at startup. Returns null for an empty/unmatched name (monitor unplugged
    // or renamed since last save), same "fall back to platform default"
    // philosophy as visibleFraction above.
    function screenByName(name) {
        if (!name) return null
        // qmllint disable missing-property
        const screens = Qt.application.screens
        // qmllint enable missing-property
        for (let i = 0; i < screens.length; i++) {
            if (screens[i].name === name) return screens[i]
        }
        return null
    }

    // The connected screen containing the point (px, py) in the same logical
    // virtual-desktop coordinates visibleFraction() uses, or null.
    // Unlike screenByName() this survives identical monitor models (same
    // name), renamed connectors and changed arrangements.
    function screenAtPoint(px, py) {
        // qmllint disable missing-property
        const screens = Qt.application.screens
        // qmllint enable missing-property
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i]
            if (px >= s.virtualX && px < s.virtualX + s.width &&
                py >= s.virtualY && py < s.virtualY + s.height)
                return s
        }
        return null
    }

    // Geometry the startup restore wants, kept for settleTimer's self-check.
    property bool   haveWanted:     false
    property real   wantedX:        0
    property real   wantedY:        0
    property real   wantedWidth:    0
    property real   wantedHeight:   0
    property string wantedScreenName: ""
    property bool   wantedFullscreen: false
    property bool   selfCheckDone:  false

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

            // Kiosk: only while Topaz itself is fullscreen may panes cover the
            // OS taskbar (topmost) -- see FloatingPane.qml.
            kiosk: root.visibility === Window.FullScreen

            Component.onCompleted: {
                root.restorePaneGeometry(bigCoverWindow, appConfig.bigCoverPaneConfigured,
                                         appConfig.bigCoverPaneX, appConfig.bigCoverPaneY,
                                         appConfig.bigCoverPaneWidth, appConfig.bigCoverPaneHeight,
                                         400, 400)
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

            kiosk: root.visibility === Window.FullScreen

            Component.onCompleted: {
                root.restorePaneGeometry(tagInfoWindow, appConfig.tagInfoPaneConfigured,
                                         appConfig.tagInfoPaneX, appConfig.tagInfoPaneY,
                                         appConfig.tagInfoPaneWidth, appConfig.tagInfoPaneHeight,
                                         500, 230)
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
        // Floating only while not docked (UC-38, see "Docking panes" below)
        active: root.audioVisualizerPaneOpen && !root.isDocked("audioVisualizer")
        onLoaded: {
            if (item) {
                item.engine           = engine
                item.visualizer       = audioVisualizer
                item.visualizerConfig = appConfig
            }
        }

        sourceComponent: AudioVisualizerWindow {
            id: audioVisualizerWindow

            kiosk: root.visibility === Window.FullScreen

            Component.onCompleted: {
                root.restorePaneGeometry(audioVisualizerWindow, appConfig.audioVisualizerPaneConfigured,
                                         appConfig.audioVisualizerPaneX, appConfig.audioVisualizerPaneY,
                                         appConfig.audioVisualizerPaneWidth, appConfig.audioVisualizerPaneHeight,
                                         500, 260)
                visible = true
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveAudioVisualizerPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.closePane("audioVisualizer")
            dockZones: root.availableZones("audioVisualizer")
            onDockRequested: (zone) => root.dockPane("audioVisualizer", zone)
        }
    }

    // ── Detachable "audio meter" pane ─────────────────────────────────────
    // Opened by toggling the "AUDIO METER" button in BottomBar; see
    // AudioMeterWindow.qml / AudioMeterView.qml and AudioMeterController
    // (UC-37). Same wiring as audioVisualizerLoader above.
    property bool audioMeterPaneOpen: false

    Loader {
        id: audioMeterLoader
        active: root.audioMeterPaneOpen && !root.isDocked("audioMeter")
        onLoaded: {
            if (item) {
                item.meter       = audioMeter
                item.meterConfig = appConfig
            }
        }

        sourceComponent: AudioMeterWindow {
            id: audioMeterWindow

            kiosk: root.visibility === Window.FullScreen

            Component.onCompleted: {
                root.restorePaneGeometry(audioMeterWindow, appConfig.audioMeterPaneConfigured,
                                         appConfig.audioMeterPaneX, appConfig.audioMeterPaneY,
                                         appConfig.audioMeterPaneWidth, appConfig.audioMeterPaneHeight,
                                         520, 150)
                visible = true
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveAudioMeterPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.closePane("audioMeter")
            dockZones: root.availableZones("audioMeter")
            onDockRequested: (zone) => root.dockPane("audioMeter", zone)
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
        active: root.milkdropPaneOpen && !root.isDocked("milkdrop")
        onLoaded: {
            if (item) {
                item.engine         = engine
                item.milkdropConfig = appConfig
            }
        }

        sourceComponent: MilkdropWindow {
            id: milkdropWindow

            kiosk: root.visibility === Window.FullScreen

            Component.onCompleted: {
                root.restorePaneGeometry(milkdropWindow, appConfig.milkdropPaneConfigured,
                                         appConfig.milkdropPaneX, appConfig.milkdropPaneY,
                                         appConfig.milkdropPaneWidth, appConfig.milkdropPaneHeight,
                                         560, 360)
                visible = true
                raise()
                requestActivate()
            }

            onGeometrySettled: (x, y, width, height, screenName) =>
                appConfig.saveMilkdropPaneGeometry(x, y, width, height, screenName)
            onCloseRequested: root.closePane("milkdrop")
            dockZones: root.availableZones("milkdrop")
            onDockRequested: (zone) => root.dockPane("milkdrop", zone)
        }
    }

    // ── Docking panes (UC-38) ────────────────────────────────────────────
    // A dockable pane is either floating (its own loader above, a
    // FloatingPane window) or docked into one of four zones: above / below
    // the playback queue (queueColumn, together at most maxQueueDock panes)
    // and above / below Now Playing (nowPlayingColumn, together at most
    // maxNowPlayingDock).
    // Each zone is a stack of static dock slots (QueueDockArea with
    // dockHost/zone/slotIndex, which load the pane's content view from this
    // registry) plus one free area. Never both floating and docked: each
    // floating loader is active only while its pane is open AND not docked,
    // so there is at most one instance (matters for Milkdrop's GL context /
    // projectM).
    //
    // Registry: pane id -> content component + dock heights. The id is also
    // the prefix of the pane's open flag (root.<id>PaneOpen). A future
    // dockable pane = one entry here + a dock component + dock props on its
    // floating loader. `fixed` = always docked: no floating window, can't be
    // closed or floated, only moved to another zone (moveDocked()); docked
    // at startup if the saved zones don't contain it (restoreDockedPanes()).
    Component {
        id: audioMeterDockComponent
        Item {   // same 6 px margin as in AudioMeterWindow
            AudioMeterView { anchors.fill: parent; anchors.margins: 6; meter: audioMeter; meterConfig: appConfig }
        }
    }
    Component {
        id: audioVisualizerDockComponent
        AudioVisualizerView { playback: engine; visualizer: audioVisualizer; visualizerConfig: appConfig
                              drawsOwnBackground: true }
    }
    Component {
        id: milkdropDockComponent
        MilkdropPaneView { playback: engine; milkdropConfig: appConfig }
    }
    // NEW / LOAD / EXPORT / REMOVE. The LOAD dialog chain stays in NowPlaying
    // (always alive -- this view is recreated on every swap / move).
    Component {
        id: playlistButtonsDockComponent
        PlaylistButtonsView {
            playback: engine
            autoPlayController: autoPlay
            onNewRequested:    newPlaylistDialog.open()
            onLoadRequested:   nowPlayingPanel.openLoadPlaylist()
            onExportRequested: root.openExportPlaylist()
            onRemoveRequested: {
                if (autoPlay) autoPlay.clearQueueAndHistory()
                else engine.clearQueue()
            }
        }
    }
    readonly property var dockablePanes: ({
        audioMeter:      { component: audioMeterDockComponent,      minDockHeight: 90,  defaultDockHeight: 140 },
        audioVisualizer: { component: audioVisualizerDockComponent, minDockHeight: 120, defaultDockHeight: 200 },
        milkdrop:        { component: milkdropDockComponent,        minDockHeight: 160, defaultDockHeight: 260 },
        playlistButtons: { component: playlistButtonsDockComponent, minDockHeight: 118, defaultDockHeight: 132,
                           fixed: true, home: "nowPlayingBottom" }
    })
    // The playlist buttons pane is always open (fixed, see the registry).
    property bool playlistButtonsPaneOpen: true

    function openExportPlaylist() {
        exportPlaylistDialog.tracks = engine.trackList()
        exportPlaylistDialog.playlistName = engine.activePlaylistName
        exportPlaylistDialog.open()
    }

    readonly property var dockZoneKeys: ["queueTop", "queueBottom", "nowPlayingTop", "nowPlayingBottom"]
    readonly property int maxQueueDock:      4   // above + below the queue together
    readonly property int maxNowPlayingDock: 3   // above + below Now Playing (incl. the playlist buttons)
    // The hosts' own minimum heights (PlaybackQueue / NowPlaying below), used
    // by the "does one more pane fit?" check.
    readonly property int queueMinHeight:      200
    readonly property int nowPlayingMinHeight: 300
    readonly property int dockHandleSize:      5     // the columns' SplitView handles

    // The docked panes per zone, each list running from the host (queue /
    // Now Playing) OUTWARDS: queueTop[0] / nowPlayingTop[0] sit directly above
    // their host, queueBottom[0] / nowPlayingBottom[0] directly below it. A
    // new pane is appended (= the outer edge), so the panes already docked
    // keep their slot and aren't reloaded. A pane counts as docked only while
    // open: closing a docked pane removes it. Always replaced as a whole
    // (setZone()), never mutated in place, so every binding on it re-evaluates.
    property var dockZones: ({ queueTop: [], queueBottom: [], nowPlayingTop: [], nowPlayingBottom: [] })
    // Session memory: where a pane was last docked ({ zone, index }), so
    // reopening it from the BottomBar puts it back there (if that zone still
    // has room). Forgotten when the user floats the pane again.
    property var lastDockZone: ({})

    // The docked pane showing the selection outline (clicked last), like a
    // floating pane's: set by QueueDockArea on a left press, cleared after
    // 4 s (selectDockPane() restarts it), when the main window loses focus
    // or when that pane leaves its slot.
    property string selectedDockPane: ""
    function selectDockPane(id) {
        root.selectedDockPane = id
        dockSelectTimer.restart()
    }
    Timer {
        id: dockSelectTimer
        interval: 4000
        onTriggered: root.selectedDockPane = ""
    }

    function zoneSlots(zone) {
        switch (zone) {
        case "queueTop":      return [queueTopSlot0, queueTopSlot1, queueTopSlot2, queueTopSlot3]
        case "queueBottom":   return [queueBottomSlot0, queueBottomSlot1, queueBottomSlot2, queueBottomSlot3]
        case "nowPlayingTop": return [nowPlayingTopSlot0, nowPlayingTopSlot1, nowPlayingTopSlot2]
        default:              return [nowPlayingBottomSlot0, nowPlayingBottomSlot1, nowPlayingBottomSlot2]
        }
    }
    function zoneFree(zone) {
        switch (zone) {
        case "queueTop":      return queueTopFree
        case "queueBottom":   return queueBottomFree
        case "nowPlayingTop": return nowPlayingTopFree
        default:              return nowPlayingBottomFree
        }
    }
    function isNowPlayingZone(zone) { return zone.indexOf("nowPlaying") === 0 }
    // Both zones of `zone`'s column (they share the column's capacity + room).
    function columnZones(zone) {
        return root.isNowPlayingZone(zone) ? ["nowPlayingTop", "nowPlayingBottom"] : ["queueTop", "queueBottom"]
    }
    // Places left in `zone`'s column; `exceptId` (a pane being moved) doesn't count.
    function zoneCapacityLeft(zone, exceptId) {
        const zones = root.columnZones(zone)
        let n = 0
        for (let z = 0; z < zones.length; z++) {
            const list = root.dockZones[zones[z]]
            for (let i = 0; i < list.length; i++) if (list[i] !== exceptId) n++
        }
        return (root.isNowPlayingZone(zone) ? root.maxNowPlayingDock : root.maxQueueDock) - n
    }
    function dockZoneOf(id) {
        for (let z = 0; z < root.dockZoneKeys.length; z++)
            if (root.dockZones[root.dockZoneKeys[z]].indexOf(id) >= 0) return root.dockZoneKeys[z]
        return ""
    }
    function isDocked(id) { return root.dockZoneOf(id) !== "" }

    // Does pane `id` still fit into `zone`'s column? Column height minus the
    // host's minimum, every docked pane's minimum and the handles must leave
    // at least the pane's own minimum -- so on a smaller screen the dock
    // buttons simply disappear before a layout could break.
    // `exceptId` (a pane being moved within the column) is left out.
    function columnRoomFor(id, zone, exceptId) {
        const entry  = root.dockablePanes[id]
        const np     = root.isNowPlayingZone(zone)
        const column = np ? nowPlayingColumn : queueColumn
        const zones  = root.columnZones(zone)
        let used    = np ? root.nowPlayingMinHeight : root.queueMinHeight
        let handles = 2                                   // the host's + the new pane's
        for (let z = 0; z < zones.length; z++) {
            const list = root.dockZones[zones[z]]
            for (let i = 0; i < list.length; i++) {
                if (list[i] === exceptId) continue
                used += root.dockablePanes[list[i]].minDockHeight
                handles++
            }
        }
        return column.height - used - handles * root.dockHandleSize >= entry.minDockHeight
    }
    function canDock(id, zone) {
        return root.dockablePanes[id] !== undefined && !root.isDocked(id)
               && root.zoneCapacityLeft(zone) > 0 && root.columnRoomFor(id, zone)
    }
    // The zones a floating pane offers dock buttons for right now.
    function availableZones(id) {
        return root.dockZoneKeys.filter(z => root.canDock(id, z))
    }
    // Can docked pane `id` move to another zone (the fixed panes' move buttons)?
    function canMoveTo(id, zone) {
        const current = root.dockZoneOf(id)
        if (current === "" || current === zone) return false
        return root.zoneCapacityLeft(zone, id) > 0 && root.columnRoomFor(id, zone, id)
    }

    // Height a new pane may take in `zone`'s column without pushing the host
    // below its minimum (the free areas and the other slots keep theirs).
    function spareHeight(zone) {
        const np     = root.isNowPlayingZone(zone)
        const column = np ? nowPlayingColumn : queueColumn
        const zones  = root.columnZones(zone)
        let used    = np ? root.nowPlayingMinHeight : root.queueMinHeight
        let handles = 2
        for (let z = 0; z < zones.length; z++) {
            const free = root.zoneFree(zones[z])
            if (free.SplitView.preferredHeight > 0) { used += free.SplitView.preferredHeight; handles++ }
            const list  = root.dockZones[zones[z]]
            const slots = root.zoneSlots(zones[z])
            for (let i = 0; i < list.length; i++) {
                used += slots[i].SplitView.preferredHeight
                handles++
            }
        }
        return column.height - used - handles * root.dockHandleSize
    }

    // id -> current height of every pane docked in `zone` (read from the
    // slots, before the zone changes, so heights travel with their panes).
    function zoneHeights(zone) {
        const out   = {}
        const list  = root.dockZones[zone]
        const slots = root.zoneSlots(zone)
        for (let i = 0; i < list.length; i++) out[list[i]] = slots[i].SplitView.preferredHeight
        return out
    }
    // Replace `zone`'s list and give each slot the height of the pane it now holds.
    function setZone(zone, list, heights) {
        const zones = Object.assign({}, root.dockZones)
        zones[zone] = list
        root.dockZones = zones
        const slots = root.zoneSlots(zone)
        for (let i = 0; i < list.length; i++) slots[i].SplitView.preferredHeight = heights[list[i]]
    }

    // Dock pane `id` into `zone` (at `index` from the host outwards, default:
    // the outer edge) and open it there. The zone is set BEFORE the open flag,
    // so the floating loader never starts. Height: the zone's FREE SPACE if it
    // is open and big enough (it is taken over and collapses, as before),
    // else the mode's saved height, else the pane's default -- limited to what
    // the column can spare unless `restoring` (startup: the column isn't laid
    // out yet; applyDockHeights() follows). `height` (moveDocked()) replaces
    // the saved height. A fixed pane being restored skips the capacity check
    // (it must always be somewhere) -- the zone's slot count still applies.
    function dockPane(id, zone, index, restoring, height) {
        const entry = root.dockablePanes[id]
        if (!entry || root.isDocked(id)) return
        if (root.dockZones[zone].length >= root.zoneSlots(zone).length) return
        if (!(restoring && entry.fixed) && root.zoneCapacityLeft(zone) <= 0) return
        const heights = root.zoneHeights(zone)
        const list = root.dockZones[zone].slice()
        const pos = (index === undefined || index < 0 || index > list.length) ? list.length : index
        list.splice(pos, 0, id)

        const free = root.zoneFree(zone)
        let h
        if (free.SplitView.preferredHeight >= entry.minDockHeight) {
            h = free.SplitView.preferredHeight
            free.SplitView.preferredHeight = 0
        } else {
            const saved = height !== undefined ? height : root.savedDockHeight(id, root.layoutFullscreen)
            h = saved >= entry.minDockHeight ? saved : entry.defaultDockHeight
            if (!restoring)
                h = Math.max(entry.minDockHeight, Math.min(h, root.spareHeight(zone)))
        }
        heights[id] = h
        root.lastDockZone[id] = { zone: zone, index: pos }
        root.setZone(zone, list, heights)
        root[id + "PaneOpen"] = true
    }

    // Take pane `id` out of its zone; its height goes to the zone's free area,
    // so the layout doesn't jump (FREE SPACE stays where the pane was, as
    // before). Returns the index it had, or -1. `toHost` (moveDocked()): the
    // host takes the space instead, so the pane can take it back elsewhere.
    function removeDocked(id, toHost) {
        const zone = root.dockZoneOf(id)
        if (zone === "") return -1
        const heights = root.zoneHeights(zone)
        const list = root.dockZones[zone].slice()
        const pos = list.indexOf(id)
        list.splice(pos, 1)
        if (!toHost) {
            const free = root.zoneFree(zone)
            // + the slot's own handle, which disappears with it
            free.SplitView.preferredHeight += heights[id] + root.dockHandleSize
        }
        root.setZone(zone, list, heights)
        if (root.selectedDockPane === id) root.selectedDockPane = ""
        return pos
    }

    // Move docked pane `id` to the outer edge of another zone, keeping its
    // height (the move buttons of fixed panes).
    function moveDocked(id, zone) {
        if (!root.canMoveTo(id, zone)) return
        const h = root.zoneHeights(root.dockZoneOf(id))[id]
        root.removeDocked(id, true)
        root.dockPane(id, zone, -1, false, h)
    }

    // Float a docked pane again: removing it from its zone makes the floating
    // loader start (the open flag stays true). Not for fixed panes.
    function undockPane(id) {
        if (root.dockablePanes[id] && root.dockablePanes[id].fixed) return
        delete root.lastDockZone[id]
        root.removeDocked(id)
    }

    // Close a pane wherever it is. The open flag goes false BEFORE it leaves
    // its zone, so a docked pane doesn't flash up as a floating window.
    // lastDockZone remembers where it was. Fixed panes can't be closed.
    function closePane(id) {
        if (root.dockablePanes[id] && root.dockablePanes[id].fixed) return
        root[id + "PaneOpen"] = false
        const zone = root.dockZoneOf(id)
        const pos  = root.removeDocked(id)
        if (pos >= 0) root.lastDockZone[id] = { zone: zone, index: pos }
    }

    // ▲/▼ on a docked pane: swap it with its neighbour in the same zone.
    // `dir` is on screen (-1 = up); the zones above a host run upwards.
    function swapDocked(id, dir) {
        const zone = root.dockZoneOf(id)
        if (zone === "") return
        const step = zone.endsWith("Top") ? -dir : dir
        const list = root.dockZones[zone].slice()
        const i = list.indexOf(id)
        const j = i + step
        if (j < 0 || j >= list.length) return
        const heights = root.zoneHeights(zone)
        list[i] = list[j]
        list[j] = id
        root.setZone(zone, list, heights)
    }

    // Persistence: a pane is listed exactly while it is docked and open
    // (closePane() removes it), so the config always holds what a restart
    // should bring back.
    // Only after restoreDockedPanes() ran: a change before it (the property's
    // own initial value) would otherwise overwrite the saved zones with empty
    // ones before they were read.
    property bool dockZonesRestored: false
    onDockZonesChanged: if (root.dockZonesRestored) appConfig.saveDockZones(root.dockZones)

    // Startup (Component.onCompleted, window still hidden): reopen the panes
    // that were docked at the last exit, in their zones and order. Unknown
    // ids (a pane removed in a later version) and duplicates are ignored.
    function restoreDockedPanes() {
        const saved = appConfig.dockZones
        for (let z = 0; z < root.dockZoneKeys.length; z++) {
            const zone = root.dockZoneKeys[z]
            const ids  = saved[zone] || []
            for (let i = 0; i < ids.length; i++)
                if (root.dockablePanes[ids[i]]) root.dockPane(ids[i], zone, -1, true)
        }
        // Fixed panes are always docked: at their home position (index 0 =
        // next to the host) if the saved zones didn't have them, else in the
        // first zone with a free slot.
        const ids = Object.keys(root.dockablePanes)
        for (let p = 0; p < ids.length; p++) {
            const entry = root.dockablePanes[ids[p]]
            if (!entry.fixed || root.isDocked(ids[p])) continue
            const order = [entry.home].concat(root.dockZoneKeys)
            for (let z = 0; z < order.length && !root.isDocked(ids[p]); z++)
                root.dockPane(ids[p], order[z], 0, true)
        }
        root.dockZonesRestored = true
        appConfig.saveDockZones(root.dockZones)   // drops ids that weren't restored
    }

    // BottomBar button: close if open; otherwise reopen where it was last
    // docked if that zone still has room, else as a floating window.
    function togglePane(id) {
        if (root[id + "PaneOpen"]) {
            root.closePane(id)
            return
        }
        const last = root.lastDockZone[id]
        if (last && root.canDock(id, last.zone))
            root.dockPane(id, last.zone, last.index)
        else
            root[id + "PaneOpen"] = true
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

    // A rating just stored by NowPlaying (a star click or a rating deletion)
    // reaches the library's own tracks right away, so ratingCount and the AUTO
    // PLAY candidate pool -- and with them the AUTO PLAY button's "Consider
    // Rating" gate -- don't have to wait for the next scan. Wired here, in the
    // composition root, so PlaybackEngine and LibraryModel stay unaware of each
    // other. See LibraryModel::applyRating() / UC-14.
    Connections {
        target: engine
        function onRatingStored(ratingId, rating) { libraryModel.applyRating(ratingId, rating) }
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

    // Audio Meter level analysis (UC-37): BASS levels when BASS plays,
    // otherwise Topaz's own PCM analysis. Idle unless a meter view exists.
    AudioMeterController {
        id: audioMeter
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
        genreScanController: genreScanController
        audioVisualizer:   audioVisualizer
    }

    // Genre discovery for Setup -> GENRES -> SCAN FOLDERS (UC-36). Owns its
    // own worker thread, independent of the library scanner's.
    GenreScanController { id: genreScanController }

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
        // UC-26 Replay Gain Normalization -- see ExportPlaylistDialog.qml's
        // property doc comments. Both are real declared properties there
        // (qmllint --ignore-settings reports 0), but the editor's qmlls
        // flags them anyway -- see CLAUDE.md's "Editor diagnostics" note.
        // qmllint disable missing-property
        bassAudioActive:  engine.activeBackendName === "BASS Audio Library"
        appConfig:        appConfig
        // qmllint enable missing-property
    }

    // Missing-playlist-tracks notice — opened after a LOAD (NowPlaying or
    // PlaylistViewer) finds tracks whose file no longer exists. See UC-10/UC-22.
    MissingTracksDialog {
        id: missingTracksDialog
    }

    // Visual Folder Scanning (Setup > MISC, opt-in) — opens/closes itself by
    // watching libraryModel.scanning; nothing else ever calls .open() on it.
    // Both are real declared properties on ScanFoldersDialog.qml (qmllint
    // --ignore-settings reports 0), but the editor's qmlls flags them
    // anyway -- see CLAUDE.md's "Editor diagnostics" note.
    // qmllint disable missing-property
    ScanFoldersDialog {
        libraryModel: libraryModel
        appConfig:    appConfig
    }
    // qmllint enable missing-property

    // Restore the main window's screen, size and position (see
    // AppConfig.windowX/Y/windowScreenName/windowWidth/windowHeight), THEN show
    // it -- the window is still hidden here (see `visible: false` at the top),
    // so the native window is created on the right screen with the right
    // geometry. Then kick off the cache load + background stat-check.
    //
    // Target screen: a fullscreen start goes by the saved screen name (the
    // monitor it was fullscreen on), a windowed start by the screen the saved
    // rect lies on; each falls back to the other. That way identical monitor
    // models (same name), renamed connectors or a changed arrangement don't
    // silently pick the primary display.
    //
    // try/finally: the window must ALWAYS end up shown, even if restoring
    // throws -- an invisible app is the one outcome that can't be tolerated.
    Component.onCompleted: {
        const wantFullscreen = appConfig.startFullscreen
        let w = appConfig.windowWidth
        let h = appConfig.windowHeight
        let target = null
        let haveXY = false
        let px = 0
        let py = 0

        try {
            if (appConfig.windowPositionConfigured) {
                const byName = root.screenByName(appConfig.windowScreenName)
                const byRect = root.screenAtPoint(appConfig.windowX + w / 2, appConfig.windowY + h / 2)
                target = wantFullscreen ? (byName || byRect) : (byRect || byName)
            }

            // A saved size may no longer fit the monitor that's actually
            // connected (e.g. last used on a 4K display, only a 1080p one
            // remains) -- clamp down to the screen the window will be on, or
            // the primary screen if the saved monitor is gone entirely. Never
            // below the minimum window size.
            // qmllint disable missing-property
            const clampScreen = target || Qt.application.screens[0]
            // qmllint enable missing-property
            if (clampScreen) {
                w = Math.max(root.minimumWidth,  Math.min(w, clampScreen.width))
                h = Math.max(root.minimumHeight, Math.min(h, clampScreen.height))
            }

            if (appConfig.windowPositionConfigured) {
                if (root.visibleFraction(appConfig.windowX, appConfig.windowY, w, h) >= 0.5) {
                    px = appConfig.windowX
                    py = appConfig.windowY
                    haveXY = true
                } else if (target) {
                    // The saved spot is off every connected screen but the
                    // screen itself is known: center on it. (If the saved
                    // monitor is gone, the platform default position stands.)
                    px = target.virtualX + (target.width  - w) / 2
                    py = target.virtualY + (target.height - h) / 2
                    haveXY = true
                }
            }

            // Screen first (only meaningful before the native window exists),
            // then size, then position -- all still on the hidden window.
            if (target) root.screen = target
            root.width  = w
            root.height = h
            if (haveXY) {
                root.x = px
                root.y = py
            }

            root.wantedX          = px
            root.wantedY          = py
            root.wantedWidth      = w
            root.wantedHeight     = h
            root.haveWanted       = haveXY
            root.wantedScreenName = target ? target.name : ""
            root.wantedFullscreen = wantFullscreen
        } catch (e) {
            console.warn("Main: restoring the window geometry failed, using platform defaults:", e)
        } finally {
            // Panes docked at the last exit come back docked (UC-38). In the
            // windowed set's heights here; a full-screen start re-applies its
            // own set via applyPanelWidths() on the flip below.
            try {
                root.restoreDockedPanes()
            } catch (e2) {
                console.warn("Main: restoring the docked panes failed:", e2)
                root.dockZonesRestored = true   // later changes are saved anyway
            }
            root.visibility = wantFullscreen ? Window.FullScreen : Window.Windowed
            settleTimer.start()
        }

        libraryModel.loadCacheAndStartStatCheck()
    }

    // ~1.2s after the window is shown: the startup geometry has settled. Logs
    // where the window actually ended up versus where the restore wanted it
    // (terminal output, for multi-display/mixed-DPI reports), corrects it once
    // if a windowed start didn't land where it was restored to (the window now
    // lives on the right screen, so a second assignment maps correctly), and
    // only then lets saveLayoutTimer persist anything -- so transient startup
    // geometry (DPI re-scale, SplitView squeeze) can never overwrite what the
    // user configured.
    Timer {
        id: settleTimer
        interval: 1200
        repeat:   false
        onTriggered: {
            const scr = root.screen
            // qmllint disable missing-property
            console.info("Main: window after startup: visibility=" + root.visibility
                         + " screen=" + (scr ? scr.name : "?")
                         + " dpr=" + (scr ? scr.devicePixelRatio : "?")
                         + " pos=" + root.x + "," + root.y
                         + " size=" + root.width + "x" + root.height
                         + " | restored to: " + (root.haveWanted
                              ? (root.wantedX + "," + root.wantedY + " " + root.wantedWidth + "x" + root.wantedHeight)
                              : "(platform default)")
                         + " on screen=" + root.wantedScreenName)
            // qmllint enable missing-property

            if (root.visibility !== Window.FullScreen && root.haveWanted && !root.selfCheckDone) {
                root.selfCheckDone = true
                if (Math.abs(root.x - root.wantedX) > 8 || Math.abs(root.y - root.wantedY) > 8
                    || Math.abs(root.width - root.wantedWidth) > 8
                    || Math.abs(root.height - root.wantedHeight) > 8) {
                    console.info("Main: window is not where it was restored to, re-applying once")
                    root.width  = root.wantedWidth
                    root.height = root.wantedHeight
                    root.x      = root.wantedX
                    root.y      = root.wantedY
                }
            }
            root.layoutSettled = true
        }
    }

    // ── Kiosk: keep the panes above the taskbar ──────────────────────────
    // While Topaz is fullscreen the panes are topmost (FloatingPane.kiosk), but
    // the taskbar is topmost too, and Windows puts it back on top of that band
    // whenever the foreground window changes -- e.g. clicking the fullscreen
    // main window on the other display would cover a pane sitting over the
    // additional display's taskbar again. Each pane re-raises itself (a short
    // burst plus a slow safety timer, see FloatingPane.kioskBurst()); this is
    // the trigger for the main window GAINING keyboard focus -- from a pane or
    // from another application. It keys on activeFocusItem (none -> some), not on
    // `active`: the panes are transient children of this window and `active`
    // stays true on both windows however the focus moves (measured), whereas
    // activeFocusItem follows the real OS focus window.
    property bool mainHadFocus: false
    onActiveFocusItemChanged: {
        const hasFocus = root.activeFocusItem !== null
        if (hasFocus && !root.mainHadFocus && root.visibility === Window.FullScreen) {
            const loaders = [bigCoverLoader, tagInfoLoader, audioVisualizerLoader, audioMeterLoader, milkdropLoader]
            for (let i = 0; i < loaders.length; i++) {
                if (loaders[i].item) loaders[i].item.kioskBurst()
            }
        }
        root.mainHadFocus = hasFocus
        if (!hasFocus) root.selectedDockPane = ""   // the docked panes' outline (UC-38)
    }

    // Persist layout (window size + panel widths + position/monitor) 500 ms
    // after the last resize/move. Window dimensions and position are only
    // saved when not in fullscreen to avoid overwriting the user's windowed
    // geometry with the screen resolution/origin; screenName is always
    // refreshed (meaningful in both modes, and is what fixes fullscreen
    // opening on the wrong monitor on a multi-monitor machine).
    onWidthChanged:  saveLayoutTimer.restart()
    onHeightChanged: saveLayoutTimer.restart()
    onXChanged:      saveLayoutTimer.restart()
    onYChanged:      saveLayoutTimer.restart()
    onScreenChanged: saveLayoutTimer.restart()

    Timer {
        id: saveLayoutTimer
        interval: 500
        repeat:   false
        onTriggered: {
            // Nothing is persisted until the startup geometry has settled --
            // see settleTimer.
            if (!root.layoutSettled) return

            const winW = (root.visibility !== Window.FullScreen)
                         ? root.width  : appConfig.windowWidth
            const winH = (root.visibility !== Window.FullScreen)
                         ? root.height : appConfig.windowHeight
            // Panel widths go into the set of the applied mode (see
            // applyPanelWidths()) -- layoutFullscreen, not visibility, so a
            // full-screen window that gets minimised still saves to its own set.
            appConfig.saveLayout(winW, winH,
                                 libraryTreePanel.width,
                                 queueColumn.width,
                                 nowPlayingColumn.width,
                                 root.layoutFullscreen)
            // Every docked pane's height (UC-38): its slot's preferredHeight
            // (only a handle drag / Main.qml writes it), not its current
            // height -- a window squeezed too small must not overwrite what
            // the user set. Per pane; panes not docked keep their stored
            // heights. Free areas aren't saved (they start collapsed).
            const dockHeights = {}
            for (let z = 0; z < root.dockZoneKeys.length; z++) {
                const list  = root.dockZones[root.dockZoneKeys[z]]
                const slots = root.zoneSlots(root.dockZoneKeys[z])
                for (let i = 0; i < list.length; i++)
                    dockHeights[list[i]] = Math.round(slots[i].SplitView.preferredHeight)
            }
            appConfig.saveDockPaneHeights(dockHeights, root.layoutFullscreen)

            const posX = (root.visibility !== Window.FullScreen) ? root.x : appConfig.windowX
            const posY = (root.visibility !== Window.FullScreen) ? root.y : appConfig.windowY
            // qmllint disable missing-property
            appConfig.saveWindowPosition(posX, posY, root.screen ? root.screen.name : "")
            // qmllint enable missing-property
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
            engine: engine
            activeTab: root.activeTab
            fullscreen: root.visibility === Window.FullScreen
            onSettingsRequested: setupDialog.open()
            onAboutRequested:    aboutDialog.open()
            onFullscreenToggled: root.toggleFullscreen()
            onMinimizeRequested: root.minimizeWindow()
            onCloseRequested:    root.close()   // honours the onClosing veto above
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
                        // The loaded item's type is only known at run time (a Loader over
                        // either the SEARCH or the PLAYLISTS panel), so qmllint can't see
                        // its signals/properties.
                        // qmllint disable missing-property
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
                            exportPlaylistDialog.playlistName = playlistsData.selectedDisplayName
                            exportPlaylistDialog.open()
                            // qmllint enable missing-property
                        })
                    } else {
                        item.lib = lib
                    }
                }
            }

            // Queue column: a vertical SplitView of free area | 4 dock slots |
            // queue | 4 dock slots | free area (UC-38, see "Docking panes"
            // above). The free areas let the queue be made shorter from the
            // top and the bottom and can take a docked pane; a slot is
            // invisible (no handle) unless root.dockZones puts a pane in it.
            // Slot index 0 sits next to the queue (zone lists run outwards).
            // The queue fills the rest, so window height changes go to the
            // queue; the slots and areas keep their size. Width (as before)
            // and the docked panes' heights are persisted per mode -- see
            // applyPanelWidths() / saveLayoutTimer.
            SplitView {
                id: queueColumn
                orientation: Qt.Vertical
                SplitView.preferredWidth: appConfig.playbackQueueWidth
                SplitView.minimumWidth:   240
                onWidthChanged: saveLayoutTimer.restart()

                // Same 5 px handle as the main SplitView's
                handle: Rectangle {
                    implicitWidth:  5
                    implicitHeight: 5
                    color: SplitHandle.pressed ? Theme.secondary
                         : SplitHandle.hovered ? Theme.surfaceContainerHigh
                         :                       Theme.surfaceContainerLow
                }

                // Free areas start collapsed (not persisted); a handle drag
                // opens them. Slots get their heights from dockPane() /
                // setZone() / applyDockHeights().
                QueueDockArea {
                    id: queueTopFree
                    SplitView.preferredHeight: 0
                    freeAllowed: root.zoneCapacityLeft("queueTop") > 0
                }
                QueueDockArea { id: queueTopSlot3; dockHost: root; zone: "queueTop"; slotIndex: 3
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: queueTopSlot2; dockHost: root; zone: "queueTop"; slotIndex: 2
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: queueTopSlot1; dockHost: root; zone: "queueTop"; slotIndex: 1
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: queueTopSlot0; dockHost: root; zone: "queueTop"; slotIndex: 0
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }

                PlaybackQueue {
                    id: playbackQueuePanel
                    SplitView.fillHeight:    true
                    SplitView.minimumHeight: root.queueMinHeight
                    engine: engine
                    autoPlay: autoPlay
                    appConfig: appConfig
                }

                QueueDockArea { id: queueBottomSlot0; dockHost: root; zone: "queueBottom"; slotIndex: 0
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: queueBottomSlot1; dockHost: root; zone: "queueBottom"; slotIndex: 1
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: queueBottomSlot2; dockHost: root; zone: "queueBottom"; slotIndex: 2
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: queueBottomSlot3; dockHost: root; zone: "queueBottom"; slotIndex: 3
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea {
                    id: queueBottomFree
                    SplitView.preferredHeight: 0
                    freeAllowed: root.zoneCapacityLeft("queueBottom") > 0
                }
            }

            // Now Playing column: free area | 3 dock slots | NowPlaying |
            // 3 dock slots | free area, built like queueColumn (UC-38; 3 per
            // zone because one zone may hold all 3 panes the column allows).
            // NowPlaying is a Flickable, so when the docked panes make it
            // shorter its content just scrolls. Width and its minimum live on
            // this column (applyPanelWidths() / saveLayoutTimer), like
            // queueColumn.
            SplitView {
                id: nowPlayingColumn
                orientation: Qt.Vertical
                SplitView.preferredWidth: appConfig.nowPlayingWidth
                SplitView.minimumWidth:   280
                onWidthChanged: saveLayoutTimer.restart()

                handle: Rectangle {
                    implicitWidth:  5
                    implicitHeight: 5
                    color: SplitHandle.pressed ? Theme.secondary
                         : SplitHandle.hovered ? Theme.surfaceContainerHigh
                         :                       Theme.surfaceContainerLow
                }

                QueueDockArea {
                    id: nowPlayingTopFree
                    SplitView.preferredHeight: 0
                    freeAllowed: root.zoneCapacityLeft("nowPlayingTop") > 0
                }
                QueueDockArea { id: nowPlayingTopSlot2; dockHost: root; zone: "nowPlayingTop"; slotIndex: 2
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: nowPlayingTopSlot1; dockHost: root; zone: "nowPlayingTop"; slotIndex: 1
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: nowPlayingTopSlot0; dockHost: root; zone: "nowPlayingTop"; slotIndex: 0
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }

                NowPlaying {
                    id: nowPlayingPanel
                    SplitView.fillHeight:    true
                    SplitView.minimumHeight: root.nowPlayingMinHeight
                    engine:          engine
                    playlistManager: playlistManager
                    autoPlay:        autoPlay
                    appConfig:       appConfig
                    onBigCoverRequested: root.bigCoverPaneOpen = true
                    onMissingPlaylistTracks: (missing) => {
                        missingTracksDialog.missingTracks = missing
                        missingTracksDialog.open()
                    }
                }

                QueueDockArea { id: nowPlayingBottomSlot0; dockHost: root; zone: "nowPlayingBottom"; slotIndex: 0
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: nowPlayingBottomSlot1; dockHost: root; zone: "nowPlayingBottom"; slotIndex: 1
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea { id: nowPlayingBottomSlot2; dockHost: root; zone: "nowPlayingBottom"; slotIndex: 2
                                SplitView.onPreferredHeightChanged: saveLayoutTimer.restart() }
                QueueDockArea {
                    id: nowPlayingBottomFree
                    SplitView.preferredHeight: 0
                    freeAllowed: root.zoneCapacityLeft("nowPlayingBottom") > 0
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
            audioMeterPaneOpen: root.audioMeterPaneOpen
            milkdropPaneOpen: root.milkdropPaneOpen
            onScanRequested: libraryModel.startFullScan()
            onTagInfoToggleRequested: root.tagInfoPaneOpen = !root.tagInfoPaneOpen
            // Dockable panes go through togglePane(): reopening a pane that
            // was docked puts it back in its area (UC-38).
            onAudioVisualizerToggleRequested: root.togglePane("audioVisualizer")
            onAudioMeterToggleRequested: root.togglePane("audioMeter")
            onMilkdropToggleRequested: root.togglePane("milkdrop")
        }
    }
}
