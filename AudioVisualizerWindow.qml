import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// ── AudioVisualizerWindow ────────────────────────────────────────────────
// Detachable bar-style audio visualizer — see FloatingPane.qml for the
// movable/resizable/right-click-to-close chrome this builds on, and
// BigCoverWindow.qml/TagInfoWindow.qml for the sibling panes it mirrors the
// wiring pattern of. Opened by clicking the "AUDIO VISUALIZER" button in
// BottomBar.qml (see Main.qml's Loader wiring). The content itself (bars,
// placeholder) is AudioVisualizerView.qml, shared with the docked copy
// (UC-38).
//
// Purely a renderer: all audio analysis (FFT, band grouping, decay,
// peak-hold) happens in AudioVisualizerController (C++) — see UC-19.
FloatingPane {
    id: visWindow

    property var engine: null
    property var visualizer: null
    // Deliberately NOT named "appConfig" — Main.qml's Component.onCompleted for
    // this pane (see the Loader wiring there) reads the OUTER "appConfig" id for
    // geometry restore, inside this object's own scope. A same-named local
    // property here would shadow that outer id for every unqualified reference
    // within this whole object, including Component.onCompleted — which runs
    // before Loader.onLoaded has a chance to set this property, so it would read
    // null and abort before ever reaching "visible = true" (confirmed: this is
    // exactly what broke the pane the first time). See UC-19.
    property var visualizerConfig: null

    title: qsTr("Topaz — Audio Visualizer")
    minPaneWidth:  400
    minPaneHeight: 200
    dockable: true

    // Background-only opacity — applied to the window's own clear color
    // (Window.color's alpha channel) AND the no-track placeholder's gradient
    // (both are "the pane's background" as far as this setting is concerned),
    // never to the bars/peak ticks. Deliberately NOT using Window.opacity,
    // which would fade the whole window including its content. Lets the user
    // drop the pane anywhere with just the bars visible.
    //
    // The window's own color additionally premultiplies RGB by paneOpacity
    // (not just the alpha channel) — DWM/Direct3D composition on Windows
    // expects a premultiplied-alpha convention for a composited window's clear
    // color; at true zero opacity the RGB channels must also be zero, or a
    // compositor assuming premultiplied input can render a faint residual tint
    // instead of true invisibility. This only applies to the window's own
    // clear color, not ordinary in-scene Rectangles like the placeholder
    // (Qt Quick's own scenegraph alpha blending already handles those
    // correctly without this treatment).
    readonly property real paneOpacity:
        visualizerConfig ? visualizerConfig.audioVisualizerPaneOpacity : 1.0
    color: Qt.rgba(Theme.surfaceContainerLowest.r * paneOpacity,
                   Theme.surfaceContainerLowest.g * paneOpacity,
                   Theme.surfaceContainerLowest.b * paneOpacity,
                   paneOpacity)

    AudioVisualizerView {
        anchors.fill: parent
        playback: visWindow.engine
        visualizer: visWindow.visualizer
        visualizerConfig: visWindow.visualizerConfig
        backgroundOpacity: visWindow.paneOpacity
    }
}
