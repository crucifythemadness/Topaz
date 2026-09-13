import QtQuick

// Replaces AlbumBrowser in the same SplitView slot when TopBar's SEARCH tab
// is active (see Main.qml's Loader). Same album-card grid/drag-to-queue
// behavior as AlbumBrowser, but driven by SearchData.results instead of
// lib.filteredAlbums() -- entirely independent of LibraryData. AlbumCard
// itself needs no changes: searchLibrary() returns the identical per-album/
// per-track object shape filteredAlbums() does.
Rectangle {
    id: root
    property SearchData searchData: null
    property var engine: null
    property var autoPlay: null
    color: Theme.surface

    readonly property var currentAlbums: searchData ? searchData.results : []

    // Restore the scroll position saved from this same searchData the last
    // time this view was loaded (Main.qml's Loader destroys/recreates this
    // component on every SEARCH<->LIBRARY switch) -- fires once per
    // (re)creation, not on every new search result set, since searchData
    // itself doesn't change while the view stays loaded. Index-based (not a
    // raw contentY pixel value) for the same reason as the scrollbar drag
    // fix below -- see UC-12: AlbumCard's content-derived height makes
    // contentHeight only an estimate until every delegate is realized, so
    // restoring a pixel value can land on a different logical row than
    // where the user actually was. Qt.callLater defers past this tick so
    // currentAlbums has taken effect.
    onSearchDataChanged: {
        if (!searchData) return
        Qt.callLater(function() {
            var idx = searchData.resultScrollIndex
            if (idx < 0 || idx >= resultList.count) return
            resultList.positionViewAtIndex(idx, ListView.Beginning)
            var it = resultList.itemAtIndex(idx)
            if (it) {
                var maxY = resultList.originY
                         + Math.max(0, resultList.contentHeight - resultList.height)
                resultList.contentY = Math.min(resultList.contentY + searchData.resultScrollOffset, maxY)
            }
        })
    }

    // ── Header ────────────────────────────────────────────────────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 72

        Text {
            anchors { left: parent.left; leftMargin: 32; bottom: parent.bottom; bottomMargin: 16 }
            text: qsTr("SEARCH RESULT")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     Theme.headlineLg
            font.weight:        Font.Black
            font.letterSpacing: Theme.lsTight
            color: Theme.fgSurface
        }

        Text {
            anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 20 }
            text: (searchData && searchData.query.trim().length > 0)
                  ? (root.currentAlbums.length + " ITEMS  —  "
                     + searchData.mode.toUpperCase() + ": " + searchData.query.trim())
                  : ""
            font.family:        Theme.fontFamilyMono
            font.pixelSize:     Theme.monoSm
            font.letterSpacing: 1.5
            color: Theme.fgSurfaceVariant
        }
    }

    // ── Result list ──────────────────────────────────────────────────
    ListView {
        id: resultList
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
            if (!root.searchData) return
            var idx = resultList.indexAt(1, resultList.contentY + 1)
            if (idx < 0) return
            var it = resultList.itemAtIndex(idx)
            root.searchData.resultScrollIndex  = idx
            root.searchData.resultScrollOffset = it ? (resultList.contentY - it.y) : 0
        }

        model: root.currentAlbums

        delegate: AlbumCard {
            width:       resultList.width
            albumTitle:  modelData.albumTitle
            artistLabel: modelData.artistLabel
            isActive:    modelData.isActive
            coverSource: modelData.coverSource ?? ""
            albumYear:   modelData.year ?? 0
            albumGenre:  modelData.genre ?? ""
            tracks:      modelData.tracks
            engine:      root.engine
            autoPlay:    root.autoPlay
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            visible:  resultList.count === 0
            text:     (searchData && searchData.query.trim().length > 0)
                      ? qsTr("No matches for the current search.")
                      : qsTr("Type a query to search your library.")
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelMd
            color:          Theme.fgSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }

        // Custom scrollbar — draggable thumb (see UC-12)
        Rectangle {
            id: resultScrollTrack
            z: 2   // guarantee hit-testing above delegate content, regardless of stacking order
            anchors { right: resultList.right; top: resultList.top; bottom: resultList.bottom }
            width: 4
            color: Theme.surfaceContainerLowest
            Rectangle {
                id: resultScrollThumb
                width:  parent.width
                height: Math.max(24, parent.height * resultList.visibleArea.heightRatio)
                y:      resultList.visibleArea.yPosition * parent.height
                color:  resultThumbMA.pressed        ? Theme.secondary
                      : resultThumbMA.containsMouse   ? Theme.fgSurfaceVariant
                      :                                 Theme.outlineVariant
                radius: 2
                visible: resultList.contentHeight > resultList.height

                MouseArea {
                    id: resultThumbMA
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
                        var count = resultList.count
                        if (count <= 0) return

                        var trackRange = resultScrollTrack.height - resultScrollThumb.height
                        if (trackRange <= 0) return

                        var pt   = mapToItem(resultScrollTrack, mouse.x, mouse.y)
                        var grab = Math.min(pressGrabY, resultScrollThumb.height)
                        var frac = Math.max(0, Math.min((pt.y - grab) / trackRange, 1))

                        // Endpoints use Qt's own helpers -- real laid-out
                        // geometry, correct even when the global
                        // contentHeight estimate is off.
                        if (frac <= 0.0005) { resultList.positionViewAtBeginning(); return }
                        if (frac >= 0.9995) { resultList.positionViewAtEnd();       return }

                        // count is exact; contentHeight is only an estimate
                        // for content-derived delegate heights (AlbumCard).
                        var span = Math.max(0, count * (1 - resultList.visibleArea.heightRatio))
                        var pos  = frac * span
                        var idx  = Math.max(0, Math.min(Math.floor(pos), count - 1))
                        resultList.positionViewAtIndex(idx, ListView.Beginning)

                        // Interpolate inside the delegate just landed on, so
                        // dragging through a few tall cards stays smooth.
                        var it = resultList.itemAtIndex(idx)
                        if (it) {
                            var rem  = Math.max(0, pos - idx)
                            var maxY = resultList.originY
                                     + Math.max(0, resultList.contentHeight - resultList.height)
                            resultList.contentY =
                                Math.min(resultList.contentY + rem * (it.height + resultList.spacing),
                                         maxY)
                        }
                    }
                }
            }
        }
    }
}
