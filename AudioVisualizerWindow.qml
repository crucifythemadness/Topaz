import QtQuick

// ── AudioVisualizerWindow ────────────────────────────────────────────────
// Detachable bar-style audio visualizer — see FloatingPane.qml for the
// movable/resizable/right-click-to-close chrome this builds on, and
// BigCoverWindow.qml/TagInfoWindow.qml for the sibling panes it mirrors the
// wiring pattern of. Opened by clicking the "AUDIO VISUALIZER" button in
// BottomBar.qml (see Main.qml's Loader wiring).
//
// Purely a renderer: all audio analysis (FFT, band grouping, decay,
// peak-hold) happens in AudioVisualizerController (C++) — this file just
// draws whatever barLevels/peakLevels currently say. See UC-19.
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

    readonly property bool hasTrack: engine && engine.currentTitle.length > 0
    readonly property var  barModel:  visualizer ? visualizer.barLevels  : []
    readonly property var  peakModel: visualizer ? visualizer.peakLevels : []
    readonly property color barColor: (visualizerConfig && visualizerConfig.audioVisualizerColor.length > 0)
                                       ? visualizerConfig.audioVisualizerColor : Theme.primary
    readonly property bool  peakHoldEnabled: visualizerConfig ? visualizerConfig.audioVisualizerPeakHoldEnabled : true

    // Background-only opacity — applied to the window's own clear color
    // (Window.color's alpha channel) AND the no-track placeholder's gradient
    // below (both are "the pane's background" as far as this setting is
    // concerned), never to the bars/peak ticks, which bind fully-opaque colors
    // and are entirely unaffected by this. Deliberately NOT using
    // Window.opacity, which would fade the whole window including its content.
    // Lets the user drop the pane anywhere with just the bars visible.
    //
    // The window's own color additionally premultiplies RGB by paneOpacity
    // (not just the alpha channel) — DWM/Direct3D composition on Windows
    // expects a premultiplied-alpha convention for a composited window's clear
    // color; at true zero opacity the RGB channels must also be zero, or a
    // compositor assuming premultiplied input can render a faint residual tint
    // instead of true invisibility. This only applies to the window's own
    // clear color, not ordinary in-scene Rectangles like the placeholder below
    // (Qt Quick's own scenegraph alpha blending already handles those
    // correctly without this treatment).
    readonly property real paneOpacity:
        visualizerConfig ? visualizerConfig.audioVisualizerPaneOpacity : 1.0
    color: Qt.rgba(Theme.surfaceContainerLowest.r * paneOpacity,
                   Theme.surfaceContainerLowest.g * paneOpacity,
                   Theme.surfaceContainerLowest.b * paneOpacity,
                   paneOpacity)

    // ── Placeholder — no track loaded ─────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: !visWindow.hasTrack
        gradient: Gradient {
            orientation: Gradient.Diagonal
            GradientStop {
                position: 0.0
                color: Qt.rgba(Theme.surfaceContainerHigh.r, Theme.surfaceContainerHigh.g,
                               Theme.surfaceContainerHigh.b, visWindow.paneOpacity)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(Theme.surfaceBright.r, Theme.surfaceBright.g,
                               Theme.surfaceBright.b, visWindow.paneOpacity)
            }
        }
        Text {
            anchors.centerIn: parent
            text: "♫  " + qsTr("NO TRACK")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     22
            font.weight:        Font.Bold
            font.letterSpacing: 2
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.30)
        }
    }

    // ── Bars ───────────────────────────────────────────────────────────────
    Row {
        id: barsRow
        anchors.fill: parent
        anchors.margins: 12
        visible: visWindow.hasTrack
        spacing: 3

        readonly property int  barCount: visWindow.barModel.length
        readonly property real barWidth: barCount > 0
                                          ? (width - spacing * (barCount - 1)) / barCount
                                          : 0

        // Repeater's model is a plain integer (the bar count), not the level
        // array itself — the level array is reassigned wholesale ~30 times a
        // second (see AudioVisualizerController::onUpdateTick), and Repeater
        // would recreate every delegate on each such reassignment if the
        // array were the model directly. Keeping the model a stable integer
        // means delegates are created once; only their height/y bindings
        // (which read barModel[index] reactively) recompute each tick.
        Repeater {
            model: barsRow.barCount

            delegate: Item {
                width:  barsRow.barWidth
                height: barsRow.height

                readonly property real level:
                    (index < visWindow.barModel.length && typeof visWindow.barModel[index] === "number")
                    ? visWindow.barModel[index] : 0
                readonly property real peak:
                    (index < visWindow.peakModel.length && typeof visWindow.peakModel[index] === "number")
                    ? visWindow.peakModel[index] : 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: parent.height * parent.level
                    radius: 1
                    color:  visWindow.barColor
                }

                Rectangle {
                    visible: visWindow.peakHoldEnabled && parent.peak > 0.01
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: parent.height * parent.peak
                    width:  parent.width
                    height: 2
                    color:  Theme.fgSurface
                }
            }
        }
    }
}
