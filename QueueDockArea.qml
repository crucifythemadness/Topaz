import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// Free area above or below the playback queue (Main.qml's vertical
// queueColumn SplitView). Created when the user drags the queue smaller from
// the top or the bottom. A pane (Audio Meter, Audio Visualizer, Milkdrop, ...)
// can be docked into it (UC-38): Main.qml sets paneComponent (the pane's
// content view from its dockablePanes registry) and this item loads it.
//
// Empty: a subtle placeholder -- a faint dashed outline and a small hint,
// both hidden while the area is too thin to hold them, so a sliver stays clean.
// Occupied: the pane fills the area; hovering shows two small buttons in the
// top-right corner ("float again" / "close"), and a right-click closes the
// pane, like on a floating pane. Generic: what those requests mean is up to
// Main.qml (undockRequested / closeRequested).
Rectangle {
    id: root

    color: Theme.surfaceContainerLow     // same surface as PlaybackQueue

    // The docked pane's content component, or null when the area is empty.
    property Component paneComponent: null
    readonly property bool occupied: paneComponent !== null

    signal undockRequested()
    signal closeRequested()

    readonly property bool roomy: height >= 48

    // ── Empty: placeholder ────────────────────────────────────────────────
    Canvas {
        id: outline
        anchors.fill: parent
        anchors.margins: 8
        visible: root.roomy && !root.occupied

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const r = 8
            const w = width - 1, h = height - 1
            ctx.lineWidth = 1
            ctx.strokeStyle = Theme.outlineVariant
            ctx.setLineDash([6, 5])
            ctx.beginPath()
            ctx.moveTo(0.5 + r, 0.5)
            ctx.lineTo(w - r, 0.5)
            ctx.arcTo(w, 0.5, w, 0.5 + r, r)
            ctx.lineTo(w, h - r)
            ctx.arcTo(w, h, w - r, h, r)
            ctx.lineTo(0.5 + r, h)
            ctx.arcTo(0.5, h, 0.5, h - r, r)
            ctx.lineTo(0.5, 0.5 + r)
            ctx.arcTo(0.5, 0.5, 0.5 + r, 0.5, r)
            ctx.closePath()
            ctx.stroke()
        }
    }

    Column {
        anchors.centerIn: parent
        width: parent.width - 24
        spacing: 2
        visible: root.roomy && !root.occupied

        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: qsTr("FREE SPACE")
            font.family:        Theme.fontFamilyBody
            font.pixelSize:     Theme.labelSm
            font.weight:        Font.Bold
            font.letterSpacing: Theme.lsWidest
            color: Theme.fgSurfaceVariant
            opacity: 0.7
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.height >= 72
            text: qsTr("Hover over a pane and use its dock buttons to dock it here")
            elide: Text.ElideRight
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelSm
            color: Theme.fgSurfaceVariant
            opacity: 0.5
        }
    }

    // ── Occupied: the docked pane ─────────────────────────────────────────
    Loader {
        id: paneLoader
        anchors.fill: parent
        active: root.occupied
        sourceComponent: root.paneComponent
    }

    // Right-click closes, like a floating pane. A handler, not a MouseArea:
    // it must not take hover or left clicks away from the docked content.
    TapHandler {
        enabled: root.occupied
        acceptedButtons: Qt.RightButton
        onTapped: root.closeRequested()
    }

    // Hover: the area's own HoverHandler OR one of the buttons (a hovered
    // button may take the hover away from what is beneath it), with a short
    // grace period so moving onto a button never flickers.
    HoverHandler { id: areaHover; enabled: root.occupied }
    readonly property bool _hover: areaHover.hovered || undockBtn.hovered || closeBtn.hovered
    property bool _buttonsShown: false
    on_HoverChanged: {
        if (_hover) {
            hideTimer.stop()
            _buttonsShown = true
        } else {
            hideTimer.restart()
        }
    }
    Timer {
        id: hideTimer
        interval: 600
        onTriggered: root._buttonsShown = false
    }

    Rectangle {
        anchors { top: parent.top; right: parent.right; topMargin: 6; rightMargin: 6 }
        z: 10
        width: btnRow.implicitWidth + 8
        height: btnRow.implicitHeight + 8
        radius: Theme.radiusMd
        color: Qt.rgba(Theme.surfaceContainerLowest.r, Theme.surfaceContainerLowest.g,
                       Theme.surfaceContainerLowest.b, 0.85)
        border.width: 1
        border.color: Theme.outlineVariant
        visible: opacity > 0
        opacity: (root.occupied && root._buttonsShown) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }

        Row {
            id: btnRow
            anchors.centerIn: parent
            spacing: 2
            IconButton {
                id: undockBtn
                buttonSize: 28
                iconName: "undock"
                tooltip: qsTr("Float as a separate window")
                onClicked: root.undockRequested()
            }
            IconButton {
                id: closeBtn
                buttonSize: 28
                iconName: "close"
                danger: true
                tooltip: qsTr("Close")
                onClicked: root.closeRequested()
            }
        }
    }
}
