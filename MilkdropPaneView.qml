import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// ── MilkdropPaneView ─────────────────────────────────────────────────────
// Milkdrop's content (MilkdropView + NO TRACK / PAUSED / unavailable
// placeholders + preset-name toast), shared by the floating MilkdropWindow.qml
// and the docked copy in a QueueDockArea (UC-38). Window-only features (F10
// full screen, double-click positions, cursor auto-hide) stay in
// MilkdropWindow.qml.
//
// MilkdropView owns real GPU/native resources (an offscreen OpenGL context,
// the projectM instance), so its lifetime is this item's: created when the
// pane opens (floating or docked), destroyed when it closes or moves between
// the two. Main.qml keeps at most one instance alive. See UC-20.
//
// "playback", not "engine": same outer-id shadowing reason as
// AudioVisualizerView.qml.
Item {
    id: view

    property var playback: null
    property var milkdropConfig: null

    readonly property bool hasTrack:  playback && playback.currentTitle.length > 0
    // Distinct from hasTrack: currentTitle stays set to the last track after
    // it pauses or the queue ends (so NowPlaying can keep showing it), so
    // hasTrack alone doesn't mean "actively playing" — gating the visualizer
    // on this instead is what actually stops it animating in those states.
    readonly property bool isPlaying: playback && playback.isPlaying

    MilkdropView {
        id: milkdropView
        anchors.fill: parent
        visible: view.hasTrack && view.isPlaying && !milkdropView.initFailed
        engine: view.playback
        appConfig: view.milkdropConfig
    }

    // ── Placeholder — no track loaded ─────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: !view.hasTrack && !milkdropView.initFailed
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
            GradientStop { position: 1.0; color: Theme.surfaceBright }
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

    // ── Placeholder — track loaded but not playing (paused, or queue ended) ─
    Rectangle {
        anchors.fill: parent
        visible: view.hasTrack && !view.isPlaying && !milkdropView.initFailed
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
            GradientStop { position: 1.0; color: Theme.surfaceBright }
        }
        Text {
            anchors.centerIn: parent
            text: "⏸  " + qsTr("PAUSED")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     22
            font.weight:        Font.Bold
            font.letterSpacing: 2
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.30)
        }
    }

    // ── Placeholder — projectM/OpenGL failed to initialize ─────────────────
    // Shown instead of either state above once MilkdropView reports it
    // couldn't set up its offscreen GL context or the projectM instance —
    // most likely this system's GPU/driver doesn't support the required
    // OpenGL 3.3 core profile. See UC-20.
    Rectangle {
        anchors.fill: parent
        visible: milkdropView.initFailed
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
            GradientStop { position: 1.0; color: Theme.surfaceBright }
        }
        Column {
            anchors.centerIn: parent
            width: parent.width - 24
            spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "⚠  " + qsTr("MILKDROP UNAVAILABLE")
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     22
                font.weight:        Font.Bold
                font.letterSpacing: 2
                color: Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.55)
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("This system's graphics driver doesn't support the required OpenGL version (OpenGL 3.3 Core Profile)")
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelSm
                color: Theme.fgSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── Current preset name toast ───────────────────────────────────────
    // Shows the active preset's name briefly on every switch, then fades out
    // — same convention projectM's own reference frontends use. Optional,
    // toggled via AppConfig.milkdropShowPresetName (SetupDialog's MILKDROP
    // tab). Text.Outline instead of a background Rectangle for legibility
    // over arbitrary preset visuals without adding another opaque box.
    // Also gated on isPlaying so a toast mid-fade doesn't linger visibly on
    // top of the "PAUSED" placeholder if playback pauses.
    Text {
        id: presetToast
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: Math.min(24, parent.height / 8)
        }
        width: Math.min(implicitWidth, parent.width - 16)
        elide: Text.ElideRight
        text: milkdropView.currentPresetName
        visible: opacity > 0 && view.isPlaying
        opacity: 0
        font.family:    Theme.fontFamilyBody
        font.pixelSize: Theme.titleMd
        font.weight:    Font.Bold
        color: Theme.fgSurface
        style: Text.Outline
        styleColor: "black"

        Behavior on opacity {
            NumberAnimation { duration: 1000 }
        }
    }

    Timer {
        id: presetToastHoldTimer
        interval: 5000
        repeat: false
        onTriggered: presetToast.opacity = 0
    }

    Connections {
        target: milkdropView
        function onCurrentPresetNameChanged() {
            if (view.milkdropConfig && view.milkdropConfig.milkdropShowPresetName
                && milkdropView.currentPresetName.length > 0) {
                presetToast.opacity = 1
                presetToastHoldTimer.restart()
            }
        }
    }
}
