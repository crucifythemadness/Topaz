import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Header bar: Logo | Navigation tabs | Loudspeaker icon + Settings icon + User avatar
Rectangle {
    id: root
    height: 64
    color: Theme.surface

    // Bound from Main.qml -- controls the Windows OS master volume (not
    // Topaz's own playback level). See systemvolumecontroller.h.
    property var systemVolume: null

    // Emitted when the user clicks the gear (⚙) icon
    signal settingsRequested()

    // Ghost bottom border (10 % outlineVariant) -- satisfies the "no-line" rule
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.ov10
    }

    RowLayout {
        anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
        spacing: 0

        // -- Branding --------------------------------------------------
        Text {
            text: qsTr("TOPAZ JUKEBOX")
            font.family: Theme.fontFamilyHeadline
            font.pixelSize:    22
            font.weight:       Font.Bold
            font.letterSpacing: Theme.lsWidest
            color: Theme.fgSurface
        }

        Item { Layout.fillWidth: true }

        // -- Navigation tabs ---------------------------------------------
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

        // -- Right-side actions --------------------------------------------
        Row {
            Layout.fillHeight: true
            spacing: 20

            // OS Volume (loudspeaker) -- opens a flyout pane with the volume
            // slider. Leftmost of the three (swapped with Settings).
            Item {
                id: volumeButton
                width:  32
                height: 32
                anchors.verticalCenter: parent.verticalCenter

                // Hover feedback: a background highlight rather than the
                // usual text-recolor, since the speaker emoji glyph is
                // rendered full-color by the system font and ignores text color.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusMd
                    color:  Theme.p10
                    visible: hoverVolume.containsMouse || volumePopup.opened
                }

                Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                    text: "🔊"
                    font.pixelSize: 22
                }

                MouseArea {
                    id: hoverVolume
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Re-read the OS volume in case it changed elsewhere
                        // while Topaz was already running (see
                        // SystemVolumeController::refresh()).
                        if (root.systemVolume) root.systemVolume.refresh()
                        volumePopup.open()
                    }
                    onContainsMouseChanged: volumeCloseTimer.restart()
                }

                Popup {
                    id: volumePopup
                    parent: volumeButton
                    x: volumeButton.width - width
                    y: volumeButton.height + 8
                    padding: Theme.sp5

                    modal: false
                    focus: false
                    closePolicy: Popup.NoAutoClose

                    background: Rectangle {
                        color:  Theme.surfaceContainerLow
                        radius: Theme.radiusLg
                        border.color: Theme.ov20
                        border.width: 1
                    }

                    contentItem: ColumnLayout {
                        spacing: 12

                        // Closes the pane once neither the button nor the
                        // pane itself has been hovered for a short moment --
                        // debounced so moving the mouse from the button onto
                        // the pane doesn't flicker-close it in transit.
                        HoverHandler {
                            id: hoverPane
                            onHoveredChanged: volumeCloseTimer.restart()
                        }
                        Timer {
                            id: volumeCloseTimer
                            interval: 150
                            onTriggered: {
                                if (!hoverVolume.containsMouse && !hoverPane.hovered)
                                    volumePopup.close()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: qsTr("OS Volume")
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(volumeSlider.value)
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelLg
                                font.weight:    Font.Bold
                                color: Theme.secondary
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                text: "0"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: volumeSlider
                                Layout.preferredWidth: 300
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.systemVolume ? root.systemVolume.volume : 100

                                onMoved: {
                                    if (root.systemVolume)
                                        root.systemVolume.setVolume(Math.round(value))
                                }

                                background: Rectangle {
                                    x: volumeSlider.leftPadding
                                    y: volumeSlider.topPadding
                                       + volumeSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  300
                                    implicitHeight: 4
                                    width:  volumeSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  volumeSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: volumeSlider.leftPadding
                                       + volumeSlider.visualPosition
                                         * (volumeSlider.availableWidth - width)
                                    y: volumeSlider.topPadding
                                       + volumeSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "100"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }
                }
            }

            // Settings
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "⚙"
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
