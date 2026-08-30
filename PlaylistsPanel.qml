import QtQuick
import QtQuick.Controls

// Replaces LibraryTree/SearchPanel in the same SplitView slot when TopBar's
// PLAYLISTS tab is active (see Main.qml's Loader). Entirely independent of
// LibraryData/SearchData -- all state lives in PlaylistsData.
Rectangle {
    id: root
    property PlaylistsData playlistsData: null
    color: Theme.surfaceContainerLowest

    // Refreshes the playlist listing every time this panel is (re)created,
    // i.e. every time the user switches into PLAYLISTS -- cheap (a QDir
    // listing) and means a playlist just created via NOW PLAYING's + NEW
    // shows up with no extra signal plumbing. Deliberately NOT
    // Component.onCompleted: Main.qml's Loader.onLoaded assigns
    // `item.playlistsData` imperatively *after* this item (and its
    // Component.onCompleted) already ran, so playlistsData would still be
    // null at that point -- the same ordering pitfall AlbumBrowser/
    // SearchResultBrowser already solve via onLibChanged/onSearchDataChanged.
    //
    // Also auto-selects the first playlist not already active in the queue,
    // but only if nothing is currently selected -- PlaylistsData lives
    // outside the Loader specifically so its selection survives switching
    // away and back (same as LibraryData/SearchData), so this must not
    // clobber an existing selection on re-entry.
    onPlaylistsDataChanged: {
        if (!playlistsData) return
        playlistsData.refreshPlaylists()
        if (playlistsData.selectedFileName !== "") return
        const activeInQueue = playlistsData.engine ? playlistsData.engine.activePlaylistName : ""
        const first = playlistsData.playlists.find(p => p.fileName !== activeInQueue)
        if (first) playlistsData.selectPlaylist(first.fileName)
    }

    // Ghost right border -- same chrome as LibraryTree/SearchPanel
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1
        color: Theme.ov10
    }

    // ── Header -- matches SearchPanel's "SEARCH" header exactly ───────────
    Item {
        id: panelHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56

        Text {
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            text: qsTr("PLAYLISTS")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     Theme.labelLg
            font.weight:        Font.Bold
            font.letterSpacing: Theme.lsWidest
            color: Theme.primary
        }

        // Placeholder for a v2.0 playlist manager -- intentionally not wired
        // to anything yet (no signal, no onClicked action). Styled to match
        // NowPlaying's NEW/LOAD pill buttons for a preview of its look.
        Rectangle {
            id: managerBtn
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter }
            width:  132
            height: 36
            radius: Theme.radiusSm
            color: managerHover.containsMouse ? Theme.surfaceContainerHigh
                                               : Theme.surfaceContainer
            border.color: Theme.ov20
            border.width: 1

            Row {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⚙"
                    font.pixelSize: Theme.titleMd
                    color: Theme.fgSurfaceVariant
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("MANAGER")
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelLg
                    font.weight:        Font.Medium
                    font.letterSpacing: Theme.lsWide
                    color: Theme.fgSurface
                }
            }

            MouseArea {
                id: managerHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                ToolTip.visible: containsMouse
                ToolTip.delay:   600
                ToolTip.text:    qsTr("OFFLINE PLAYLIST MANAGER")
            }
        }
    }

    // ── Playlist list ────────────────────────────────────────────────────
    ListView {
        id: playlistList
        anchors { left: parent.left; right: parent.right; top: panelHeader.bottom; bottom: parent.bottom }
        clip: true
        model: root.playlistsData ? root.playlistsData.playlists : []

        delegate: Item {
            id: rowItem
            width:  playlistList.width
            height: 44

            readonly property bool isSelected: root.playlistsData
                                                && root.playlistsData.selectedFileName === modelData.fileName
            // The playlist currently loaded into the queue can't be opened
            // for viewing here -- reselecting it would just clear and
            // reload the exact same queue. See UC-22.
            readonly property bool isActiveInQueue: root.playlistsData && root.playlistsData.engine
                                                      && root.playlistsData.engine.activePlaylistName === modelData.fileName

            Rectangle {
                anchors.fill: parent
                color:  rowItem.isSelected ? Theme.s10 : "transparent"
                radius: Theme.radiusSm
            }

            Row {
                spacing: 8
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                opacity: rowItem.isActiveInQueue ? 0.4 : 1.0

                Text {
                    text: "⬥"
                    font.pixelSize: Theme.labelMd
                    color: rowItem.isSelected ? Theme.secondary : Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: modelData.displayName
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelLg
                    font.weight:        rowItem.isSelected ? Font.ExtraBold : Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: rowItem.isSelected ? Theme.secondary : Theme.primary
                }
                Text {
                    visible: rowItem.isActiveInQueue
                    text: qsTr("(IN QUEUE)")
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.labelSm
                    color: Theme.fgSurfaceVariant
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled:      !rowItem.isActiveInQueue
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: if (root.playlistsData) root.playlistsData.selectPlaylist(modelData.fileName)
            }
        }

        // Empty state
        Text {
            anchors.centerIn: parent
            visible: playlistList.count === 0
            text:    qsTr("No playlists yet.\nCreate one from NOW PLAYING.")
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelMd
            color:          Theme.fgSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
