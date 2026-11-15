import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
import QtQuick.Controls

// A dock area in one of Main.qml's dock columns (UC-38): the vertical
// queueColumn SplitView (above / below the playback queue) or
// nowPlayingColumn (below Now Playing). Two roles, chosen by Main.qml:
//
// - Free area (dockHost unset): the zone's single empty area, created when the
//   user drags it open. A subtle placeholder -- a faint dashed outline and a
//   small hint, both hidden while the area is too thin to hold them, so a
//   sliver stays clean.
// - Dock slot (dockHost + zone + slotIndex set): shows the pane at position
//   slotIndex of dockHost.dockZones[zone], loaded from dockHost.dockablePanes;
//   invisible (no SplitView handle, no cost) while that position is empty.
//   Hovering shows small buttons in the top-right corner -- move up / move
//   down (swap with the neighbour in the same zone, only when there is one),
//   "float again" and "close" -- and a right-click closes the pane, like on a
//   floating pane. A "fixed" pane (registry flag, e.g. the playlist buttons)
//   can't float or close: instead of those two it gets one "move to" button
//   per other zone that has room, and right-click does nothing. A left press
//   selects the pane (turquoise outline, like a floating pane's, via
//   dockHost.selectDockPane()); while a handle of the column is dragged every
//   docked pane shows the outline, so its edges are visible while resizing.
//   What all these requests do is up to dockHost (Main.qml).
Rectangle {
    id: root

    color: Theme.surfaceContainerLow     // same surface as PlaybackQueue

    property var    dockHost: null       // Main.qml's root (dockZones, dockablePanes, ...)
    property string zone: ""
    property int    slotIndex: -1

    readonly property bool   isSlot: dockHost !== null && zone !== ""
    readonly property var    zoneList: isSlot ? (dockHost.dockZones[zone] || []) : []
    readonly property string paneId: (isSlot && slotIndex >= 0 && slotIndex < zoneList.length)
                                     ? zoneList[slotIndex] : ""
    readonly property var    paneEntry: paneId !== "" ? dockHost.dockablePanes[paneId] : null

    // The docked pane's content component, or null when the area is empty.
    readonly property Component paneComponent: paneEntry ? paneEntry.component : null
    readonly property bool occupied: paneComponent !== null
    readonly property bool fixedPane: paneEntry !== null && paneEntry.fixed === true

    // Zone lists run from the host (queue / Now Playing) outwards, so in the
    // zones above a host a higher index is further UP on screen.
    readonly property bool topZone: zone.endsWith("Top")
    readonly property bool hasInner: occupied && slotIndex > 0
    readonly property bool hasOuter: occupied && slotIndex < zoneList.length - 1
    readonly property bool canMoveUp:   topZone ? hasOuter : hasInner
    readonly property bool canMoveDown: topZone ? hasInner : hasOuter

    // Selection outline: selected by a click, or the column is being resized.
    // qmllint disable missing-property
    readonly property bool columnResizing: SplitView.view ? SplitView.view.resizing : false
    // qmllint enable missing-property
    readonly property bool outlined: occupied && (columnResizing || dockHost.selectedDockPane === paneId)

    // Free areas: Main.qml hides a column's free areas while the column is
    // full (no FREE SPACE that nothing could be docked into). Hidden = no
    // SplitView handle to drag it open; its space goes back to the host.
    property bool freeAllowed: true
    visible: isSlot ? occupied : freeAllowed
    onVisibleChanged: if (!isSlot && !visible) SplitView.preferredHeight = 0
    // A docked pane can't be squeezed below its own minimum
    SplitView.minimumHeight: paneEntry ? paneEntry.minDockHeight : 0

    signal undockRequested()
    signal closeRequested()
    signal moveRequested(int dir)        // on screen: -1 = up, +1 = down
    signal moveToZoneRequested(string target)   // fixed panes: to another zone
    onUndockRequested: if (isSlot) dockHost.undockPane(paneId)
    onCloseRequested:  if (isSlot) dockHost.closePane(paneId)
    onMoveRequested: (dir) => { if (isSlot) dockHost.swapDocked(paneId, dir) }
    onMoveToZoneRequested: (target) => { if (isSlot) dockHost.moveDocked(paneId, target) }

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
        enabled: root.occupied && !root.fixedPane
        acceptedButtons: Qt.RightButton
        onTapped: root.closeRequested()
    }

    // Left press anywhere selects the pane (outline). Passive: the docked
    // content still gets every press and click.
    PointHandler {
        enabled: root.occupied
        acceptedButtons: Qt.LeftButton
        onActiveChanged: if (active) root.dockHost.selectDockPane(root.paneId)
    }

    // Selection outline, the same as FloatingPane's: above the content and
    // the buttons, takes no mouse input.
    Rectangle {
        anchors.fill: parent
        z: 20
        visible: root.outlined
        color: "transparent"
        border.width: 2
        border.color: Theme.secondary
    }

    // Hover: the area's own HoverHandler OR one of the buttons (a hovered
    // button may take the hover away from what is beneath it), with a short
    // grace period so moving onto a button never flickers.
    HoverHandler { id: areaHover; enabled: root.occupied }
    readonly property bool _hover: areaHover.hovered || upBtn.hovered || downBtn.hovered
                                   || undockBtn.hovered || closeBtn.hovered
                                   || toQueueTopBtn.hovered || toQueueBottomBtn.hovered
                                   || toNowPlayingTopBtn.hovered || toNowPlayingBottomBtn.hovered
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
                id: upBtn
                buttonSize: 28
                visible: root.canMoveUp
                iconName: "move-up"
                tooltip: qsTr("Move up (swap with the pane above)")
                onClicked: root.moveRequested(-1)
            }
            IconButton {
                id: downBtn
                buttonSize: 28
                visible: root.canMoveDown
                iconName: "move-down"
                tooltip: qsTr("Move down (swap with the pane below)")
                onClicked: root.moveRequested(1)
            }
            // Fixed panes: move to another zone (only where it fits)
            IconButton {
                id: toQueueTopBtn
                buttonSize: 28
                visible: root.fixedPane && root.dockHost.canMoveTo(root.paneId, "queueTop")
                iconName: "dock-top"
                tooltip: qsTr("Move above the queue")
                onClicked: root.moveToZoneRequested("queueTop")
            }
            IconButton {
                id: toQueueBottomBtn
                buttonSize: 28
                visible: root.fixedPane && root.dockHost.canMoveTo(root.paneId, "queueBottom")
                iconName: "dock-bottom"
                tooltip: qsTr("Move below the queue")
                onClicked: root.moveToZoneRequested("queueBottom")
            }
            IconButton {
                id: toNowPlayingTopBtn
                buttonSize: 28
                visible: root.fixedPane && root.dockHost.canMoveTo(root.paneId, "nowPlayingTop")
                iconName: "dock-nowplaying-top"
                tooltip: qsTr("Move above Now Playing")
                onClicked: root.moveToZoneRequested("nowPlayingTop")
            }
            IconButton {
                id: toNowPlayingBottomBtn
                buttonSize: 28
                visible: root.fixedPane && root.dockHost.canMoveTo(root.paneId, "nowPlayingBottom")
                iconName: "dock-nowplaying-bottom"
                tooltip: qsTr("Move below Now Playing")
                onClicked: root.moveToZoneRequested("nowPlayingBottom")
            }
            IconButton {
                id: undockBtn
                buttonSize: 28
                visible: !root.fixedPane
                iconName: "undock"
                tooltip: qsTr("Float as a separate window")
                onClicked: root.undockRequested()
            }
            IconButton {
                id: closeBtn
                buttonSize: 28
                visible: !root.fixedPane
                iconName: "close"
                danger: true
                tooltip: qsTr("Close")
                onClicked: root.closeRequested()
            }
        }
    }
}
