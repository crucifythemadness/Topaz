import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

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

    onLibChanged: {
        currentAlbums = lib ? lib.filteredAlbums() : []
        // Restore the scroll position saved from this same lib the last
        // time this view was loaded (Main.qml's Loader destroys/recreates
        // this component on every LIBRARY<->SEARCH switch). Index-based
        // (not a raw contentY pixel value) for the same reason as the
        // scrollbar drag fix below -- see UC-12: AlbumCard's content-derived
        // height makes contentHeight only an estimate until every delegate
        // is realized, so restoring a pixel value can land on a different
        // logical row than where the user actually was. Qt.callLater defers
        // past this tick so the model just assigned above has taken effect.
        if (lib) Qt.callLater(function() {
            var idx = lib.albumScrollIndex
            if (idx < 0 || idx >= albumList.count) return
            albumList.positionViewAtIndex(idx, ListView.Beginning)
            var it = albumList.itemAtIndex(idx)
            if (it) {
                var maxY = albumList.originY
                         + Math.max(0, albumList.contentHeight - albumList.height)
                albumList.contentY = Math.min(albumList.contentY + lib.albumScrollOffset, maxY)
            }
        })
    }

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

    // Re-sorts immediately when the user changes Setup > MISC's "Album
    // Browser & Search Result Sort Order" -- see UC-32. lib.appConfig is
    // already available (LibraryData.qml), so no new property plumbing
    // is needed here.
    Connections {
        target: root.lib ? root.lib.appConfig : null
        function onAlbumBrowserSortOrderChanged() { root._scheduleRefresh() }
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
            text: lib ? (root.currentAlbums.length + " ALBUMS  \u2014  " + lib.statusPath()) : ""
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
        onContentYChanged: {
            if (!root.lib) return
            var idx = albumList.indexAt(1, albumList.contentY + 1)
            if (idx < 0) return
            var it = albumList.itemAtIndex(idx)
            root.lib.albumScrollIndex  = idx
            root.lib.albumScrollOffset = it ? (albumList.contentY - it.y) : 0
        }

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
            wholeAlbumDoubleClickEnabled: true
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
            width: 8   // doubled from 4 -- easier to grab/drag with the left mouse button
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

                    // Offset of the press point inside the thumb, so it
                    // doesn't teleport under the cursor on the first move.
                    // The ONLY press-time state needed -- every move
                    // recomputes an absolute target from the cursor's
                    // absolute track position (see UC-12). Deliberately no
                    // pressContentY: contentY's own frame (originY) shifts
                    // as AlbumCard's content-derived delegate heights get
                    // (re-)estimated during the drag.
                    property real pressGrabY: 0

                    onPressed: function(mouse) {
                        pressGrabY = mouse.y
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var count = albumList.count
                        if (count <= 0) return

                        var trackRange = albumScrollTrack.height - albumScrollThumb.height
                        if (trackRange <= 0) return

                        var pt   = mapToItem(albumScrollTrack, mouse.x, mouse.y)
                        var grab = Math.min(pressGrabY, albumScrollThumb.height)
                        var frac = Math.max(0, Math.min((pt.y - grab) / trackRange, 1))

                        // Endpoints use Qt's own helpers -- real laid-out
                        // geometry, correct even when the global
                        // contentHeight estimate is off.
                        if (frac <= 0.0005) { albumList.positionViewAtBeginning(); return }
                        if (frac >= 0.9995) { albumList.positionViewAtEnd();       return }

                        // count is exact; contentHeight is only an estimate
                        // for content-derived delegate heights (AlbumCard).
                        var span = Math.max(0, count * (1 - albumList.visibleArea.heightRatio))
                        var pos  = frac * span
                        var idx  = Math.max(0, Math.min(Math.floor(pos), count - 1))
                        albumList.positionViewAtIndex(idx, ListView.Beginning)

                        // Interpolate inside the delegate just landed on, so
                        // dragging through a few tall cards stays smooth.
                        var it = albumList.itemAtIndex(idx)
                        if (it) {
                            var rem  = Math.max(0, pos - idx)
                            var maxY = albumList.originY
                                     + Math.max(0, albumList.contentHeight - albumList.height)
                            albumList.contentY =
                                Math.min(albumList.contentY + rem * (it.height + albumList.spacing),
                                         maxY)
                        }
                    }
                }
            }
        }
    }
}

