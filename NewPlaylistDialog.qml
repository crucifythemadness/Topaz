import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ── NewPlaylistDialog ─────────────────────────────────────────────────────
// Modal dialog to create a new XSPF playlist.
// The user provides a name (without extension); the file is saved as <name>.xml
// in the playlist directory managed by PlaylistManager.
//
// Usage in Main.qml:
//   NewPlaylistDialog { id: newPlaylistDialog
//                       playlistManager: playlistManager
//                       engine: engine }
//   ...
//   newPlaylistDialog.open()
Popup {
    id: root

    required property var playlistManager
    required property var engine

    anchors.centerIn: Overlay.overlay
    width:  520
    height: 280
    padding: 0

    modal: true
    closePolicy: Popup.NoAutoClose

    // Reset state each time the dialog opens
    onOpened: {
        nameInput.text = ""
        nameInput.forceActiveFocus()
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    // Themed message box for the "already exists" error
    MessageBox {
        id: errorBox
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            // Square off bottom corners
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                spacing: 0

                Text {
                    text: "NEW PLAYLIST"
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                // ✕ close button
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusFull
                    color: closeHover.containsMouse ? Theme.surfaceContainerHighest
                                                    : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        font.pixelSize: 14
                        color: Theme.fgSurfaceVariant
                    }
                    MouseArea {
                        id: closeHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    root.close()
                    }
                }
            }
        }

        // ── Body ─────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 16

                // Label
                Text {
                    text: "PLAYLIST NAME"
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelXs
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurfaceVariant
                }

                // Text input field
                Rectangle {
                    Layout.fillWidth: true
                    height: 40
                    color:  Theme.surfaceContainerHigh
                    radius: Theme.radiusSm
                    border.color: nameInput.activeFocus ? Theme.primary : "transparent"
                    border.width: 1

                    // Placeholder
                    Text {
                        anchors { fill: nameInput }
                        visible: nameInput.text.length === 0 && !nameInput.activeFocus
                        verticalAlignment: Text.AlignVCenter
                        text: "Enter playlist name\u2026"
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelLg
                        color: Theme.fgSurfaceVariant
                    }

                    TextInput {
                        id: nameInput
                        anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                        verticalAlignment: TextInput.AlignVCenter
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelLg
                        color:          Theme.fgSurface
                        clip:           true
                        selectByMouse:  true
                        Keys.onReturnPressed: root.tryCreate()
                        Keys.onEscapePressed: root.close()
                    }
                }

                Item { Layout.fillHeight: true }

                // ── Buttons row ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    // CANCEL
                    Rectangle {
                        width: 100; height: 36
                        radius: Theme.radiusSm
                        color: cancelHover.containsMouse ? Theme.surfaceContainerHighest
                                                         : Theme.surfaceContainerHigh
                        Text {
                            anchors.centerIn: parent
                            text: "CANCEL"
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        Font.Bold
                            font.letterSpacing: Theme.lsWidest
                            color: Theme.fgSurfaceVariant
                        }
                        MouseArea {
                            id: cancelHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    root.close()
                        }
                    }

                    // OK
                    Rectangle {
                        width: 100; height: 36
                        radius: Theme.radiusSm
                        color: okHover.containsMouse ? Theme.primaryContainer
                                                     : Theme.surfaceContainerHigh
                        Text {
                            anchors.centerIn: parent
                            text: "OK"
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        Font.Bold
                            font.letterSpacing: Theme.lsWidest
                            color: okHover.containsMouse ? Theme.fgPrimaryContainer
                                                         : Theme.primary
                        }
                        MouseArea {
                            id: okHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    root.tryCreate()
                        }
                    }
                }
            }
        }
    }

    // ── Logic ─────────────────────────────────────────────────────────────
    function tryCreate() {
        const name = nameInput.text.trim()
        if (name.length === 0)
            return

        const tracks = root.engine ? root.engine.trackList() : []
        const err = root.playlistManager.createPlaylist(name, tracks)

        if (err.length > 0) {
            errorBox.message = err
            errorBox.open()
        } else {
            if (root.engine)
                root.engine.setActivePlaylistName(name + ".xml")
            root.close()
        }
    }
}
