import QtQuick
import QtQuick.Controls

// Replaces AlbumBrowser/SearchResultBrowser in the same SplitView slot when
// TopBar's PLAYLISTS tab is active (see Main.qml's Loader). Unlike
// AlbumBrowser/SearchResultBrowser, cards here are never grouped by album --
// LibraryModel.buildStandaloneTrackCards() returns one standalone,
// AlbumCard-shaped entry per track (same shape filteredAlbums()/
// searchLibrary() use, just one track each), in playlist order, so the
// playlist's actual track-by-track composition stays visible even when
// several tracks from the same album are adjacent. AlbumCard itself needs
// no changes -- see UC-22.
Rectangle {
    id: root
    property PlaylistsData playlistsData: null
    property var engine:   null
    property var autoPlay: null
    color: Theme.surface

    // Emitted after LOAD when the just-loaded playlist had tracks whose file
    // couldn't be found -- Main.qml opens MissingTracksDialog. See UC-22.
    signal missingPlaylistTracks(var missingTracks)

    readonly property var currentAlbums: playlistsData ? playlistsData.albums : []

    // Restore the scroll position saved from this same playlistsData the
    // last time this view was loaded (Main.qml's Loader destroys/recreates
    // this component on every PLAYLISTS<->LIBRARY/SEARCH switch) -- fires
    // once per (re)creation, not on every new playlist selection, since
    // playlistsData itself doesn't change while the view stays loaded.
    // Qt.callLater defers past this tick so contentHeight has caught up
    // with currentAlbums first -- setting contentY immediately can get
    // clamped back to 0.
    onPlaylistsDataChanged: {
        if (playlistsData) Qt.callLater(function() { resultList.contentY = playlistsData.resultScrollY })
    }

    // ── Header -- LOAD button instead of a title label (see UC-22) ────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 72

        Rectangle {
            id: loadBtn
            anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
            width:  140
            height: 44
            radius: Theme.radiusSm

            // Also active when there's nothing loadable but something to
            // *report* -- a playlist whose tracks are all missing should
            // still let LOAD explain why, rather than being permanently
            // disabled with no feedback. See UC-22.
            readonly property bool active: root.playlistsData
                                            && (root.playlistsData.selectedRawTracks.length > 0
                                                || root.playlistsData.selectedMissingTracks.length > 0)
                                            && (!root.autoPlay || root.autoPlay.queueClearAllowed)

            color:  active && loadHover.containsMouse ? Theme.surfaceContainerHigh
                                                       : Theme.surfaceContainer
            border.color: Theme.ov20
            border.width: 1
            opacity: active ? 1.0 : 0.35

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↑"
                    font.pixelSize: Theme.titleMd
                    color: Theme.fgSurfaceVariant
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("LOAD")
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelLg
                    font.weight:        Font.Medium
                    font.letterSpacing: Theme.lsWide
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: loadHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: loadBtn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!loadBtn.active) return
                    const tracks         = root.playlistsData ? root.playlistsData.selectedRawTracks : []
                    const missing        = root.playlistsData ? root.playlistsData.selectedMissingTracks : []
                    const loadedFileName = root.playlistsData ? root.playlistsData.selectedFileName   : ""
                    if (root.engine && tracks.length > 0) {
                        // loadPlaylistTracks() always replaces the queue --
                        // it crossfades into the new playlist when CROSSFADE
                        // is on and something is currently playing,
                        // otherwise it's an instant replace (see UC-23).
                        if (root.autoPlay) root.autoPlay.clearHistory()
                        root.engine.loadPlaylistTracks(tracks)
                        root.engine.setActivePlaylistName(loadedFileName)
                    }
                    if (root.playlistsData) root.playlistsData.selectNeighborOf(loadedFileName)
                    if (missing.length > 0) root.missingPlaylistTracks(missing)
                }

                ToolTip.visible: containsMouse && loadBtn.active
                ToolTip.delay:   600
                ToolTip.text:    qsTr("LOAD PLAYLIST")
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 20 }
            spacing: 4

            readonly property int offlineCount:
                root.playlistsData ? root.playlistsData.selectedMissingTracks.length : 0

            Text {
                text: (playlistsData && playlistsData.selectedFileName !== "")
                      ? (_trackCount(root.currentAlbums) + " TRACKS  —  "
                         + playlistsData.selectedDisplayName.toUpperCase())
                      : ""
                font.family:        Theme.fontFamilyMono
                font.pixelSize:     Theme.monoSm
                font.letterSpacing: 1.5
                color: Theme.fgSurfaceVariant
            }
            Text {
                visible: parent.offlineCount > 0
                text: "|"
                font.family:        Theme.fontFamilyMono
                font.pixelSize:     Theme.monoSm
                font.letterSpacing: 1.5
                color: Theme.fgSurfaceVariant
            }
            Text {
                visible: parent.offlineCount > 0
                text: parent.offlineCount + " OFFLINE"
                font.family:        Theme.fontFamilyMono
                font.pixelSize:     Theme.monoSm
                font.letterSpacing: 1.5
                color: Theme.error
            }
        }
    }

    function _trackCount(albums) {
        let n = 0
        for (let i = 0; i < albums.length; i++) n += albums[i].tracks.length
        return n
    }

    // ── Track list ───────────────────────────────────────────────────────
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
        onContentYChanged: if (root.playlistsData) root.playlistsData.resultScrollY = contentY

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
            text:     qsTr("Select a playlist to preview its tracks.")
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
