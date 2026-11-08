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
        if (np    > 0) nowPlayingPanel.SplitView.preferredWidth    = np

        root.applyDockHeights(full)
    }

    // The stored height of a free area for one mode (-1 = full screen never set).
    function savedDockHeight(slot, full) {
        return slot === "top"
               ? (full ? appConfig.fullscreenQueueTopDockHeight    : appConfig.queueTopDockHeight)
               : (full ? appConfig.fullscreenQueueBottomDockHeight : appConfig.queueBottomDockHeight)
    }

    // Gives each area holding a docked pane the mode's stored height (if it
    // fits the pane's minimum; else keeps the current height if that does,
    // else the pane's default). Empty areas keep their current size during a
    // session -- they only start collapsed (see the dock areas' preferredHeight).
    function applyDockHeights(full) {
        const slots = ["top", "bottom"]
        for (let i = 0; i < slots.length; i++) {
            const id = slots[i] === "top" ? root.dockTop : root.dockBottom
            if (id === "") continue
            const entry = root.dockablePanes[id]
            const area  = root.dockArea(slots[i])
            const saved = root.savedDockHeight(slots[i], full)
            if (saved >= entry.minDockHeight)
                area.SplitView.preferredHeight = saved
            else if (area.SplitView.preferredHeight < entry.minDockHeight)
                area.SplitView.preferredHeight = entry.defaultDockHeight
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
        active: root.audioVisualizerPaneOpen
                && root.dockTop !== "audioVisualizer" && root.dockBottom !== "audioVisualizer"
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
            dockTopAvailable:    root.dockTop === ""
            dockBottomAvailable: root.dockBottom === ""
            onDockRequested: (slot) => root.dockPane("audioVisualizer", slot)
        }
    }

    // ── Detachable "audio meter" pane ─────────────────────────────────────
    // Opened by toggling the "AUDIO METER" button in BottomBar; see
    // AudioMeterWindow.qml / AudioMeterView.qml and AudioMeterController
    // (UC-37). Same wiring as audioVisualizerLoader above.
    property bool audioMeterPaneOpen: false

    Loader {
        id: audioMeterLoader
        active: root.audioMeterPaneOpen
                && root.dockTop !== "audioMeter" && root.dockBottom !== "audioMeter"
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
            dockTopAvailable:    root.dockTop === ""
            dockBottomAvailable: root.dockBottom === ""
            onDockRequested: (slot) => root.dockPane("audioMeter", slot)
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
                && root.dockTop !== "milkdrop" && root.dockBottom !== "milkdrop"
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
            dockTopAvailable:    root.dockTop === ""
            dockBottomAvailable: root.dockBottom === ""
            onDockRequested: (slot) => root.dockPane("milkdrop", slot)
        }
    }

    // ── Docking panes into the queue column (UC-38) ──────────────────────
    // A dockable pane is either floating (its own loader above, a
    // FloatingPane window) or docked into one of the two free areas above /
    // below the queue (queueTopDock / queueBottomDock, which load the pane's
    // content view from this registry). Never both: each floating loader is
    // active only while its pane is open AND not docked, so there is at most
    // one instance (matters for Milkdrop's GL context / projectM).
    //
    // Registry: pane id -> content component + dock heights. The id is also
    // the prefix of the pane's open flag (root.<id>PaneOpen). A future
    // dockable pane = one entry here + a dock component + dock props on its
    // floating loader.
    Component {
        id: audioMeterDockComponent
        Item {   // same 6 px margin as in AudioMeterWindow
            AudioMeterView { anchors.fill: parent; anchors.margins: 6; meter: audioMeter; meterConfig: appConfig }
        }
    }
    Component {
        id: audioVisualizerDockComponent
        AudioVisualizerView { playback: engine; visualizer: audioVisualizer; visualizerConfig: appConfig }
    }
    Component {
        id: milkdropDockComponent
        MilkdropPaneView { playback: engine; milkdropConfig: appConfig }
    }
    readonly property var dockablePanes: ({
        audioMeter:      { component: audioMeterDockComponent,      minDockHeight: 90,  defaultDockHeight: 140 },
        audioVisualizer: { component: audioVisualizerDockComponent, minDockHeight: 120, defaultDockHeight: 200 },
        milkdrop:        { component: milkdropDockComponent,        minDockHeight: 160, defaultDockHeight: 260 }
    })

    // Which pane is docked in each area ("" = empty). A pane counts as docked
    // only while open: closing a docked pane empties its area.
    property string dockTop: ""
    property string dockBottom: ""
    // Session memory: the area a pane was last docked in, so reopening it from
    // the BottomBar puts it back there (if that area is free). Forgotten when
    // the user floats the pane again.
    property var lastDockSlot: ({})

    function dockSlotOf(id) {
        return root.dockTop === id ? "top" : root.dockBottom === id ? "bottom" : ""
    }
    function dockArea(slot) { return slot === "top" ? queueTopDock : queueBottomDock }

    // Dock pane `id` into `slot` ("top"/"bottom") and open it there. The slot
    // is set BEFORE the open flag, so the floating loader never starts.
    function dockPane(id, slot) {
        const entry = root.dockablePanes[id]
        if (!entry) return
        const occupant = slot === "top" ? root.dockTop : root.dockBottom
        if (occupant !== "" && occupant !== id) return
        if (root.dockTop === id)    root.dockTop = ""
        if (root.dockBottom === id) root.dockBottom = ""
        if (slot === "top") root.dockTop = id
        else                root.dockBottom = id
        root.lastDockSlot[id] = slot
        root[id + "PaneOpen"] = true

        // Give the area room for the pane: keep its current height if it is
        // big enough, else the mode's saved height, else the pane's default.
        const area  = root.dockArea(slot)
        const saved = root.savedDockHeight(slot, root.layoutFullscreen)
        if (area.SplitView.preferredHeight < entry.minDockHeight)
            area.SplitView.preferredHeight = saved >= entry.minDockHeight ? saved : entry.defaultDockHeight
    }

    // Float a docked pane again: emptying its area makes the floating loader
    // start (the open flag stays true).
    function undockPane(id) {
        delete root.lastDockSlot[id]
        if (root.dockTop === id)    root.dockTop = ""
        if (root.dockBottom === id) root.dockBottom = ""
    }

    // Close a pane wherever it is. The open flag goes false BEFORE the area is
    // emptied, so a docked pane doesn't flash up as a floating window. The
    // area keeps its size (FREE SPACE) and lastDockSlot is kept.
    function closePane(id) {
        root[id + "PaneOpen"] = false
        if (root.dockTop === id)    root.dockTop = ""
        if (root.dockBottom === id) root.dockBottom = ""
    }

    // Persistence: an area's entry is set exactly while a pane is docked and
    // open there (closePane() empties it), so the config always holds what a
    // restart should bring back.
    onDockTopChanged:    appConfig.saveDockedPanes(root.dockTop, root.dockBottom)
    onDockBottomChanged: appConfig.saveDockedPanes(root.dockTop, root.dockBottom)

    // Startup (Component.onCompleted, window still hidden): reopen the panes
    // that were docked at the last exit, in their areas. Unknown ids (a pane
    // removed in a later version) and a duplicate are ignored.
    function restoreDockedPanes() {
        const top    = appConfig.queueTopDockPane
        const bottom = appConfig.queueBottomDockPane
        if (top !== "" && root.dockablePanes[top])
            root.dockPane(top, "top")
        if (bottom !== "" && bottom !== top && root.dockablePanes[bottom])
            root.dockPane(bottom, "bottom")
    }

    // BottomBar button: close if open; otherwise reopen in the area it was
    // last docked in when that area is free, else as a floating window.
    function togglePane(id) {
        if (root[id + "PaneOpen"]) {
            root.closePane(id)
            return
        }
        const slot = root.lastDockSlot[id]
        if (slot && (slot === "top" ? root.dockTop : root.dockBottom) === "")
            root.dockPane(id, slot)
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
                                 nowPlayingPanel.width,
                                 root.layoutFullscreen)
            // The free areas above/below the queue: their preferredHeight
            // (only a handle drag writes it), not their current height -- a
            // window squeezed too small must not overwrite what the user set.
            // Only while an area holds a docked pane (UC-38); an empty area
            // keeps the stored height of its last docked pane.
            const full = root.layoutFullscreen
            appConfig.saveQueueDockHeights(
                root.dockTop !== "" ? Math.round(queueTopDock.SplitView.preferredHeight)
                                    : root.savedDockHeight("top", full),
                root.dockBottom !== "" ? Math.round(queueBottomDock.SplitView.preferredHeight)
                                       : root.savedDockHeight("bottom", full),
                full)

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

            // Queue column: a vertical SplitView of free area | queue | free
            // area, so the queue can be made shorter from the top and from the
            // bottom (its two handles sit directly above and below it). The
            // free areas (QueueDockArea) can hold a docked pane (UC-38, see
            // "Docking panes" above). The queue fills the rest, so window height
            // changes go to the queue; the areas keep their size. Width (as
            // before) and the two heights are persisted per mode -- see
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

                QueueDockArea {
                    id: queueTopDock
                    // Starts collapsed; restoreDockedPanes() / applyDockHeights()
                    // open it only when a pane comes back docked (UC-38).
                    SplitView.preferredHeight: 0
                    // A docked pane can't be squeezed below its own minimum
                    SplitView.minimumHeight: root.dockTop !== "" ? root.dockablePanes[root.dockTop].minDockHeight : 0
                    SplitView.onPreferredHeightChanged: saveLayoutTimer.restart()
                    paneComponent: root.dockTop !== "" ? root.dockablePanes[root.dockTop].component : null
                    onUndockRequested: root.undockPane(root.dockTop)
                    onCloseRequested:  root.closePane(root.dockTop)
                }

                PlaybackQueue {
                    id: playbackQueuePanel
                    SplitView.fillHeight:    true
                    SplitView.minimumHeight: 200
                    engine: engine
                    autoPlay: autoPlay
                    appConfig: appConfig
                }

                QueueDockArea {
                    id: queueBottomDock
                    SplitView.preferredHeight: 0
                    SplitView.minimumHeight: root.dockBottom !== "" ? root.dockablePanes[root.dockBottom].minDockHeight : 0
                    SplitView.onPreferredHeightChanged: saveLayoutTimer.restart()
                    paneComponent: root.dockBottom !== "" ? root.dockablePanes[root.dockBottom].component : null
                    onUndockRequested: root.undockPane(root.dockBottom)
                    onCloseRequested:  root.closePane(root.dockBottom)
                }
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
                    exportPlaylistDialog.playlistName = engine.activePlaylistName
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
