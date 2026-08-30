import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Informational dialog shown after loading a playlist whose tracks include
// one or more files that can no longer be found on disk (see
// PlaylistManager::loadPlaylist()'s "missing" result key, UC-10/UC-22).
// Purely informational -- the load already happened for the tracks that
// were found, and the playlist file itself was never modified.
//
// Usage:
//   MissingTracksDialog { id: missingTracksDialog }
//   missingTracksDialog.missingTracks = [...]
//   missingTracksDialog.open()
Popup {
    id: root

    // Each entry: { artist, album, title, location }
    property var missingTracks: []

    // Column widths are a fixed fraction of each RowLayout's own width
    // (see artistFrac etc. below) rather than fixed pixels/fillWidth, so
    // resizing the dialog scales all four together, preserving their
    // ratio -- LOCATION deliberately stays wider than the other three,
    // matching the original fixed-pixel layout's visual weighting.
    readonly property real artistFrac:   0.20
    readonly property real albumFrac:    0.20
    readonly property real trackFrac:    0.20
    readonly property real locationFrac: 0.40

    property int minDialogWidth:  500
    property int minDialogHeight: 300

    anchors.centerIn: Overlay.overlay
    width:  850   // 680 * 1.25
    height: 420
    padding: 0
    modal: true
    closePolicy: Popup.NoAutoClose

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    // ── Free resize (4 edges + 4 corners) ────────────────────────────────
    // Popup has no OS-level window to hand off to (unlike FloatingPane.qml's
    // Window.startSystemResize()), so width/height are tracked manually from
    // the global mouse position at press time. anchors.centerIn above
    // already keeps the dialog centered on every width/height change, so
    // there's no separate x/y bookkeeping to do (unlike FloatingPane's
    // aspect-locked-resize path, which has to compute that itself for a
    // real top-level Window).
    property real _rDragGlobalX: 0
    property real _rDragGlobalY: 0
    property real _rStartWidth:  0
    property real _rStartHeight: 0
    property int  gripSize: 8

    function beginResize(item, mouse) {
        const g = item.mapToGlobal(mouse.x, mouse.y)
        root._rDragGlobalX = g.x
        root._rDragGlobalY = g.y
        root._rStartWidth  = root.width
        root._rStartHeight = root.height
    }

    // growX/growY: -1, 0, or +1 -- which direction this grip's edge grows
    // the dialog in as the mouse moves right/down.
    function updateResize(item, mouse, growX, growY) {
        const g = item.mapToGlobal(mouse.x, mouse.y)
        if (growX !== 0)
            root.width  = Math.max(root.minDialogWidth,
                                    root._rStartWidth  + growX * (g.x - root._rDragGlobalX))
        if (growY !== 0)
            root.height = Math.max(root.minDialogHeight,
                                    root._rStartHeight + growY * (g.y - root._rDragGlobalY))
    }

    // contentItem is a plain Item (not directly the ColumnLayout) so the 8
    // resize grips below can be true siblings of it, anchored to the whole
    // popup's own bounds -- Popup's default property would otherwise route
    // bare children into whatever contentItem is, which must not be the
    // ColumnLayout itself (that only sizes to its own content, not
    // necessarily the full popup).
    contentItem: Item {
        id: contentRoot

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            Text {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: "MISSING TRACKS"
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.headlineSm
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurface
            }
        }

        // ── Explanation ──────────────────────────────────────────────────
        Text {
            Layout.fillWidth:  true
            Layout.margins:    24
            Layout.bottomMargin: 12
            text: root.missingTracks.length + " track(s) could not be found and were not"
                  + " added to the queue. The playlist file itself is unchanged."
            wrapMode: Text.Wrap
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelLg
            color: Theme.fgSurface
            lineHeight: 1.4
        }

        // ── Column header ────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth:  true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            height: 30
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusSm

            RowLayout {
                id: headerRow
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                readonly property real usableWidth: width - spacing * 3

                Text {
                    Layout.preferredWidth: headerRow.usableWidth * root.artistFrac
                    text: "ARTIST"
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelXs
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurfaceVariant
                }
                Text {
                    Layout.preferredWidth: headerRow.usableWidth * root.albumFrac
                    text: "ALBUM"
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelXs
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurfaceVariant
                }
                Text {
                    Layout.preferredWidth: headerRow.usableWidth * root.trackFrac
                    text: "TRACK"
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelXs
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurfaceVariant
                }
                Text {
                    Layout.preferredWidth: headerRow.usableWidth * root.locationFrac
                    text: "LOCATION"
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelXs
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurfaceVariant
                }
            }
        }

        // ── Missing-track list ───────────────────────────────────────────
        ScrollView {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            Layout.margins:    24
            Layout.topMargin:  8
            clip: true

            ListView {
                id: missingList
                model: root.missingTracks
                spacing: 3

                delegate: Rectangle {
                    width:  missingList.width
                    height: 32
                    radius: Theme.radiusSm
                    color:  Theme.surfaceContainer

                    RowLayout {
                        id: rowLayout
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        spacing: 8

                        readonly property real usableWidth: width - spacing * 3

                        Text {
                            Layout.preferredWidth: rowLayout.usableWidth * root.artistFrac
                            text: modelData.artist
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelMd
                            color: Theme.fgSurface
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                ToolTip.visible: containsMouse && parent.text.length > 0
                                ToolTip.text:    parent.text
                                ToolTip.delay:   600
                            }
                        }
                        Text {
                            Layout.preferredWidth: rowLayout.usableWidth * root.albumFrac
                            text: modelData.album
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelMd
                            color: Theme.fgSurface
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                ToolTip.visible: containsMouse && parent.text.length > 0
                                ToolTip.text:    parent.text
                                ToolTip.delay:   600
                            }
                        }
                        Text {
                            Layout.preferredWidth: rowLayout.usableWidth * root.trackFrac
                            text: modelData.title
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelMd
                            color: Theme.fgSurface
                            elide: Text.ElideRight

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                ToolTip.visible: containsMouse && parent.text.length > 0
                                ToolTip.text:    parent.text
                                ToolTip.delay:   600
                            }
                        }
                        Text {
                            Layout.preferredWidth: rowLayout.usableWidth * root.locationFrac
                            text: modelData.location
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoSm
                            color: Theme.fgSurfaceVariant
                            elide: Text.ElideMiddle

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                ToolTip.visible: containsMouse && parent.text.length > 0
                                ToolTip.text:    parent.text
                                ToolTip.delay:   600
                            }
                        }
                    }
                }
            }
        }

        // ── Close button row ─────────────────────────────────────────────
        Item {
            Layout.fillWidth:    true
            Layout.bottomMargin: 20
            height: 36

            Rectangle {
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                width: 100; height: 36
                radius: Theme.radiusSm
                color: closeHover.containsMouse ? Theme.primaryContainer
                                                 : Theme.surfaceContainerHigh

                Text {
                    anchors.centerIn: parent
                    text: "CLOSE"
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: closeHover.containsMouse ? Theme.fgPrimaryContainer : Theme.primary
                }

                MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    root.close()
                }
            }
        }
        } // end ColumnLayout

        // ── Resize grips (4 edges + 4 corners) ───────────────────────────
        // Siblings of the ColumnLayout above within contentRoot, anchored
        // to contentRoot's own bounds (== the whole popup, since padding
        // is 0) rather than to the ColumnLayout's, which only sizes to its
        // own content.
        MouseArea {
            id: topGrip
            anchors { top: parent.top; left: parent.left; right: parent.right
                      leftMargin: root.gripSize; rightMargin: root.gripSize }
            height: root.gripSize
            cursorShape: Qt.SizeVerCursor
            onPressed: (mouse) => root.beginResize(topGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(topGrip, mouse, 0, -1) }
        }
        MouseArea {
            id: bottomGrip
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                      leftMargin: root.gripSize; rightMargin: root.gripSize }
            height: root.gripSize
            cursorShape: Qt.SizeVerCursor
            onPressed: (mouse) => root.beginResize(bottomGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(bottomGrip, mouse, 0, 1) }
        }
        MouseArea {
            id: leftGrip
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                      topMargin: root.gripSize; bottomMargin: root.gripSize }
            width: root.gripSize
            cursorShape: Qt.SizeHorCursor
            onPressed: (mouse) => root.beginResize(leftGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(leftGrip, mouse, -1, 0) }
        }
        MouseArea {
            id: rightGrip
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom
                      topMargin: root.gripSize; bottomMargin: root.gripSize }
            width: root.gripSize
            cursorShape: Qt.SizeHorCursor
            onPressed: (mouse) => root.beginResize(rightGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(rightGrip, mouse, 1, 0) }
        }
        MouseArea {
            id: topLeftGrip
            anchors { top: parent.top; left: parent.left }
            width: root.gripSize; height: root.gripSize
            cursorShape: Qt.SizeFDiagCursor
            onPressed: (mouse) => root.beginResize(topLeftGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(topLeftGrip, mouse, -1, -1) }
        }
        MouseArea {
            id: bottomRightGrip
            anchors { bottom: parent.bottom; right: parent.right }
            width: root.gripSize; height: root.gripSize
            cursorShape: Qt.SizeFDiagCursor
            onPressed: (mouse) => root.beginResize(bottomRightGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(bottomRightGrip, mouse, 1, 1) }
        }
        MouseArea {
            id: topRightGrip
            anchors { top: parent.top; right: parent.right }
            width: root.gripSize; height: root.gripSize
            cursorShape: Qt.SizeBDiagCursor
            onPressed: (mouse) => root.beginResize(topRightGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(topRightGrip, mouse, 1, -1) }
        }
        MouseArea {
            id: bottomLeftGrip
            anchors { bottom: parent.bottom; left: parent.left }
            width: root.gripSize; height: root.gripSize
            cursorShape: Qt.SizeBDiagCursor
            onPressed: (mouse) => root.beginResize(bottomLeftGrip, mouse)
            onPositionChanged: (mouse) => { if (pressed) root.updateResize(bottomLeftGrip, mouse, -1, 1) }
        }
    } // end contentItem: Item
}
