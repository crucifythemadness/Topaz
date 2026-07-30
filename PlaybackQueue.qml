import QtQuick
import QtQuick.Controls

// Playback queue panel - shows the ordered list of upcoming tracks.
// Binds to PlaybackEngine (passed as `engine` property).
// Accepts track drops from AlbumCard via DropArea.
Rectangle {
    id: root
    property var engine: null
    // Bound from Main.qml. Gates manual add/remove/reorder (autoPlay.manualQueueEditingAllowed)
    // and the clear-queue button (autoPlay.queueClearAllowed) while an AUTO PLAY
    // session is active — see UC-16 in the architecture doc.
    property var autoPlay: null
    color: Theme.surfaceContainerLow

    // Ghost left border
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: 1
        color: Theme.ov10
    }

    // ── Panel header ──────────────────────────────────────────────────────
    Rectangle {
        id: queueHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 72
        color: Qt.rgba(Theme.surfaceContainerHigh.r,
                       Theme.surfaceContainerHigh.g,
                       Theme.surfaceContainerHigh.b, 0.30)

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.ov10
        }

        Row {
            id: titleRow
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            spacing: 8

            Text {
                text: "\u2630"
                font.pixelSize: Theme.labelLg
                color: Theme.secondary
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: qsTr("QUEUE")
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.titleMd
                font.weight:        Font.Black
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurface
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                id: playlistNameLabel
                visible: root.engine && root.engine.activePlaylistName.length > 0
                text: root.engine ? "(" + root.engine.activePlaylistName + ")" : ""
                font.family:        Theme.fontFamilyMono
                font.pixelSize:     Theme.monoLg
                font.weight:        Font.Normal
                color: Theme.fgSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter

                HoverHandler { id: playlistNameHover }
                ToolTip.visible: playlistNameHover.hovered && playlistNameLabel.visible
                ToolTip.delay:   600
                ToolTip.text:    root.engine
                                 ? qsTr("PLAYLIST ") + root.engine.activePlaylistName
                                 : ""
            }

            // Lock label — visible only when a playlist is active
            Text {
                visible: root.engine && root.engine.activePlaylistName.length > 0
                text: qsTr("LOCK")
                font.family:        Theme.fontFamilyBody
                font.pixelSize:     Theme.labelSm
                font.letterSpacing: Theme.lsWidest
                color: root.engine && root.engine.playlistLocked
                       ? Theme.secondary : Theme.fgSurfaceVariant
                anchors.verticalCenter: parent.verticalCenter
            }

            // Lock toggle — visible only when a playlist is active
            Rectangle {
                id: lockTrack
                visible: root.engine && root.engine.activePlaylistName.length > 0
                width: 32; height: 16
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: root.engine && root.engine.playlistLocked
                       ? Theme.secondary : Theme.outlineVariant

                Rectangle {
                    width: 12; height: 12
                    radius: 6
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.engine && root.engine.playlistLocked ? 16 : 2
                    color: Theme.fgSurface
                    Behavior on x { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.engine)
                            root.engine.setPlaylistLocked(!root.engine.playlistLocked)
                    }
                }

                HoverHandler { id: lockHover }
                ToolTip.visible: lockHover.hovered && lockTrack.visible
                ToolTip.delay:   600
                ToolTip.text: root.engine && root.engine.playlistLocked
                              ? qsTr("Playlist is locked \u2014 queue changes will NOT update the file")
                              : qsTr("Playlist is unlocked \u2014 queue changes update the file automatically")
            }
        }

        // Clear-queue button \u2014 only usable outside an active AUTO PLAY session
        // (MANUAL MODE); clearing during a session is always forbidden, even
        // when Allow Manual Modification is on.
        Text {
            readonly property bool clearAllowed: !root.autoPlay || root.autoPlay.queueClearAllowed
            anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
            text: "\u2715"
            font.pixelSize: Theme.labelLg
            color: clearHover.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
            visible: root.engine && root.engine.queueCount > 0 && clearAllowed
            MouseArea {
                id: clearHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    if (root.autoPlay) root.autoPlay.clearQueueAndHistory()
                    else if (root.engine) root.engine.clearQueue()
                }
            }
        }
    }

    // ── Column headers ────────────────────────────────────────────────────
    Rectangle {
        id: colHeaders
        anchors { left: parent.left; right: parent.right; top: queueHeader.bottom }
        height: 40
        color: Theme.surfaceContainerHigh

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.ov20
        }

        Row {
            anchors.fill: parent

            Text {
                width: 47; height: parent.height
                text: qsTr("#")
                font.family:        Theme.fontFamilyBody
                font.pixelSize:     Theme.labelMd
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment:   Text.AlignVCenter
            }
            Text {
                width: parent.width - 47 - 78
                height: parent.height
                text: qsTr("TRACK")
                font.family:        Theme.fontFamilyBody
                font.pixelSize:     Theme.labelMd
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurfaceVariant
                verticalAlignment:  Text.AlignVCenter
            }
            Text {
                width: 78; height: parent.height
                text: qsTr("KBPS")
                font.family:        Theme.fontFamilyBody
                font.pixelSize:     Theme.labelMd
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurfaceVariant
                horizontalAlignment: Text.AlignRight
                verticalAlignment:   Text.AlignVCenter
                rightPadding: 16
            }
        }
    }

    // ── Queue rows ────────────────────────────────────────────────────────
    Item {
        id: queueArea
        clip: true
        // Tracks an in-progress reorder drag (index = -1 means no drag active).
        property int reorderFrom: -1
        property int reorderTo:   -1
        anchors {
            left: parent.left; right: parent.right
            top: colHeaders.bottom; bottom: parent.bottom
        }

        // Scrolls so the currently-playing row is the first visible one,
        // revealing as many upcoming tracks below it as the panel can hold —
        // already-played rows scroll out of view above. Only acts when the
        // queue actually overflows the panel (a scrollbar would be showing);
        // applies regardless of AUTO PLAY/MANUAL MODE. Triggered on every
        // add/remove (see the Connections block on queueCountChanged below).
        function autoScrollToCurrent() {
            if (!root.engine) return
            if (queueList.contentHeight <= queueList.height) return
            const curIdx = root.engine.currentIndex
            if (curIdx < 0) return
            const maxY = Math.max(0, queueList.contentHeight - queueList.height)
            queueList.contentY = Math.min(curIdx * 68, maxY)   // 68 = row height (see delegate)
        }

        Connections {
            target: root.engine
            function onQueueCountChanged() { Qt.callLater(queueArea.autoScrollToCurrent) }
        }

        ListView {
            id: queueList
            anchors.fill: parent
            clip:        true
            cacheBuffer: 120

            model: root.engine

            delegate: Item {
                id: rowItem
                width:  queueList.width
                height: 68

                // Whether add/remove/reorder is currently allowed — always
                // true in MANUAL MODE (no AUTO PLAY session), otherwise
                // follows AppConfig's Allow Manual Modification setting.
                readonly property bool manualAllowed:
                    !root.autoPlay || root.autoPlay.manualQueueEditingAllowed

                // Dim this row while it is being dragged.
                opacity: queueArea.reorderFrom === index ? 0.45 : 1.0

                // Playing-now highlight
                Rectangle {
                    anchors.fill: parent
                    color: model.playing ? Theme.p10 : "transparent"
                }

                // Playing left accent
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 4
                    color: Theme.primary
                    visible: model.playing
                }

                // Hover tint for non-playing rows
                Rectangle {
                    anchors.fill: parent
                    color: Theme.surfaceContainerHighest
                    opacity: 0.4
                    visible: !model.playing && rowHover.containsMouse
                }

                // Row separator
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.ov10
                }

                Row {
                    anchors { fill: parent; leftMargin: model.playing ? 4 : 0 }
                    // z:1 ensures action-button MouseAreas (inside this Row) are hit-tested
                    // before rowHover (z:0), so they capture their own clicks without
                    // rowHover.onClicked firing first.
                    z: 1

                    // Position number
                    Text {
                        width: 47; height: parent.height
                        text: model.pos
                        font.family:    Theme.fontFamilyMono
                        font.pixelSize: Theme.monoMd
                        font.weight:    model.playing ? Font.Bold : Font.Normal
                        color: model.playing ? Theme.primary : Theme.fgSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                        // Fade out (not visible:false) so the Row width is preserved.
                        opacity: (model.playing ||
                                  !(dragHandleMA.containsMouse || queueArea.reorderFrom === index))
                                 ? 1.0 : 0.0
                    }

                    // Track name + sub-label
                    Column {
                        width: parent.width - 47 - 78 - 52
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Text {
                            width: parent.width
                            text: model.trackName
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            font.weight:    model.playing ? Font.Bold : Font.Medium
                            color: rowHover.containsMouse ? Theme.primary : Theme.fgSurface
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: model.subLabel
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.letterSpacing: 0.8
                            color: Theme.fgSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                // Move up/down buttons (hidden while playing or while manual
                // queue editing isn't allowed)
                    Column {
                        width: 20
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        visible: !model.playing && rowItem.manualAllowed

                        Text {
                            text: "\u2191"
                            font.pixelSize: 12
                            color: upHover.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                            MouseArea {
                                id: upHover; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.engine) root.engine.moveUp(index) }
                            }
                        }
                        Text {
                            text: "\u2193"
                            font.pixelSize: 12
                            color: downHover.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                            horizontalAlignment: Text.AlignHCenter
                            width: parent.width
                            MouseArea {
                                id: downHover; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { if (root.engine) root.engine.moveDown(index) }
                            }
                        }
                    }

                    // Remove button
                    Text {
                        width: 32
                        height: parent.height
                        text: "\u2715"
                        font.pixelSize: Theme.labelSm
                        color: removeHover.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                        visible: (rowHover.containsMouse || removeHover.containsMouse) && rowItem.manualAllowed
                        MouseArea {
                            id: removeHover; anchors.fill: parent
                            enabled: rowItem.manualAllowed
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (root.engine) root.engine.removeAt(index) }
                        }
                    }

                    // Bitrate
                    Text {
                        width: 78; height: parent.height
                        text: model.kbps
                        font.family:    Theme.fontFamilyMono
                        font.pixelSize: Theme.monoMd
                        font.weight:    model.playing ? Font.Medium : Font.Normal
                        color: model.playing ? Theme.secondary : Theme.fgSurfaceVariant
                        horizontalAlignment: Text.AlignRight
                        verticalAlignment:   Text.AlignVCenter
                        rightPadding: 16
                    }
                }

                MouseArea {
                    id: rowHover
                    anchors.fill: parent
                    anchors.rightMargin: 8   // leave the scrollbar thumb's column free (see UC-12)
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        var navAllowed = !root.autoPlay || root.autoPlay.trackNavigationAllowed
                        if (root.engine && !model.playing && navAllowed)
                            root.engine.playAt(index)
                    }
                }

                // ── Drag handle (non-playing rows only) ──────────────────
                // Sits at z:2 in the position-number column.
                // Uses pure mouse tracking: onPositionChanged fires even when
                // the cursor leaves the handle, as long as the button is held
                // (preventStealing: true keeps the ListView from stealing).
                // queueArea.reorderFrom/To drive the insert bar and moveTrack().
                Item {
                    id: dragHandle
                    x: 0; y: 0
                    width:  47      // matches the position-number column width
                    height: parent.height
                    z: 2
                    visible: !model.playing && rowItem.manualAllowed

                    Text {
                        anchors.centerIn: parent
                        text: "\u2807"   // ⠿ braille six-dot — drag-handle glyph
                        font.pixelSize: 14
                        visible: dragHandleMA.containsMouse || queueArea.reorderFrom === index
                        color: Theme.fgSurface
                    }

                    MouseArea {
                        id: dragHandleMA
                        anchors.fill: parent
                        hoverEnabled:    true
                        preventStealing: true
                        cursorShape: queueArea.reorderFrom >= 0
                                     ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                        onPressed: function(mouse) {
                            if (!model.playing && rowItem.manualAllowed) {
                                queueArea.reorderFrom = index
                                queueArea.reorderTo   = index
                            }
                        }

                        onPositionChanged: function(mouse) {
                            if (queueArea.reorderFrom < 0) return
                            // Map cursor into ListView content-item space.
                            // contentItem coords account for scrolling automatically.
                            var pt  = mapToItem(queueList.contentItem, mouse.x, mouse.y)
                            var cnt = root.engine ? root.engine.queueCount : 0
                            var newTo = Math.floor(pt.y / 68)
                            newTo = Math.max(0, Math.min(newTo, cnt - 1))
                            queueArea.reorderTo = newTo
                        }

                        onReleased: function(mouse) {
                            var from = queueArea.reorderFrom
                            var to   = queueArea.reorderTo
                            // Reset first so the bar disappears before the model updates
                            queueArea.reorderFrom = -1
                            queueArea.reorderTo   = -1
                            if (from >= 0 && to >= 0 && from !== to && root.engine)
                                root.engine.moveTrack(from, to)
                        }
                    }
                }
            } // delegate Item

            // Custom scrollbar — draggable thumb (see UC-12)
            Rectangle {
                id: queueScrollTrack
                z: 2   // guarantee hit-testing above delegate content, regardless of stacking order
                anchors { right: queueList.right; top: queueList.top; bottom: queueList.bottom }
                width: 4
                color: Theme.surfaceContainerLowest
                Rectangle {
                    id: queueScrollThumb
                    width:  parent.width
                    height: Math.max(24, parent.height * queueList.visibleArea.heightRatio)
                    y:      queueList.visibleArea.yPosition * parent.height
                    color:  queueThumbMA.pressed        ? Theme.secondary
                          : queueThumbMA.containsMouse   ? Theme.fgSurfaceVariant
                          :                                Theme.outlineVariant
                    radius: 2
                    visible: queueList.contentHeight > queueList.height

                    MouseArea {
                        id: queueThumbMA
                        anchors.fill: parent
                        hoverEnabled:    true
                        preventStealing: true
                        cursorShape:     Qt.PointingHandCursor

                        property real pressTrackY:   0
                        property real pressContentY: 0

                        onPressed: function(mouse) {
                            var pt = mapToItem(queueScrollTrack, mouse.x, mouse.y)
                            pressTrackY   = pt.y
                            pressContentY = queueList.contentY
                        }

                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var pt = mapToItem(queueScrollTrack, mouse.x, mouse.y)
                            var trackRange = queueScrollTrack.height - queueScrollThumb.height
                            if (trackRange <= 0) return
                            var contentRange = queueList.contentHeight - queueList.height
                            if (contentRange <= 0) return
                            var newY = pressContentY + (pt.y - pressTrackY) * (contentRange / trackRange)
                            queueList.contentY = Math.max(0, Math.min(newY, contentRange))
                        }
                    }
                }
            }
        }

        // ── Reorder insert indicator ───────────────────────────────────
        // A single 2 px bar in queueArea coordinate space showing where
        // the dragged row will land.  Row height is fixed at 68 px.
        // y = (insertIndex * 68) - contentY converts content coords to
        // view coords (same origin as queueArea since queueList fills it).
        Rectangle {
            id: insertBar
            anchors { left: parent.left; right: parent.right }
            height: 2
            color:  Theme.secondary
            z: 10
            visible: queueArea.reorderFrom >= 0 &&
                     queueArea.reorderTo   >= 0 &&
                     queueArea.reorderTo  !== queueArea.reorderFrom
            y: {
                var from = queueArea.reorderFrom
                var to   = queueArea.reorderTo
                // Moving down: bar after target row. Moving up: bar before target row.
                return (from < to ? to + 1 : to) * 68 - queueList.contentY
            }
        }

        // ── Drop target (accepts drags from AlbumCard) ────────────────────
        DropArea {
            anchors.fill: parent
            enabled: !root.autoPlay || root.autoPlay.manualQueueEditingAllowed
            keys: ["externalDrop"]   // only AlbumCard drags; ignores internal reorder

            // Highlight the panel during drag-over
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Theme.secondary.r, Theme.secondary.g,
                               Theme.secondary.b, 0.08)
                visible: parent.containsDrag
                border.color: Theme.secondary
                border.width: 1
            }

            onDropped: function(drop) {
                var src = drop.source
                if (root.engine && src && src.trackData !== undefined) {
                    root.engine.addTracks([src.trackData])
                    drop.accept(Qt.CopyAction)
                }
            }
        }

        // Empty-state hint
        Text {
            anchors.centerIn: parent
            visible: !root.engine || root.engine.queueCount === 0
            text: qsTr("Queue is empty.\nDrag tracks here or use\nthe context menu.")
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelMd
            color:          Theme.fgSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}