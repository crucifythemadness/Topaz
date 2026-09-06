import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs

// Now-Playing panel: album art, transport controls, and playlist management.
// Custom progress slider (no QtQuick.Controls Slider dependency) keeps it light.
Rectangle {
    id: root
    property var engine: null
    property var playlistManager: null
    // Bound from Main.qml. Gates playlist load/remove while an AUTO PLAY
    // session forbids manual modification/clearing — see UC-16 in the
    // architecture doc.
    property var autoPlay: null
    color: Theme.surfaceContainerLow

    signal newPlaylistRequested()
    // Emitted when the user clicks EXPORT with a named playlist loaded --
    // Main.qml opens ExportPlaylistDialog. See UC-26.
    signal exportPlaylistRequested()
    // Emitted when the user left-clicks the album cover — opens the
    // detachable BigCoverWindow pane (see Main.qml's Loader wiring).
    signal bigCoverRequested()
    // Emitted after LOAD when the just-loaded playlist had tracks whose file
    // couldn't be found -- Main.qml opens MissingTracksDialog. See UC-10.
    signal missingPlaylistTracks(var missingTracks)

    // ── Load playlist file dialog ───────────────────────────────────────
    FileDialog {
        id: loadPlaylistDialog
        title: qsTr("Select a XSPF Playlist")
        nameFilters: ["XSPF Playlists (*.xml)"]
        fileMode: FileDialog.OpenFile
        onAccepted: {
            if (!root.playlistManager || !root.engine) return
            if (root.autoPlay && !root.autoPlay.manualQueueEditingAllowed) return
            const result = root.playlistManager.loadPlaylist(
                               loadPlaylistDialog.selectedFile.toString())
            const tracks = result.tracks
            if (tracks && tracks.length > 0) {
                // loadPlaylistTracks() always replaces the queue -- it
                // crossfades into the new playlist when CROSSFADE is on and
                // something is currently playing, otherwise it's an instant
                // replace (see UC-23).
                if (root.autoPlay) root.autoPlay.clearHistory()
                root.engine.loadPlaylistTracks(tracks)
                root.engine.setActivePlaylistName(result.fileName)
            }
            if (result.missing && result.missing.length > 0)
                root.missingPlaylistTracks(result.missing)
        }
    }

    // Ghost left border
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
        width: 1
        color: Theme.ov10
    }

    Flickable {
        anchors.fill: parent
        contentHeight: npColumn.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: npColumn
            width: root.width
            spacing: 0

            // ── Album Cover ────────────────────────────────────────────────
            Item {
                id: coverArea
                width:  root.width
                height: root.width

                // Placeholder gradient (shown when no track is playing)
                Rectangle {
                    anchors.fill: parent
                    color: Theme.surfaceContainerHigh
                    visible: coverImage.status !== Image.Ready

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
                        GradientStop { position: 1.0; color: Theme.surfaceBright }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.engine && root.engine.currentTitle.length > 0
                              ? root.engine.currentTitle.charAt(0).toUpperCase()
                              : "\u266B"
                        font.family:    Theme.fontFamilyHeadline
                        font.pixelSize: 40
                        font.weight:    Font.Bold
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.30)
                        font.letterSpacing: 4
                    }
                }

                Image {
                    id: coverImage
                    anchors.fill: parent
                    source: root.engine
                            ? (root.engine.currentLargeCoverSource !== ""
                               ? root.engine.currentLargeCoverSource
                               : root.engine.currentCoverSource)
                            : ""
                    sourceSize.width:  root.width
                    sourceSize.height: root.width
                    fillMode:  Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                // Opens the detachable BigCoverWindow pane — same pointing-hand
                // cursor as Play/Pause, left-click only (right-click is reserved
                // for closing the pane itself, not for anything here).
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.bigCoverRequested()
                }
            }

            // ── Track info ─────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 0
                topPadding: 16
                leftPadding: 16
                rightPadding: 16

                Text {
                    width: parent.width - 32
                    text: root.engine && root.engine.currentTitle.length > 0
                          ? root.engine.currentTitle.toUpperCase()
                          : qsTr("NO TRACK")
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineMd
                    font.weight:        Font.Black
                    font.letterSpacing: Theme.lsTight
                    color: Theme.fgSurface
                    elide: Text.ElideRight
                    bottomPadding: 4
                }

                Text {
                    width: parent.width - 32
                    text: root.engine ? root.engine.currentArtist.toUpperCase() : ""
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelLg
                    font.weight:        Font.DemiBold
                    font.letterSpacing: Theme.lsWide
                    color: Theme.secondary
                    bottomPadding: 12
                }

                // Format/bitrate badge (left) + rating stars (right) — same row
                Item {
                    width:  parent.width - 32
                    height: 26

                    // Star rating — click star N to set the rating to N (1-10).
                    // Persists immediately to Topaz.rating.json; refreshed whenever
                    // NowPlaying starts a new track (see PlaybackEngine.currentRating).
                    Row {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 3
                        // Only show a rating to give when a track is actually loaded.
                        visible: root.engine && root.engine.currentTitle.length > 0

                        Repeater {
                            model: 10

                            delegate: Text {
                                text: "★"   // ★
                                font.pixelSize: 18

                                readonly property bool filled:
                                    root.engine && index < root.engine.currentRating

                                // This blue is a deliberate, one-off break from the
                                // theme palette for the rating stars.
                                color: filled              ? "#00A6ED"
                                     : starMA.containsMouse ? Qt.rgba(0, 0.651, 0.929, 0.45)
                                     :                        Theme.outlineVariant

                                MouseArea {
                                    id: starMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape:  Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.engine) root.engine.setCurrentRating(index + 1)
                                    }
                                }
                            }
                        }
                    }

                    // Format badge
                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        height: 26
                        width:  formatLabel.implicitWidth + 20
                        radius: Theme.radiusFull
                        color:  Theme.surfaceContainerHigh
                        visible: root.engine && root.engine.currentFormat.length > 0

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                width: 8; height: 8
                                radius: 4
                                color: Theme.secondary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: formatLabel
                                text: root.engine
                                      ? (root.engine.currentFormat + "  |  "
                                         + root.engine.currentBitrate + " KBPS")
                                      : ""
                                font.family:        Theme.fontFamilyMono
                                font.pixelSize:     Theme.monoSm
                                font.weight:        Font.Medium
                                font.letterSpacing: 0.8
                                color: Theme.fgSurface
                            }
                        }
                    }
                }
            }

            // ── Progress section ───────────────────────────────────────────
            Item {
                width:  parent.width
                height: progressInner.implicitHeight + 14
                clip:   false

                Column {
                    id: progressInner
                    anchors {
                        left:  parent.left;  leftMargin:  16
                        right: parent.right; rightMargin: 16
                        top:   parent.top;   topMargin:   14
                    }
                    spacing: 6

                    // Time row
                    Item {
                        width:  parent.width
                        height: 22

                        Text {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            text: root.engine ? root.engine.positionString : "0:00"
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoMd
                            color: Theme.fgSurfaceVariant
                        }
                        Text {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: root.engine ? root.engine.durationString : "0:00"
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoMd
                            color: Theme.fgSurfaceVariant
                        }
                    }

                    // Custom seekable progress bar
                    Item {
                        id: progressBar
                        width:  parent.width
                        height: 16

                        property real progress: (root.engine && root.engine.duration > 0)
                                                ? root.engine.position / root.engine.duration
                                                : 0

                        // Track background
                        Rectangle {
                            anchors { left: parent.left; right: parent.right
                                      verticalCenter: parent.verticalCenter }
                            height: 4
                            radius: 2
                            color:  Theme.surfaceContainerHighest

                            // Played portion
                            Rectangle {
                                width: parent.width * progressBar.progress
                                height: parent.height
                                radius: 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.primary }
                                    GradientStop { position: 1.0; color: Theme.secondary }
                                }
                            }
                        }

                        // Thumb handle
                        Rectangle {
                            id: thumb
                            x: progressBar.progress * (progressBar.width - width)
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16; height: 16
                            radius: 8
                            color: Theme.secondary

                            Rectangle {
                                anchors.centerIn: parent
                                width: 26; height: 26
                                radius: 13
                                color: Theme.s20
                            }
                        }

                        // Seek mouse area
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: function(mouse) {
                                if (root.engine && root.engine.duration > 0)
                                    root.engine.seek(
                                        Math.max(0, Math.min(1, mouse.x / progressBar.width))
                                        * root.engine.duration)
                            }
                            onPositionChanged: function(mouse) {
                                if (pressed && root.engine && root.engine.duration > 0)
                                    root.engine.seek(
                                        Math.max(0, Math.min(1, mouse.x / progressBar.width))
                                        * root.engine.duration)
                            }
                        }
                    }
                }
            }

            // ── Transport controls ─────────────────────────────────────────
            Item {
                width:  parent.width
                height: 60

                Row {
                    anchors.centerIn: parent
                    spacing: 28

                    // Previous
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u23EE"
                        font.pixelSize: 20
                        color: prevHover.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                        MouseArea {
                            id: prevHover; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var navAllowed = !root.autoPlay || root.autoPlay.trackNavigationAllowed
                                if (root.engine && navAllowed) root.engine.previous()
                            }
                        }
                    }

                    // Play/Pause (primary action)
                    Rectangle {
                        id: playPauseBtn
                        width: 44; height: 44
                        radius: 22
                        color: playHover.containsMouse ? Theme.surfaceBright
                                                       : Theme.surfaceContainerHighest
                        anchors.verticalCenter: parent.verticalCenter

                        // Blinks while the current track is manually paused
                        // (see UC-07) -- stops the instant playback resumes
                        // or a different track becomes current, never for
                        // any other "not playing" state (e.g. the queue
                        // having finished naturally).
                        readonly property bool userPaused: root.engine && root.engine.userPaused

                        SequentialAnimation on opacity {
                            running: playPauseBtn.userPaused
                            loops: Animation.Infinite
                            NumberAnimation { from: 1.0; to: 0.3; duration: 500 }
                            NumberAnimation { from: 0.3; to: 1.0; duration: 500 }
                        }
                        onUserPausedChanged: if (!userPaused) opacity = 1.0   // animation.stop() can land mid-fade

                        Text {
                            anchors.centerIn: parent
                            text: (root.engine && root.engine.isPlaying) ? "\u23F8" : "\u25B6"
                            font.pixelSize: 18
                            color: Theme.fgSurface
                        }

                        MouseArea {
                            id: playHover; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var playAllowed = !root.autoPlay || root.autoPlay.playPauseAllowed
                                if (root.engine && playAllowed) root.engine.togglePlay()
                            }
                        }
                    }

                    // Next
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u23ED"
                        font.pixelSize: 20
                        color: nextHover.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant
                        MouseArea {
                            id: nextHover; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var navAllowed = !root.autoPlay || root.autoPlay.trackNavigationAllowed
                                if (root.engine && navAllowed) root.engine.next()
                            }
                        }
                    }
                }
            }

            // ── Playlist management ────────────────────────────────────────
            Column {
                id: playlistButtons
                width: parent.width

                // Row 1 — NEW  |  LOAD
                Row {
                    width:  parent.width
                    height: 52

                    Rectangle {
                        width:  parent.width / 2
                        height: parent.height
                        color:  newHover.containsMouse ? Theme.surfaceContainerHigh
                                                       : Theme.surfaceContainerHigh
                        border.color: Theme.ov20
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "+"
                                font.pixelSize: Theme.titleMd
                                color: Theme.fgSurfaceVariant
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("NEW")
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelLg
                                font.weight:        Font.Medium
                                font.letterSpacing: Theme.lsWide
                                color: Theme.fgSurface
                            }
                        }
                        MouseArea {
                            id: newHover; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.newPlaylistRequested()

                            ToolTip.visible: containsMouse
                            ToolTip.delay:   600
                            ToolTip.text:    qsTr("NEW PLAYLIST")
                        }
                    }

                    Rectangle {
                        id: loadPlaylistBtn
                        width:  parent.width / 2
                        height: parent.height

                        readonly property bool active: !root.autoPlay || root.autoPlay.queueClearAllowed

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
                                text: "\u2191"
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
                            id: loadHover; anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: loadPlaylistBtn.active ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!loadPlaylistBtn.active) return
                                // Clearing/crossfading happens in
                                // loadPlaylistDialog.onAccepted instead, once
                                // the new tracks are actually known (see
                                // UC-23) -- clearing here, before the file is
                                // even picked, meant canceling the dialog
                                // used to leave the queue emptied for nothing.
                                if (root.playlistManager)
                                    loadPlaylistDialog.currentFolder =
                                        "file:///" + root.playlistManager.playlistDirectory()
                                loadPlaylistDialog.open()
                            }

                            ToolTip.visible: containsMouse && loadPlaylistBtn.active
                            ToolTip.delay:   600
                            ToolTip.text:    qsTr("LOAD PLAYLIST")
                        }
                    }
                }

                // Row 2 — EXPORT  |  REMOVE
                Row {
                    width:  parent.width
                    height: 52

                    Rectangle {
                        id: exportPlaylistBtn
                        width:  parent.width / 2
                        height: parent.height

                        readonly property bool active:
                            root.engine !== null && root.engine.activePlaylistName !== ""
                            && root.engine.queueCount > 0

                        color:  active && exportHover.containsMouse
                                ? Theme.surfaceContainerHigh : Theme.surfaceContainer
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
                                text: "\u2197"   // ↗ northeast arrow
                                font.pixelSize: Theme.titleMd
                                color: Theme.fgSurfaceVariant
                            }
                        }
                        MouseArea {
                            id: exportHover; anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: exportPlaylistBtn.active
                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!exportPlaylistBtn.active) return
                                root.exportPlaylistRequested()
                            }

                            ToolTip.visible: containsMouse && exportPlaylistBtn.active
                            ToolTip.delay:   600
                            ToolTip.text:    qsTr("EXPORT PLAYLIST")
                        }
                    }

                    Rectangle {
                        id: removePlaylistBtn
                        width:  parent.width / 2
                        height: parent.height

                        readonly property bool active:
                            root.engine !== null && root.engine.activePlaylistName !== ""
                            && (!root.autoPlay || root.autoPlay.queueClearAllowed)

                        color:  active && removePlaylistHover.containsMouse
                                ? Theme.surfaceContainerHigh : Theme.surfaceContainer
                        border.color: Theme.ov20
                        border.width: 1
                        opacity: active ? 1.0 : 0.35

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u2715"   // ✕
                                font.pixelSize: Theme.titleMd
                                color: Theme.fgSurfaceVariant
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("REMOVE")
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelLg
                                font.weight:        Font.Medium
                                font.letterSpacing: Theme.lsWide
                                color: Theme.fgSurface
                            }
                        }
                        MouseArea {
                            id: removePlaylistHover; anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: removePlaylistBtn.active
                                         ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (!removePlaylistBtn.active) return
                                if (root.autoPlay) root.autoPlay.clearQueueAndHistory()
                                else if (root.engine) root.engine.clearQueue()
                            }

                            ToolTip.visible: containsMouse && removePlaylistBtn.active
                            ToolTip.delay:   600
                            ToolTip.text:    qsTr("REMOVE PLAYLIST")
                        }
                    }
                }
            }
        }
    }
}