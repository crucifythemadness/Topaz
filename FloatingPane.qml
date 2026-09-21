import QtQuick
import QtQuick.Window

// ── FloatingPane ─────────────────────────────────────────────────────────
// Reusable base for detachable, frameless, movable, resizable panes that can
// be dragged onto any connected screen (a plain QtQuick Popup can't leave its
// owning ApplicationWindow's surface, so this is a genuine second top-level
// Window instead). First user: BigCoverWindow.qml. More are planned later
// (tag info, audio visualizers) — keep this generic, no AppConfig/persistence
// logic here; that's the owner's responsibility via geometrySettled().
//
// Usage (see BigCoverWindow.qml):
//   FloatingPane {
//       Image { ... }   // becomes a child of the content area via the
//   }                   // default property alias below
//
// Interaction:
//   - Left-press anywhere (except the resize edges) starts an OS-native
//     interactive move (Window.startSystemMove()); pointing-hand cursor,
//     matching NowPlaying's Play/Pause.
//   - Right-click anywhere emits closeRequested() — this pane does not close
//     itself; the owner (typically a Loader) decides what "closed" means.
//   - Dragging any of the 8 edge/corner zones resizes the pane, with the
//     matching cursor shape. When fixedAspectRatio is 0 (default) this uses
//     an OS-native interactive resize (Window.startSystemResize()); when set,
//     see "Aspect-locked resize" below — startSystemResize() hands the whole
//     interactive gesture to the OS window manager, so there's no way to
//     constrain intermediate frames of it, which is why locking requires a
//     completely different, manually-tracked mechanism.
//   - Any settled change to x/y/width/height (debounced 500ms, same pattern
//     as Main.qml's saveLayoutTimer) emits geometrySettled() for the owner to
//     persist.
Window {
    id: pane

    default property alias contentData: contentItem.data

    property int minPaneWidth:  120
    property int minPaneHeight: 120
    property int gripSize: 8

    // When true, every interactive area below shows a blank cursor instead
    // of its own native shape. Purely a display toggle — FloatingPane has no
    // opinion on *when* to hide it, same "generic base, subclass decides
    // meaning" split as doubleClicked() below. First consumer: MilkdropWindow.qml's
    // auto-hide-cursor-during-fullscreen-idle behavior (see UC-20).
    property bool cursorHidden: false

    // 0 (default) = free resize via native startSystemResize(). Otherwise the
    // width/height ratio to maintain while resizing (e.g. 1.0 for a square
    // pane) — see "Aspect-locked resize" below. Generic on purpose: any
    // future FloatingPane subclass can opt in, not just square ones.
    property real fixedAspectRatio: 0

    // Kiosk mode -- driven by the owner (Main.qml: true exactly while the main
    // window is fullscreen), never set by the pane itself. While true the pane
    // is topmost, so it can be placed over the OS taskbar (which is otherwise
    // always above an ordinary window) and stays above the fullscreen main
    // window. Visual only: nothing here blocks other applications. Leaving
    // fullscreen removes the hint again.
    property bool kiosk: false
    onKioskChanged: { if (kiosk && visible) raise() }

    // Topmost is not enough on Windows: the taskbar is topmost too, and the
    // shell puts it back on top of that band whenever the foreground window
    // changes (e.g. clicking the fullscreen main window on the other display),
    // which covers a kiosk pane again. raise() puts the pane back on top without
    // activating it. Three layers, because the shell re-sorts a moment AFTER a
    // focus change and can also do it for reasons we never see:
    //   1. kioskBurst(): raise now and three more times, 80 ms apart. Called when
    //      this pane loses focus (below) and by Main.qml when the main window
    //      is activated.
    //   2. kioskRaiseTimer: a slow safety net (taskbar clicked, another app
    //      popped up).
    // Neither skips a focused pane: being the focused window does not keep a
    // topmost pane above the taskbar (measured: the taskbar covered a focused
    // pane).
    //
    // The trigger is activeFocusItem, NOT Window.active: the panes are
    // transient children of the main window and Qt counts a window as active
    // while any window in its transient chain has focus, so `active` was
    // measured to stay true on BOTH windows however focus moved (it fires but
    // never goes false). activeFocusItem follows the real OS focus window
    // (measured: it alternates cleanly between the main window and a pane).
    function kioskBurst() {
        if (!kiosk || !visible) return
        kioskBurstTimer.n = 0
        kioskBurstTimer.restart()
    }
    onActiveFocusItemChanged: { if (activeFocusItem === null) kioskBurst() }

    Timer {
        id: kioskBurstTimer
        interval: 80
        repeat: true
        triggeredOnStart: true
        property int n: 0
        onTriggered: {
            pane.raise()
            if (++n >= 4) stop()
        }
    }

    Timer {
        id: kioskRaiseTimer
        interval: 400
        repeat: true
        running: pane.kiosk && pane.visible
        onTriggered: pane.raise()
    }

    // NoDropShadowWindowHint removes Qt's own drop shadow on the frameless
    // window; WindowChrome.prepareWindow() below (native, no QML equivalent
    // exists) requests an alpha-capable surface before the native window is
    // created (needed for AudioVisualizerWindow's background opacity to
    // actually composite as translucent — see WindowChrome's own comment for
    // why a QML `color` binding alone isn't reliable here) and removes
    // Windows 11's default DWM window border on top of that.
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.NoDropShadowWindowHint
           | (kiosk ? Qt.WindowStaysOnTopHint : 0)

    // The logical rect ({x, y, width, height}, same virtual-desktop
    // coordinates as this pane's own x/y) of the screen the pane is on right
    // now: the screen containing its center, else the one it overlaps most,
    // else the first. Used instead of the `Screen` attached property, which
    // did not follow the pane across displays -- F10 (Milkdrop fullscreen)
    // and the double-click placements always went to the main display.
    function currentScreenRect() {
        // qmllint disable missing-property
        const screens = Qt.application.screens
        // qmllint enable missing-property
        const cx = pane.x + pane.width  / 2
        const cy = pane.y + pane.height / 2
        let best = null
        let bestArea = -1
        for (let i = 0; i < screens.length; i++) {
            const s = screens[i]
            if (cx >= s.virtualX && cx < s.virtualX + s.width &&
                cy >= s.virtualY && cy < s.virtualY + s.height)
                return { x: s.virtualX, y: s.virtualY, width: s.width, height: s.height }
            const ox = Math.max(0, Math.min(pane.x + pane.width,  s.virtualX + s.width)  - Math.max(pane.x, s.virtualX))
            const oy = Math.max(0, Math.min(pane.y + pane.height, s.virtualY + s.height) - Math.max(pane.y, s.virtualY))
            if (ox * oy > bestArea) { bestArea = ox * oy; best = s }
        }
        if (best)
            return { x: best.virtualX, y: best.virtualY, width: best.width, height: best.height }
        return { x: Screen.virtualX, y: Screen.virtualY, width: Screen.width, height: Screen.height }
    }
    minimumWidth:  minPaneWidth
    minimumHeight: minPaneHeight

    // Explicit default (rather than relying on Window's own default, which
    // isn't guaranteed the same across Qt versions/contexts): stay hidden
    // until the owner has positioned the pane, so it never flashes into view
    // at a default position before Component.onCompleted repositions it.
    visible: false

    // Fires before any subclass's own outer Component.onCompleted (in
    // Main.qml's Loader.sourceComponent blocks, which set visible = true) —
    // nested Component.onCompleted handlers fire innermost-first, so the
    // native window is prepared (translucency-capable, border-free) before
    // it's ever actually shown.
    Component.onCompleted: WindowChrome.prepareWindow(pane)

    signal closeRequested()
    signal geometrySettled(int x, int y, int width, int height, string screenName)
    // Emitted on a left-button double-click anywhere on the pane — see the
    // MouseArea below for the detection mechanism. Generic on purpose — like
    // closeRequested()/geometrySettled(), FloatingPane just detects and emits;
    // what a double-click *means* (e.g. maximize/restore) is entirely up to the
    // subclass. Unhandled by any pane that doesn't declare an onDoubleClicked
    // handler, so this is a no-op for panes that don't opt in.
    signal doubleClicked()
    // Emitted on every mouse movement over the pane (hover or drag alike —
    // see the move MouseArea's hoverEnabled below) via the same handler that
    // already reliably drives window dragging. Generic on purpose, same
    // split as doubleClicked(); first consumer: MilkdropWindow.qml's
    // auto-hide-cursor-during-fullscreen-idle behavior (see UC-20), which
    // needs a proven-reliable movement signal rather than a separately
    // stacked hover mechanism.
    signal mouseMoved()

    Item {
        id: contentItem
        anchors.fill: parent
    }

    // Move (whole pane) + close (right-click) + double-click. Declared before
    // the resize grips below so they naturally stack above it for their thin
    // strips.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.PointingHandCursor

        property bool _moveStarted: false

        onPressed: (mouse) => { _moveStarted = false }
        onPositionChanged: (mouse) => {
            pane.mouseMoved()
            // Only start the native move once real movement is seen while the
            // left button is held — NOT on the raw press itself. An earlier
            // version called startSystemMove() unconditionally on every press,
            // which hands the mouse off to the OS's native interactive-move
            // loop immediately; that loop swallows the second press of a
            // double-click before Qt's own click/doubleClick synthesis (below)
            // ever sees it — confirmed by testing, not just theorized. A
            // stationary click (both halves of a double-click) never reaches
            // this branch, so the native loop is never entered for it; a real
            // drag still starts moving on its very first pixel of motion, so
            // single-click-drag keeps feeling instant.
            if (pressed && (mouse.buttons & Qt.LeftButton) && !_moveStarted) {
                _moveStarted = true
                pane.startSystemMove()
            }
        }
        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) pane.closeRequested()
        }
        onDoubleClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) pane.doubleClicked()
        }
    }

    // ── Aspect-locked resize (only used while fixedAspectRatio > 0) ──────
    // Tracks the drag using global cursor coordinates (via mapToGlobal),
    // never the grip's own local mouse.x/y — the grip itself moves as the
    // window resizes, so accumulating local per-frame deltas would drift;
    // recomputing from the fixed press-time global position each move does
    // not. xAnchorRight/yAnchorBottom say which corner of the pane stays
    // fixed (true = right/bottom edge fixed, so the left/top edge is the one
    // that moves); useX/useY say which mouse-delta axis this grip's growth
    // amount is drawn from (edges use one axis; corners use both, taking
    // whichever grew the pane more, via Math.max).
    property real _dragPressGlobalX: 0
    property real _dragPressGlobalY: 0
    property real _dragStartX: 0
    property real _dragStartY: 0
    property real _dragStartSize: 0

    function beginAspectResize(item, mouse) {
        const g = item.mapToGlobal(mouse.x, mouse.y)
        pane._dragPressGlobalX = g.x
        pane._dragPressGlobalY = g.y
        pane._dragStartX = pane.x
        pane._dragStartY = pane.y
        pane._dragStartSize = pane.width   // width === height, already square
    }

    function updateAspectResize(item, mouse, xAnchorRight, yAnchorBottom, useX, useY) {
        const g = item.mapToGlobal(mouse.x, mouse.y)
        const growthX = xAnchorRight ? (pane._dragPressGlobalX - g.x) : (g.x - pane._dragPressGlobalX)
        const growthY = yAnchorBottom ? (pane._dragPressGlobalY - g.y) : (g.y - pane._dragPressGlobalY)
        const growth = (useX && useY) ? Math.max(growthX, growthY) : (useX ? growthX : growthY)
        const newSize = Math.max(pane.minPaneWidth, pane._dragStartSize + growth)
        pane.width  = newSize
        pane.height = newSize
        pane.x = xAnchorRight ? (pane._dragStartX + pane._dragStartSize) - newSize : pane._dragStartX
        pane.y = yAnchorBottom ? (pane._dragStartY + pane._dragStartSize) - newSize : pane._dragStartY
    }

    // ── Resize edges/corners ────────────────────────────────────────────
    MouseArea {
        id: topGrip
        anchors { top: parent.top; left: parent.left; right: parent.right
                  leftMargin: pane.gripSize; rightMargin: pane.gripSize }
        height: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeVerCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(topGrip, mouse)
            else pane.startSystemResize(Qt.TopEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(topGrip, mouse, true, true, false, true)
        }
    }
    MouseArea {
        id: bottomGrip
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                  leftMargin: pane.gripSize; rightMargin: pane.gripSize }
        height: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeVerCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(bottomGrip, mouse)
            else pane.startSystemResize(Qt.BottomEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(bottomGrip, mouse, false, false, false, true)
        }
    }
    MouseArea {
        id: leftGrip
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                  topMargin: pane.gripSize; bottomMargin: pane.gripSize }
        width: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeHorCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(leftGrip, mouse)
            else pane.startSystemResize(Qt.LeftEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(leftGrip, mouse, true, true, true, false)
        }
    }
    MouseArea {
        id: rightGrip
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom
                  topMargin: pane.gripSize; bottomMargin: pane.gripSize }
        width: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeHorCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(rightGrip, mouse)
            else pane.startSystemResize(Qt.RightEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(rightGrip, mouse, false, false, true, false)
        }
    }
    MouseArea {
        id: topLeftGrip
        anchors { top: parent.top; left: parent.left }
        width: pane.gripSize; height: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeFDiagCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(topLeftGrip, mouse)
            else pane.startSystemResize(Qt.TopEdge | Qt.LeftEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(topLeftGrip, mouse, true, true, true, true)
        }
    }
    MouseArea {
        id: bottomRightGrip
        anchors { bottom: parent.bottom; right: parent.right }
        width: pane.gripSize; height: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeFDiagCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(bottomRightGrip, mouse)
            else pane.startSystemResize(Qt.BottomEdge | Qt.RightEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(bottomRightGrip, mouse, false, false, true, true)
        }
    }
    MouseArea {
        id: topRightGrip
        anchors { top: parent.top; right: parent.right }
        width: pane.gripSize; height: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeBDiagCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(topRightGrip, mouse)
            else pane.startSystemResize(Qt.TopEdge | Qt.RightEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(topRightGrip, mouse, false, true, true, true)
        }
    }
    MouseArea {
        id: bottomLeftGrip
        anchors { bottom: parent.bottom; left: parent.left }
        width: pane.gripSize; height: pane.gripSize
        cursorShape: pane.cursorHidden ? Qt.BlankCursor : Qt.SizeBDiagCursor
        onPressed: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.beginAspectResize(bottomLeftGrip, mouse)
            else pane.startSystemResize(Qt.BottomEdge | Qt.LeftEdge)
        }
        onPositionChanged: (mouse) => {
            if (pane.fixedAspectRatio > 0) pane.updateAspectResize(bottomLeftGrip, mouse, true, false, true, true)
        }
    }

    // ── Geometry persistence hook ────────────────────────────────────────
    onXChanged:      geometryTimer.restart()
    onYChanged:      geometryTimer.restart()
    onWidthChanged:  geometryTimer.restart()
    onHeightChanged: geometryTimer.restart()

    Timer {
        id: geometryTimer
        interval: 500
        repeat: false
        onTriggered: pane.geometrySettled(pane.x, pane.y, pane.width, pane.height,
                                           // qmllint disable missing-property
                                           pane.screen ? pane.screen.name : "")
        // qmllint enable missing-property
    }
}
