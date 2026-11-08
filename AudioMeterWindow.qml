import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// ── AudioMeterWindow ─────────────────────────────────────────────────────
// Detachable Audio Meter pane (UC-37) -- FloatingPane chrome (move, resize,
// right-click to close) around AudioMeterView. Opened by the "AUDIO METER"
// button in BottomBar.qml (see Main.qml's Loader wiring, which mirrors the
// audio visualizer pane's).
FloatingPane {
    id: meterWindow

    property var meter: null
    // Not named "appConfig" -- same outer-id shadowing gotcha as
    // AudioVisualizerWindow.qml's visualizerConfig.
    property var meterConfig: null

    title: qsTr("Topaz — Audio Meter")
    minPaneWidth:  360
    minPaneHeight: 100
    dockable: true

    // Background-only opacity, premultiplied like AudioVisualizerWindow's
    // window clear colour (see the comment there).
    readonly property real paneOpacity: meterConfig ? meterConfig.audioMeterPaneOpacity : 1.0
    color: Qt.rgba(Theme.surfaceContainerLowest.r * paneOpacity,
                   Theme.surfaceContainerLowest.g * paneOpacity,
                   Theme.surfaceContainerLowest.b * paneOpacity,
                   paneOpacity)

    AudioMeterView {
        anchors.fill: parent
        anchors.margins: 6
        meter: meterWindow.meter
        meterConfig: meterWindow.meterConfig
    }
}
