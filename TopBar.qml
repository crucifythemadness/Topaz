import QtQuick
import QtQuick.Layouts

// Header bar: Logo | Navigation tabs | Settings icon + Equalizer icon + User avatar
Rectangle {
    id: root
    height: 64
    color: Theme.surface

    // Emitted when the user clicks the gear (⚙) icon
    signal settingsRequested()

    // Ghost bottom border (10 % outlineVariant) вЂ” satisfies the "no-line" rule
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.ov10
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
        spacing: 0

        // в”Ђв”Ђ Branding в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
        Text {
            text: qsTr("TOPAZ JUKEBOX")
            font.family: Theme.fontFamilyHeadline
            font.pixelSize:    22
            font.weight:       Font.Bold
            font.letterSpacing: Theme.lsWidest
            color: Theme.fgSurface
        }

        Item { Layout.fillWidth: true }

        // в”Ђв”Ђ Navigation tabs в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
        Row {
            Layout.fillHeight: true
            spacing: 48

            // Library (active state)
            Item {
                width:  libText.implicitWidth
                height: parent.height

                Text {
                    id: libText
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("LIBRARY")
                    font.family: Theme.fontFamilyBody
                    font.pixelSize:    Theme.labelSm
                    font.weight:       Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.primary
                }

                // Active underline
                Rectangle {
                    anchors {
                        left: libText.left; right: libText.right
                        bottom: parent.bottom; bottomMargin: 4
                    }
                    height: 2
                    color: Theme.primary
                }
            }

            // Playlists (inactive)
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("PLAYLISTS")
                font.family: Theme.fontFamilyBody
                font.pixelSize:    Theme.labelSm
                font.weight:       Font.Medium
                font.letterSpacing: Theme.lsWidest
                color: hoverPlaylists.containsMouse ? Theme.fgSurface : Theme.fgSurfaceVariant

                MouseArea {
                    id: hoverPlaylists
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }

        Item { Layout.fillWidth: true }

        // в”Ђв”Ђ Right-side actions в”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђв”Ђ
        Row {
            Layout.fillHeight: true
            spacing: 20

            // Settings вљ™
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2699"
                font.pixelSize: 20
                color: hoverSettings.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
                MouseArea {
                    id: hoverSettings
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.settingsRequested()
                }
            }

            // Equalizer в‰Ў
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2261"
                font.pixelSize: 22
                color: hoverEq.containsMouse ? Theme.primary : Theme.fgSurfaceVariant
                MouseArea {
                    id: hoverEq
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }
            }

            // User avatar circle
            Rectangle {
                width:  32
                height: 32
                radius: 16
                color:  Theme.surfaceContainerHighest
                border.color: Theme.ov30
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.centerIn: parent
                    text: "M"
                    font.family: Theme.fontFamilyBody
                    font.pixelSize: 13
                    font.weight:    Font.Medium
                    color: Theme.fgSurface
                }
            }
        }
    }
}
