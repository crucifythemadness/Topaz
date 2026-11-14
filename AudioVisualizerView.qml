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
//
// Styles (Setup > AUDIO VISUALIZER > STYLE & COLOR, AppConfig
// audioVisualizerStyle): TOPAZ (default, the original look), LED, GRADIENT
// (bar delegates below), LINE, RADIAL, SCOPE (VisualizerShapeItem, C++).
// Only the chosen style's items exist. Performance rules every
// style follows (UC-19 "Styles"): delegates created once (Repeater model =
// bar count), only per-bar height/position bindings change per frame, at
// most 2 changing items per bar, no Canvas, no per-frame item creation. LED
// and GRADIENT draw each bar as ONE tiled Image of a generated texture
// (image://vizstyle, vizstyleimageprovider.h), cut off at the bar's height.
Item {
    id: view

    property var playback: null
    property var visualizer: null
    property var visualizerConfig: null
    // Pane Opacity (Setup): alpha of everything that counts as the pane's
    // background -- the NO TRACK placeholder, LED's unlit segments, and (docked
    // only, see drawsOwnBackground) the pane surface itself. Never the bars.
    // Same behaviour in every style.
    property real backgroundOpacity:
        visualizerConfig ? visualizerConfig.audioVisualizerPaneOpacity : 1.0
    // The floating AudioVisualizerWindow paints the pane surface as its own
    // window colour (translucent over the desktop). Docked there is no window
    // of its own, so the view paints that surface itself, at
    // backgroundOpacity over the dock area -- the same pane colour and the
    // same alpha as floating, just over Topaz instead of the desktop.
    property bool drawsOwnBackground: false

    readonly property bool hasTrack: playback && playback.currentTitle.length > 0
    readonly property var  barModel:  visualizer ? visualizer.barLevels  : []
    readonly property var  peakModel: visualizer ? visualizer.peakLevels : []
    readonly property color barColor: (visualizerConfig && visualizerConfig.audioVisualizerColor.length > 0)
                                       ? visualizerConfig.audioVisualizerColor : Theme.primary
    readonly property bool  peakHoldEnabled: visualizerConfig ? visualizerConfig.audioVisualizerPeakHoldEnabled : true
    // Foreground-only opacity (bars + peak ticks), see AudioVisualizerWindow.qml.
    readonly property real barOpacity:
        visualizerConfig ? visualizerConfig.audioVisualizerBarOpacity : 1.0
    readonly property string styleName:
        visualizerConfig ? visualizerConfig.audioVisualizerStyle : "topaz"
    // LINE / RADIAL / SCOPE are drawn by VisualizerShapeItem (C++), the
    // others by the bars Row below.
    readonly property bool shapeStyle:
        styleName === "line" || styleName === "radial" || styleName === "scope"

    // ── Pane surface (docked only) ────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: view.drawsOwnBackground && view.hasTrack && view.backgroundOpacity > 0
        color: Qt.rgba(Theme.surfaceContainerLowest.r, Theme.surfaceContainerLowest.g,
                       Theme.surfaceContainerLowest.b, view.backgroundOpacity)
    }

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

        // LED geometry: ~24 segments over the pane height, 30 % gap. The
        // texture only changes with colour or pane height, never per frame.
        readonly property int ledPitch:  Math.max(4, Math.floor(height / 24))
        readonly property int ledGap:    Math.max(1, Math.round(ledPitch * 0.3))
        readonly property int ledSeg:    ledPitch - ledGap
        readonly property int ledMaxLit: Math.floor(height / ledPitch)
        readonly property string ledSource: "image://vizstyle/led/"
                                            + view.barColor.toString().substring(1)
                                            + "/" + ledSeg + "/" + ledGap
        // GRADIENT strip: generated in 16 px steps of the pane height (no new
        // texture per pixel while the pane is being resized), at least as tall
        // as the bars, bottom-aligned -- so a colour sits at a fixed height.
        // Colours: the Audio Meter's two schemes (Setup: HIFI / TOPAZ, same
        // values as AudioMeterHiFi90s.qml). Colour Shift 0..1 -> span 1.3..0.3
        // of the bar height (0.3 = 1.0 = the original gradient).
        readonly property bool gradientTopaz:
            view.visualizerConfig && view.visualizerConfig.audioVisualizerGradientScheme === "topaz"
        readonly property real gradientShift:
            view.visualizerConfig ? view.visualizerConfig.audioVisualizerGradientShift : 0.3
        readonly property string gradientColors: gradientTopaz
            ? Theme.secondary.toString().substring(1) + "-" + Theme.primaryContainer.toString().substring(1)
              + "-FF4FB8-FF2E8A"
            : "3DFF7A-FFE14A-FF8A1F-FF2D45"
        readonly property string gradientSource: "image://vizstyle/gradient/" + gradientColors
                                                 + "/" + Math.round((1.3 - gradientShift) * 1000)
                                                 + "/" + Math.max(16, Math.ceil(height / 16) * 16)

        // Repeater's model is a plain integer (the bar count), not the level
        // array itself — the level array is reassigned wholesale ~30 times a
        // second (see AudioVisualizerController::onUpdateTick), and Repeater
        // would recreate every delegate on each such reassignment if the
        // array were the model directly. Keeping the model a stable integer
        // means delegates are created once; only their height/y bindings
        // (which read barModel[index] reactively) recompute each tick. The
        // delegate itself only changes when the style does.
        Repeater {
            model: view.shapeStyle ? 0 : barsRow.barCount   // no bar items for LINE/RADIAL/SCOPE
            delegate: view.styleName === "led"      ? ledBar
                    : view.styleName === "gradient" ? gradientBar
                    : topazBar
        }
    }

    // ── TOPAZ (default) — the original look, unchanged ───────────────────
    Component {
        id: topazBar
        Item {
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

    // ── LED — lit segments (rounded to whole segments) over dim unlit ones ─
    Component {
        id: ledBar
        Item {
            width:  barsRow.barWidth
            height: barsRow.height

            readonly property real level:
                (index < view.barModel.length && typeof view.barModel[index] === "number")
                ? view.barModel[index] : 0
            readonly property real peak:
                (index < view.peakModel.length && typeof view.peakModel[index] === "number")
                ? view.peakModel[index] : 0

            // Unlit segments: static (only changes on resize/colour). Part of
            // the pane's background, so they fade with Pane Opacity -- at 0 %
            // only the lit segments remain, like the bars of every other style.
            Image {
                anchors.bottom: parent.bottom
                width:  parent.width
                height: barsRow.ledMaxLit * barsRow.ledPitch
                source: barsRow.ledSource
                fillMode: Image.Tile
                verticalAlignment: Image.AlignBottom
                smooth: false
                opacity: 0.14 * view.backgroundOpacity
                visible: opacity > 0
            }
            // Lit segments: the only per-frame change is this height.
            Image {
                anchors.bottom: parent.bottom
                width:  parent.width
                height: Math.min(barsRow.ledMaxLit, Math.round(parent.level * barsRow.ledMaxLit))
                        * barsRow.ledPitch
                source: barsRow.ledSource
                fillMode: Image.Tile
                verticalAlignment: Image.AlignBottom
                smooth: false
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

    // ── GRADIENT — green → yellow → red by absolute height (own colours) ─
    Component {
        id: gradientBar
        Item {
            width:  barsRow.barWidth
            height: barsRow.height

            readonly property real level:
                (index < view.barModel.length && typeof view.barModel[index] === "number")
                ? view.barModel[index] : 0
            readonly property real peak:
                (index < view.peakModel.length && typeof view.peakModel[index] === "number")
                ? view.peakModel[index] : 0

            Image {
                anchors.bottom: parent.bottom
                width:  parent.width
                height: parent.height * parent.level
                source: barsRow.gradientSource
                fillMode: Image.Tile
                verticalAlignment: Image.AlignBottom
                smooth: false
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

    // ── LINE / RADIAL / SCOPE — one C++ scene-graph item ─────────────────
    // VisualizerShapeItem builds a single vertex-coloured geometry per frame
    // straight from the controller's levels / waveform (one draw call, no
    // per-bar items, no Canvas). Only exists while one of these styles is on.
    Loader {
        anchors.fill: parent
        anchors.margins: 12
        active: view.shapeStyle
        visible: view.hasTrack
        opacity: view.barOpacity
        sourceComponent: VisualizerShapeItem {
            visualizer: view.visualizer
            mode: view.styleName
            color: view.barColor
            peakColor: Theme.fgSurface
            peakHoldEnabled: view.peakHoldEnabled
        }
    }
}
