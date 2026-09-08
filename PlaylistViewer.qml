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
    // Emitted when the user clicks EXPORT with a playlist selected --
    // Main.qml opens ExportPlaylistDialog with playlistsData.selectedRawTracks,
    // NOT the current playback queue (the selected playlist and whatever is
    // currently playing are routinely different playlists). See UC-26.
    signal exportPlaylistRequested()

    // Live mirror of the queue's own contents, kept in sync via the
    // Connections block below -- only actually used while previewing the
    // active playlist (see currentRawTracks/currentAlbums). Populated
    // imperatively, never by a binding: engine.trackList() is
    // Q_INVOKABLE, not a NOTIFY-backed Q_PROPERTY, so a declarative
    // binding on it would freeze at first paint and never update again
    // (the documented QML invokable-binding gotcha).
    property var _liveQueueRawTracks: []
    property var _liveQueueAlbums:    []

    // Raw track maps for the previewed playlist -- feeds EXPORT's
    // enablement/payload and the total-playtime caption. Live mirror when
    // previewing the active playlist (see refreshLiveQueue()), the normal
    // disk-read PlaylistsData.selectedRawTracks otherwise.
    readonly property var currentRawTracks:
        root.isSelectedActiveInQueue ? root._liveQueueRawTracks
                                      : (playlistsData ? playlistsData.selectedRawTracks : [])

    readonly property var currentAlbums:
        root.isSelectedActiveInQueue ? root._liveQueueAlbums
                                      : (playlistsData ? playlistsData.albums : [])

    // True while the previewed/selected playlist is also the one currently
    // loaded into the queue -- gates LOAD, the trash-bin, and drag/
    // double-click-to-queue (see loadBtn/deletePlaylistBtn/the AlbumCard
    // delegate below), since re-queuing from or deleting the live queue's
    // own playlist file doesn't make sense while it's active. Also
    // switches currentRawTracks/currentAlbums/the auto-scroll behavior
    // above/below to the live queue mirror rather than the last disk
    // read. See UC-22.
    readonly property bool isSelectedActiveInQueue:
        root.engine && root.playlistsData
        && root.playlistsData.selectedFileName !== ""
        && root.engine.activePlaylistName === root.playlistsData.selectedFileName

    // Rebuilds both live-mirror arrays from the actual live queue -- the
    // XSPF file on disk isn't a reliable source for the active playlist
    // specifically, since PlaybackEngine skips rewriting it while
    // playlistLocked is true (flushed only once unlocked). Always
    // re-settles the scroll position afterward (deferred -- resultList's
    // contentHeight needs a tick to catch up with the new model before
    // positionViewAtIndex is meaningful): without this, an AUTO PLAY
    // addition mid-session would reset resultList's scroll to the top
    // (a wholesale model-array replacement) and nothing would re-correct
    // it until the next track advance.
    function refreshLiveQueue() {
        if (!root.engine || !root.playlistsData || !root.playlistsData.libraryModel) return
        root._liveQueueRawTracks = root.engine.trackList()
        root._liveQueueAlbums =
            root.playlistsData.libraryModel.buildStandaloneTrackCards(root._liveQueueRawTracks)
        Qt.callLater(root.scrollToNowPlaying)
    }

    // Scrolls resultList so the now-playing row sits at the very top --
    // only meaningful while previewing the active playlist. Shared by
    // every trigger below (mount/tab-entry, manual row selection, track
    // advance, any live-content refresh) so "as high up as possible"
    // holds regardless of *how* the active playlist became the previewed
    // one or what changed about it.
    function scrollToNowPlaying() {
        if (root.isSelectedActiveInQueue && root.engine && root.engine.currentIndex >= 0)
            resultList.positionViewAtIndex(root.engine.currentIndex, ListView.Beginning)
    }

    // Keeps the live mirror (and, via refreshLiveQueue()'s own
    // scrollToNowPlaying() call, the scroll position) in sync while this
    // view stays mounted on the active playlist -- AUTO PLAY appending
    // tracks, or a reorder via PlaybackQueue (always visible regardless
    // of which TopBar tab is active), or the queue simply advancing to
    // the next track.
    Connections {
        target: root.engine
        function onRowsInserted() { if (root.isSelectedActiveInQueue) root.refreshLiveQueue() }
        function onRowsRemoved()  { if (root.isSelectedActiveInQueue) root.refreshLiveQueue() }
        function onRowsMoved()    { if (root.isSelectedActiveInQueue) root.refreshLiveQueue() }
        function onModelReset()   { if (root.isSelectedActiveInQueue) root.refreshLiveQueue() }
        function onCurrentIndexChanged() { root.scrollToNowPlaying() }
    }

    // Covers *manually* selecting the active playlist's row in
    // PlaylistsPanel while already sitting on the PLAYLISTS tab -- a
    // plain property change, not a remount, so onPlaylistsDataChanged
    // below never fires for it.
    onIsSelectedActiveInQueueChanged: {
        if (isSelectedActiveInQueue) refreshLiveQueue()
    }

    // Re-syncs the preview every time this view (re)mounts -- Main.qml's
    // Loader destroys/recreates it on every PLAYLISTS<->LIBRARY/SEARCH
    // switch, so this fires once per entry into PLAYLISTS, not just once
    // ever. Also restores the saved scroll position (non-active playlist)
    // or scrolls to the now-playing row (active playlist, via
    // refreshLiveQueue()). Qt.callLater defers the non-active branch past
    // this tick so contentHeight has caught up with currentAlbums first
    // -- setting contentY immediately can get clamped back to 0.
    onPlaylistsDataChanged: {
        if (!playlistsData) return
        if (playlistsData.selectedFileName !== "") {
            if (root.isSelectedActiveInQueue) root.refreshLiveQueue()
            else playlistsData.selectPlaylist(playlistsData.selectedFileName)
        }
        if (!root.isSelectedActiveInQueue)
            Qt.callLater(function() {
                if (playlistsData) resultList.contentY = playlistsData.resultScrollY
            })
    }

    // ── Header -- LOAD button instead of a title label (see UC-22) ────────
    Item {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 72

        Rectangle {
            id: loadBtn
            anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
            width:  119   // 140 reduced by 15%
            height: 44
            radius: Theme.radiusSm

            // Active for any selected playlist, including a genuinely
            // empty one (0 tracks, 0 missing) -- LOAD still sets it as
            // the active playlist so LIBRARY/SEARCH additions can start
            // syncing to it, just with nothing queued to play (see the
            // "EMPTY PLAYLIST" branch below). Also covers a playlist
            // whose tracks are all missing, letting LOAD explain why
            // rather than being permanently disabled. See UC-22.
            readonly property bool active: root.playlistsData
                                            && root.playlistsData.selectedFileName !== ""
                                            && (!root.autoPlay || root.autoPlay.queueClearAllowed)
                                            && !root.isSelectedActiveInQueue

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
                    } else if (root.engine && tracks.length === 0 && missing.length === 0) {
                        // Genuinely empty playlist -- still becomes the
                        // active playlist (so LIBRARY/SEARCH additions
                        // start syncing to it via PlaybackEngine's
                        // auto-sync), just with nothing queued to play.
                        // See UC-22/UC-09.
                        if (root.autoPlay) root.autoPlay.clearHistory()
                        root.engine.loadPlaylistTracks([])
                        root.engine.setActivePlaylistName(loadedFileName)
                        emptyPlaylistBox.open()
                    }
                    // Selection deliberately stays on the just-loaded
                    // playlist -- it now renders as "(IN QUEUE)" in
                    // PlaylistsPanel instead of being moved away. See UC-22.
                    if (missing.length > 0) root.missingPlaylistTracks(missing)
                }

                ToolTip.visible: containsMouse && loadBtn.active
                ToolTip.delay:   600
                ToolTip.text:    qsTr("LOAD PLAYLIST")
            }
        }

        // EXPORT the selected playlist -- reads straight from its XSPF file
        // (playlistsData.selectedRawTracks), never touches the queue, so no
        // autoPlay.queueClearAllowed gate is needed unlike LOAD. See UC-26.
        Rectangle {
            id: exportBtn
            anchors { left: loadBtn.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width:  100
            height: 44
            radius: Theme.radiusSm

            readonly property bool active: root.currentRawTracks.length > 0

            color:  active && exportHover.containsMouse ? Theme.surfaceContainerHigh
                                                         : Theme.surfaceContainer
            border.color: Theme.ov20
            border.width: 1
            opacity: active ? 1.0 : 0.35

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("EXPORT")
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelLg
                    font.weight:        Font.Medium
                    font.letterSpacing: Theme.lsWide
                    color: Theme.fgSurface
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "↗"
                    font.pixelSize: Theme.titleMd
                    color: Theme.fgSurfaceVariant
                }
            }

            MouseArea {
                id: exportHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: exportBtn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!exportBtn.active) return
                    root.exportPlaylistRequested()
                }

                ToolTip.visible: containsMouse && exportBtn.active
                ToolTip.delay:   600
                ToolTip.text:    qsTr("EXPORT PLAYLIST")
            }
        }

        // Delete the selected playlist -- right after EXPORT, vertically
        // centered with LOAD/EXPORT (same verticalCenter: parent.verticalCenter
        // anchor, so its 32px height centers on their shared 44px middle).
        // See UC-26.
        Rectangle {
            id: deletePlaylistBtn
            anchors { left: exportBtn.right; leftMargin: 12; verticalCenter: parent.verticalCenter }
            width: 32; height: 32
            radius: Theme.radiusFull

            readonly property bool active: root.playlistsData && root.playlistsData.selectedFileName !== ""
                                            && !root.isSelectedActiveInQueue

            color: deleteHover.containsMouse ? Theme.surfaceContainerHighest : "transparent"
            opacity: active ? 1.0 : 0.35

            Image {
                anchors.centerIn: parent
                source: "qrc:/Topaz/TrashBin_Icon.svg"
                sourceSize.width:  16
                sourceSize.height: 16
            }

            MouseArea {
                id: deleteHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: deletePlaylistBtn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (!deletePlaylistBtn.active) return
                    deleteConfirmBox.open()
                }

                ToolTip.visible: containsMouse && deletePlaylistBtn.active
                ToolTip.delay:   600
                ToolTip.text:    qsTr("DELETE PLAYLIST")
            }
        }

        Row {
            anchors { right: parent.right; rightMargin: 32; bottom: parent.bottom; bottomMargin: 20 }
            spacing: 4

            readonly property int offlineCount:
                root.playlistsData ? root.playlistsData.selectedMissingTracks.length : 0

            Text {
                text: (playlistsData && playlistsData.selectedFileName !== "")
                      ? (_trackCount(root.currentAlbums) + " TRACKS | "
                         + root.formatTotalDuration(root.totalPlaylistDurationMs) + "  —  "
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

    // Plain notice (no confirmMode) -- opened by LOAD's empty-playlist
    // branch above. See UC-22/UC-09.
    MessageBox {
        id: emptyPlaylistBox
        title:   qsTr("EMPTY PLAYLIST")
        message: qsTr("The playlist is still empty.")
    }

    MessageBox {
        id: deleteConfirmBox
        title: qsTr("DELETE PLAYLIST")
        message: qsTr("Would you like to delete the selected playlist?")
        confirmMode: true
        confirmButtonText: qsTr("DELETE")
        onAccepted: {
            if (!root.playlistsData || !root.playlistsData.playlistManager) return
            const fileName = root.playlistsData.selectedFileName
            if (fileName === "") return
            root.playlistsData.playlistManager.deletePlaylist(fileName)
            // Must run BEFORE refreshPlaylists() -- selectNeighborOf() looks
            // up fileName's position in the *current* playlists array to
            // pick an adjacent one; refreshing first would make it
            // un-findable.
            root.playlistsData.selectNeighborOf(fileName)
            root.playlistsData.refreshPlaylists()
        }
    }

    function _trackCount(albums) {
        let n = 0
        for (let i = 0; i < albums.length; i++) n += albums[i].tracks.length
        return n
    }

    readonly property int totalPlaylistDurationMs:
        root.currentRawTracks.reduce(
            function (sum, t) { return sum + (t.durationMs || 0) }, 0)

    // Same M:SS-under-100-minutes / H:MM:SS-from-100-minutes-up format as
    // ExportPlaylistDialog.qml's identical helper.
    function formatTotalDuration(ms) {
        const totalSecs = Math.floor(ms / 1000)
        const totalMins = Math.floor(totalSecs / 60)
        const secs = totalSecs % 60
        if (totalMins < 100)
            return totalMins + ":" + String(secs).padStart(2, "0")
        const hours = Math.floor(totalMins / 60)
        const mins  = totalMins % 60
        return hours + ":" + String(mins).padStart(2, "0") + ":" + String(secs).padStart(2, "0")
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
            queueInteractionEnabled: !root.isSelectedActiveInQueue
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
