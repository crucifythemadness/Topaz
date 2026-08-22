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
    // itself doesn't change while the view stays loaded. Qt.callLater
    // defers past this tick so contentHeight has caught up with
    // currentAlbums first -- setting contentY immediately can get clamped
    // back to 0.
    onSearchDataChanged: {
        if (searchData) Qt.callLater(function() { resultList.contentY = searchData.resultScrollY })
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
        onContentYChanged: if (root.searchData) root.searchData.resultScrollY = contentY

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

                    property real pressTrackY:   0
                    property real pressContentY: 0

                    onPressed: function(mouse) {
                        var pt = mapToItem(resultScrollTrack, mouse.x, mouse.y)
                        pressTrackY   = pt.y
                        pressContentY = resultList.contentY
                    }

                    onPositionChanged: function(mouse) {
                        if (!pressed) return
                        var pt = mapToItem(resultScrollTrack, mouse.x, mouse.y)
                        var trackRange = resultScrollTrack.height - resultScrollThumb.height
                        if (trackRange <= 0) return
                        var contentRange = resultList.contentHeight - resultList.height
                        if (contentRange <= 0) return
                        var newY = pressContentY + (pt.y - pressTrackY) * (contentRange / trackRange)
                        resultList.contentY = Math.max(0, Math.min(newY, contentRange))
                    }
                }
            }
        }
    }
}
