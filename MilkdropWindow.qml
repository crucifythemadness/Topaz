import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
import QtQuick.Window

// ── MilkdropWindow ───────────────────────────────────────────────────────
// Detachable Milkdrop-compatible visualizer — see FloatingPane.qml for the
// movable/resizable/right-click-to-close chrome this builds on, and
// AudioVisualizerWindow.qml for the sibling pane it mirrors the wiring
// pattern of. Opened by clicking the "MILKDROP" button in BottomBar.qml (see
// Main.qml's Loader wiring). Double-click cycles horizontal position (mirrors
// BigCoverWindow.qml, see UC-17) and F10 toggles fullscreen — see UC-20.
//
// The content (MilkdropView + placeholders + preset toast) lives in
// MilkdropPaneView.qml, shared with the docked copy (UC-38); this file keeps
// only the window features. Unlike AudioVisualizerWindow (a thin renderer
// over a long-lived, Main.qml-owned AudioVisualizerController), MilkdropView
// owns real GPU/native resources (an offscreen OpenGL context, the projectM
// instance) — its lifetime is deliberately tied to this pane's own Loader
// lifecycle (created on open, destroyed on close), not kept alive for the
// whole app.
FloatingPane {
    id: mdWindow

    property var engine: null
    // Deliberately NOT named "appConfig" — same Component.onCompleted
    // scoping gotcha documented in AudioVisualizerWindow.qml's
    // "visualizerConfig" property. See UC-19/UC-20.
    property var milkdropConfig: null

    title: qsTr("Topaz — Milkdrop")
    minPaneWidth:  400
    minPaneHeight: 250

    // FloatingPane's base Window has no default color of its own, and Qt
    // Quick's own Window.color default is white — every sibling pane sets
    // this explicitly (see BigCoverWindow.qml/TagInfoWindow.qml); this one
    // was missing it, which showed as a solid white pane once the opaque
    // "NO TRACK" placeholder below stopped covering the whole window.
    color: Theme.surfaceContainerLowest

    readonly property bool hasTrack:  engine && engine.currentTitle.length > 0
    // Distinct from hasTrack: currentTitle stays set to the last track after
    // it pauses or the queue ends (so NowPlaying can keep showing it), so
    // hasTrack alone doesn't mean "actively playing" — gating the visualizer
    // on this instead is what actually stops it animating in those states.
    readonly property bool isPlaying: engine && engine.isPlaying

    // Double-click cycles the pane horizontally: original position (captured
    // on the first double-click of this open) → centered → right edge → left
    // edge → back to original → repeat. Exact mirror of BigCoverWindow.qml's
    // toggle (see UC-17) — only x changes, y/width/height stay untouched;
    // resizing stays entirely manual.
    property int  _hPositionState: 0   // 0 = original, 1 = center, 2 = right, 3 = left
    property real _restoreX: 0
    property bool _restoreXCaptured: false

    onDoubleClicked: {
        if (!_restoreXCaptured) {
            _restoreX = x
            _restoreXCaptured = true
        }
        _hPositionState = (_hPositionState + 1) % 4
        const scr = currentScreenRect()   // the display the pane is on, not the main one
        switch (_hPositionState) {
        case 1: x = scr.x + (scr.width - width) / 2; break  // center
        case 2: x = scr.x + scr.width - width;       break  // right edge
        case 3: x = scr.x;                           break  // left edge
        case 0: x = _restoreX;                       break  // original
        }
    }

    // F10 toggles fullscreen (manual geometry — same convention already used
    // for the double-click positions above and Main.qml's pane-centering,
    // rather than Qt's native Window.FullScreen visibility). Independent of
    // the double-click cycle above: whatever geometry is active when F10 is
    // pressed (manually dragged, or a result of double-clicking) is exactly
    // what gets restored on the second press.
    property bool _isFullscreen: false
    // Arrow-key nudging and the dock buttons (FloatingPane) only make sense
    // for a windowed pane.
    keyboardMoveEnabled: !_isFullscreen
    dockable: !_isFullscreen
    property real _preFullscreenX: 0
    property real _preFullscreenY: 0
    property real _preFullscreenWidth: 0
    property real _preFullscreenHeight: 0

    Shortcut {
        sequence: "F10"
        onActivated: {
            if (!mdWindow._isFullscreen) {
                // Fill the display the pane is on right now (measured before
                // it moves), not the main display. In kiosk mode the pane is
                // topmost, so this covers the taskbar strip too.
                // qmllint disable missing-property
                const scr = mdWindow.currentScreenRect()
                // qmllint enable missing-property
                mdWindow._preFullscreenX      = mdWindow.x
                mdWindow._preFullscreenY      = mdWindow.y
                mdWindow._preFullscreenWidth  = mdWindow.width
                mdWindow._preFullscreenHeight = mdWindow.height
                mdWindow.x      = scr.x
                mdWindow.y      = scr.y
                mdWindow.width  = scr.width
                mdWindow.height = scr.height
                mdWindow._isFullscreen = true
                mdWindow.cursorHidden = false
                cursorIdleTimer.restart()
            } else {
                mdWindow.x      = mdWindow._preFullscreenX
                mdWindow.y      = mdWindow._preFullscreenY
                mdWindow.width  = mdWindow._preFullscreenWidth
                mdWindow.height = mdWindow._preFullscreenHeight
                mdWindow._isFullscreen = false
                mdWindow.cursorHidden = false
                cursorIdleTimer.stop()
            }
        }
    }

    // Auto-hides the mouse cursor after 2s of no movement while fullscreen,
    // shows it again immediately on any movement — standard fullscreen-video
    // behavior. cursorHidden is FloatingPane's generic display toggle (see
    // its own comment); everything about *when* to hide lives here.
    Timer {
        id: cursorIdleTimer
        interval: 2000
        repeat: false
        onTriggered: mdWindow.cursorHidden = true
    }

    // FloatingPane's mouseMoved() is emitted from its own move MouseArea's
    // onPositionChanged — the same handler that already reliably drives
    // window dragging, so its delivery is proven (an earlier version used a
    // separate HoverHandler here, which turned out not to fire reliably
    // stacked below that MouseArea — see UC-20). Covers the pane's interior;
    // doesn't cover the 8px resize-grip strips at the very edges, a known,
    // accepted minor gap (see UC-20).
    onMouseMoved: {
        if (_isFullscreen) {
            cursorHidden = false
            cursorIdleTimer.restart()
        }
    }

    MilkdropPaneView {
        anchors.fill: parent
        playback: mdWindow.engine
        milkdropConfig: mdWindow.milkdropConfig
    }
}
