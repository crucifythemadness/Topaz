import QtQuick

// Single album card used as a delegate inside AlbumBrowser.
// Properties:
//   albumTitle    - string
//   artistLabel   - string
//   isActive      - bool   (true = primary left-accent border)
//   albumYear     - int    (0 = unknown; year label under the cover hidden)
//   albumGenre    - string (empty = hidden; shown as "Genre | Year" when set --
//                           SearchResultBrowser-only, since a genre-filtered
//                           AlbumBrowser view doesn't need it repeated per card)
//   tracks        - list<{ number, title, duration, durationMs, bitrate,
//                          filePath, artist, albumArtist, album, coverSource }>
//   coverSource   - url    (empty = show placeholder)
//   engine        - PlaybackEngine (optional; used for double-click add to queue)
//
// Interaction:
//   Drag & drop  - press and drag a track row to PlaybackQueue
//   Double-click - immediately add the track to the queue
//
// Drag mechanism: internal (same-window) drag via Drag.active.
// Drag.hotSpot is updated each frame to the actual cursor scene position so
// the DropArea in PlaybackQueue detects the drag even though trackRow never
// moves from its layout position.
Rectangle {
    id: root

    property string albumTitle:  ""
    property string artistLabel: ""
    property bool   isActive:    false
    property url    coverSource: ""
    property int    albumYear:   0   // 0 = unknown; year label hidden
    property string albumGenre:  ""  // empty = hidden; SearchResultBrowser-only
    property var    tracks:      []
    property var    engine:      null   // optional - used for double-click add to queue
    // Bound from AlbumBrowser; gates double-click add while an AUTO PLAY
    // session forbids manual modification.
    property var    autoPlay:    null

    implicitHeight: cardRow.implicitHeight + 40
    color: cardHoverHandler.hovered ? Theme.surfaceContainer : Theme.surfaceContainerLow
    radius: Theme.radiusSm

    // HoverHandler does not consume press/move events, so per-track
    // MouseAreas receive them unobstructed.
    HoverHandler { id: cardHoverHandler }

    // Left accent stripe
    Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width:  2
        radius: Theme.radiusSm
        color:  root.isActive ? Theme.primary : Theme.ov30
    }

    Row {
        id: cardRow
        anchors {
            left: parent.left; right: parent.right
            top: parent.top
            leftMargin: 20; rightMargin: 20; topMargin: 20
        }
        spacing: 24

        // Cover art + year (year sized/positioned to match PlaybackQueue's
        // "TRACK" column header: Theme.labelMd, left-aligned).
        Column {
            width: 160
            spacing: 4

            Item {
                width:  160
                height: 160
                clip:   true

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusSm
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
                        GradientStop { position: 1.0; color: Theme.surfaceBright }
                    }
                    visible: coverImg.status !== Image.Ready
                }

                Image {
                    id: coverImg
                    anchors.fill: parent
                    source: root.coverSource
                    sourceSize.width:  160
                    sourceSize.height: 160
                    fillMode:          Image.PreserveAspectCrop
                    asynchronous:      true
                    layer.enabled: true
                }
            }

            Text {
                width: 160
                text: {
                    const g = root.albumGenre
                    const y = root.albumYear > 0 ? String(root.albumYear) : ""
                    if (g && y) return g + " | " + y
                    return g || y
                }
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelMd
                color: "white"   // deliberate literal white, not a Theme.* token
            }
        }

        // Track info column
        Column {
            width: parent.width - 160 - 24
            spacing: 0

            // Album title
            Text {
                text: root.albumTitle
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.headlineMd
                font.weight:        Font.ExtraBold
                font.letterSpacing: Theme.lsTight
                color: root.isActive ? Theme.primary : Theme.fgSurface
                elide: Text.ElideRight
                width: parent.width
                bottomPadding: 4
            }

            // Artist
            Text {
                text: root.artistLabel.toUpperCase()
                font.family:        Theme.fontFamilyBody
                font.pixelSize:     Theme.labelMd
                font.weight:        Font.DemiBold
                font.letterSpacing: Theme.lsWide
                color: Theme.fgSurfaceVariant
                elide: Text.ElideRight
                width: parent.width
                bottomPadding: 20
            }

            // Track listing
            Column {
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.tracks

                    delegate: Item {
                        id: trackRow
                        width:  parent.width
                        height: 30

                        // Payload read by DropArea via drop.source.trackData
                        property var trackData: modelData

                        // Internal drag:
                        // Drag.hotSpot is updated every positionChanged to the
                        // mouse cursor's scene position relative to trackRow.
                        // This keeps the hotspot under the cursor at all times,
                        // so DropArea in PlaybackQueue fires when the user drags
                        // across - even though trackRow itself never moves.
                        Drag.supportedActions: Qt.CopyAction
                        Drag.keys:    ["externalDrop"]
                        Drag.hotSpot.x: width / 2
                        Drag.hotSpot.y: height / 2

                        // Row separator
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: index < root.tracks.length - 1 ? Theme.ov10 : "transparent"
                        }

                        // Track title
                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: modelData.number + ". " + modelData.title
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoLg
                            color: trackMA.containsMouse ? Theme.secondary : Theme.fgSurfaceVariant
                            elide: Text.ElideRight
                            width: parent.width - 60
                        }

                        // Duration
                        Text {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: modelData.duration
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoLg
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g,
                                           Theme.secondary.b, 0.6)
                        }

                        // Drag-active visual feedback: faint tint over the row
                        Rectangle {
                            anchors.fill: parent
                            color: Theme.secondary
                            opacity: trackRow.Drag.active ? 0.15 : 0.0
                        }

                        MouseArea {
                            id: trackMA
                            anchors.fill: parent
                            anchors.rightMargin: 8   // leave the scrollbar thumb's column free (see UC-12)
                            hoverEnabled: true
                            cursorShape:  dragging ? Qt.DragCopyCursor
                                                   : Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton
                            // Stop the parent ListView from stealing the gesture
                            // once we own the press.
                            preventStealing: true

                            property int  pressX:   0
                            property int  pressY:   0
                            property bool dragging: false

                            onPressed: function(mouse) {
                                pressX = mouse.x
                                pressY = mouse.y
                                dragging = false
                            }

                            onPositionChanged: function(mouse) {
                                if (!dragging && pressed &&
                                        Math.abs(mouse.x - pressX) +
                                        Math.abs(mouse.y - pressY) > 8) {
                                    dragging = true
                                    trackRow.Drag.active = true
                                    if (root.engine) root.engine.setDragCopyCursor()
                                }
                                if (dragging) {
                                    // Keep the drag hotspot directly under the
                                    // cursor by computing its position in trackRow's
                                    // coordinate space from the scene coordinates.
                                    var scenePt = mapToItem(null, mouse.x, mouse.y)
                                    var rowPt   = trackRow.mapToItem(null, 0, 0)
                                    trackRow.Drag.hotSpot.x = scenePt.x - rowPt.x
                                    trackRow.Drag.hotSpot.y = scenePt.y - rowPt.y
                                }
                            }

                            onReleased: function(mouse) {
                                if (dragging) {
                                    trackRow.Drag.drop()
                                    trackRow.Drag.active = false
                                    // Reset hotspot for next drag
                                    trackRow.Drag.hotSpot.x = trackRow.width  / 2
                                    trackRow.Drag.hotSpot.y = trackRow.height / 2
                                    dragging = false
                                    if (root.engine) root.engine.restoreOverrideCursor()
                                }
                            }

                            onDoubleClicked: function(mouse) {
                                var allowed = !root.autoPlay || root.autoPlay.manualQueueEditingAllowed
                                if (root.engine && allowed)
                                    root.engine.addTracks([modelData])
                            }
                        }
                    }
                }
            }
        }
    }
}