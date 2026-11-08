import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// ── AudioMeterView ───────────────────────────────────────────────────────
// The Audio Meter's content (UC-37), independent of where it is shown: the
// floating AudioMeterWindow today, a dock area in the queue column next.
// Loads the visual style chosen in Setup -> AUDIO METER; a new style = a new
// AudioMeter<Style>.qml plus one entry in styleComponent below. Registers
// with the controller while it exists, so analysis only runs while a meter
// is actually visible.
Item {
    id: root

    property var meter: null       // AudioMeterController
    property var meterConfig: null // AppConfig (not named appConfig, see AudioVisualizerWindow.qml)

    readonly property string style: meterConfig ? meterConfig.audioMeterStyle : "hifi90s"

    // Unknown/removed style names fall back to the first style.
    readonly property Component styleComponent: hifi90s

    Component {
        id: hifi90s
        AudioMeterHiFi90s {
            meter: root.meter
            peakHold: root.meterConfig ? root.meterConfig.audioMeterPeakHoldEnabled : true
            panelOpacity: root.meterConfig ? root.meterConfig.audioMeterPaneOpacity : 1.0
            colorScheme: root.meterConfig ? root.meterConfig.audioMeterColorScheme : "hifi"
        }
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.styleComponent
    }

    // acquire()/release() bookkeeping. `meter` may arrive as an initial
    // binding (no onMeterChanged) or later from a Loader.onLoaded, so both
    // paths go through _track().
    property var _acquired: null
    function _track() {
        if (_acquired === meter) return
        if (_acquired) _acquired.release()
        _acquired = meter
        if (meter) meter.acquire()
    }
    onMeterChanged: _track()
    Component.onCompleted: _track()
    Component.onDestruction: if (_acquired) _acquired.release()
}
