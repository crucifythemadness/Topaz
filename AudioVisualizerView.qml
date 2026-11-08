import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// ── AudioVisualizerView ──────────────────────────────────────────────────
// The bar visualizer's content (bars, peak ticks, NO TRACK placeholder),
// shared by the floating AudioVisualizerWindow.qml and the docked copy in a
// QueueDockArea (UC-38). Purely a renderer: all analysis happens in
// AudioVisualizerController (C++) -- see UC-19.
//
// The property is called "playback", not "engine": Main.qml's dock component
// binds it to the outer "engine" id, and a same-named local property would
// shadow that id (the scoping gotcha documented in AudioVisualizerWindow.qml).
Item {
    id: view

    property var playback: null
    property var visualizer: null
    property var visualizerConfig: null
    // Alpha of the NO TRACK placeholder's background: the floating window
    // passes its Pane Opacity (Setup), the docked copy keeps it opaque.
    property real backgroundOpacity: 1.0

    readonly property bool hasTrack: playback && playback.currentTitle.length > 0
    readonly property var  barModel:  visualizer ? visualizer.barLevels  : []
    readonly property var  peakModel: visualizer ? visualizer.peakLevels : []
    readonly property color barColor: (visualizerConfig && visualizerConfig.audioVisualizerColor.length > 0)
                                       ? visualizerConfig.audioVisualizerColor : Theme.primary
    readonly property bool  peakHoldEnabled: visualizerConfig ? visualizerConfig.audioVisualizerPeakHoldEnabled : true
    // Foreground-only opacity (bars + peak ticks), see AudioVisualizerWindow.qml.
    readonly property real barOpacity:
        visualizerConfig ? visualizerConfig.audioVisualizerBarOpacity : 1.0

    // ── Placeholder — no track loaded ─────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: !view.hasTrack
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Qt.rgba(Theme.surfaceContainerHigh.r, Theme.surfaceContainerHigh.g,
                               Theme.surfaceContainerHigh.b, view.backgroundOpacity)
            }
            GradientStop {
                position: 1.0
                color: Qt.rgba(Theme.surfaceBright.r, Theme.surfaceBright.g,
                               Theme.surfaceBright.b, view.backgroundOpacity)
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
        visible: view.hasTrack
        opacity: view.barOpacity
        spacing: 3

        readonly property int  barCount: view.barModel.length
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
                    (index < view.barModel.length && typeof view.barModel[index] === "number")
                    ? view.barModel[index] : 0
                readonly property real peak:
                    (index < view.peakModel.length && typeof view.peakModel[index] === "number")
                    ? view.peakModel[index] : 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: parent.height * parent.level
                    radius: 1
                    color:  view.barColor
                }

                Rectangle {
                    visible: view.peakHoldEnabled && parent.peak > 0.01
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
