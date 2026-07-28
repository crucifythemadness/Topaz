import QtQuick

// Album card list — driven by lib.filteredAlbums().
// Refreshes whenever lib.activeGenreNames, lib.selectedArtist, or
// lib.selectedAlbum changes via Connections.
Rectangle {
    id: root
    property var lib: null
    property var engine: null
    // Bound from Main.qml; forwarded to each AlbumCard delegate so double-click
    // add can be gated by autoPlay.manualQueueEditingAllowed.
    property var autoPlay: null
    color: Theme.surface

    // ── Filtered album list ───────────────────────────────────────────────
    property var currentAlbums: []

    onLibChanged: currentAlbums = lib ? lib.filteredAlbums() : []

    // Use Qt.callLater so the LibraryTree (and the rest of the current frame)
    // can render before the potentially heavy filteredAlbums() call is made.
    // This keeps the genre-click interaction feeling instant even on large libraries.
    function _scheduleRefresh() {
        Qt.callLater(function() {
            root.currentAlbums = root.lib ? root.lib.filteredAlbums() : []
        })
    }

    Connections {
        target: lib
        function onActiveGenreNamesChanged() { root._scheduleRefresh() }
        function onSelectedGenreChanged()    { root._scheduleRefresh() }
        function onSelectedArtistChanged()   { root._scheduleRefresh() }
        function onSelectedAlbumChanged()    { root._scheduleRefresh() }
    }

    // ── Header ────────────────────────────────────────────────────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 72

        Text {
            anchors { left: parent.left; leftMargin: 32; bottom: parent.bottom; bottomMargin: 16 }
            text: qsTr("ALBUM BROWSER")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     Theme.headlineLg
            font.weight:        Font.Black
            font.letterSpacing: Theme.lsTight
            color: Theme.fgSurface
        }

        Text {
            anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 20 }
            text: lib ? (root.currentAlbums.length + " ITEMS  \u2014  " + lib.statusPath()) : ""
            font.family:        Theme.fontFamilyMono
            font.pixelSize:     Theme.monoSm
            font.letterSpacing: 1.5
            color: Theme.fgSurfaceVariant
        }
    }

    // ── Album list ───────────────────────────────────────────────────
    ListView {
        id: albumList
        anchors {
            left: parent.left; right: parent.right
            top: header.bottom; bottom: parent.bottom
            leftMargin: 24; rightMargin: 24
            bottomMargin: 16
        }
        clip:        true
        spacing:     24
        cacheBuffer: 200

        model: root.currentAlbums

        delegate: AlbumCard {
            width:       albumList.width
            albumTitle:  modelData.albumTitle
            artistLabel: modelData.artistLabel
            isActive:    modelData.isActive
            coverSource: modelData.coverSource ?? ""
            albumYear:   modelData.year ?? 0
            tracks:      modelData.tracks
            engine:      root.engine
            autoPlay:    root.autoPlay
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            visible:  albumList.count === 0
            text:     qsTr("No albums to show.\nActivate a genre or select an artist.")
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelMd
            color:          Theme.fgSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Custom scrollbar — draggable thumb (see UC-12)
        Rectangle {
            id: albumScrollTrack
            z: 2   // guarantee hit-testing above delegate content, regardless of stacking order
            anchors { right: albumList.right; top: albumList.top; bottom: albumList.bottom }
            width: 4
            color: Theme.surfaceContainerLowest
            Rectangle {
                id: albumScrollThumb
                width:  parent.width
                height: Math.max(24, parent.height * albumList.visibleArea.heightRatio)
                y:      albumList.visibleArea.yPosition * parent.height
                color:  albumThumbMA.pressed        ? Theme.secondary
                      : albumThumbMA.containsMouse   ? Theme.fgSurfaceVariant
                      :                                Theme.outlineVariant
                radius: 2
                visible: albumList.contentHeight > albumList.height

                MouseArea {
                    id: albumThumbMA
                    anchors.fill: parent
                    hoverEnabled:    true
                    preventStealing: true
                    cursorShape:     Qt.PointingHandCursor

                    property real pressTrackY:   0
                    property real pressContentY: 0

                    onPressed: function(mouse) {
                        var pt = mapToItem(albumScrollTrack, mouse.x, mouse.y)
                        pressTrackY   = pt.y
                        pressContentY = albumList.contentY
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var pt = mapToItem(albumScrollTrack, mouse.x, mouse.y)
                        var trackRange = albumScrollTrack.height - albumScrollThumb.height
                        if (trackRange <= 0) return
                        var contentRange = albumList.contentHeight - albumList.height
                        if (contentRange <= 0) return
                        var newY = pressContentY + (pt.y - pressTrackY) * (contentRange / trackRange)
                        albumList.contentY = Math.max(0, Math.min(newY, contentRange))
                    }
                }
            }
        }
    }
}

