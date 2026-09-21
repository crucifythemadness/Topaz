import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
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

    // Bound from Main.qml -- read-only, just for the Hi-Res Audio badge
    // next to the branding text below (currentFormat === "FLAC").
    property var engine: null

    // Bound from Main.qml -- which of the three navigation tabs is active.
    // "library" | "playlists" | "search"
    property string activeTab: "library"

    // Emitted when the user clicks a navigation tab. TopBar owns no tab
    // state of its own beyond `activeTab` (for styling) -- same "dumb
    // component, owner decides" convention as settingsRequested()/
    // aboutRequested() below.
    signal librarySelected()
    signal playlistsSelected()
    signal searchSelected()

    // Emitted when the user clicks the gear (⚙) icon
    signal settingsRequested()

    // Emitted when the user clicks the About Topaz (ⓘ) icon
    signal aboutRequested()

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

        // Hi-Res Audio badge -- only while the currently-playing track is
        // lossless (FLAC only) AND a legitimate "Hi-Res_Audio.svg" has been
        // placed beside Topaz.exe by the user (see HiResAudioLogo -- the
        // logo is trademarked and deliberately never bundled/compiled into
        // Topaz.exe itself). RowLayout excludes an invisible child (and its
        // margin) from layout entirely, so the 16px gap only appears
        // together with the icon.
        Image {
            Layout.leftMargin: 16
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height - 16   // 8px gap above + below
            Layout.preferredWidth:  Layout.preferredHeight   // SVG is ~1:1
            visible: root.engine && root.engine.currentFormat === "FLAC"
                     && HiResAudioLogo.url() !== ""
            source: HiResAudioLogo.url()
            sourceSize.width:  Layout.preferredWidth
            sourceSize.height: Layout.preferredHeight
            fillMode: Image.PreserveAspectFit
        }

        Item { Layout.fillWidth: true }

        // -- Navigation tabs ---------------------------------------------
        Row {
            Layout.fillHeight: true
            spacing: 48

            Repeater {
                model: [
                    { key: "library",   label: "LIBRARY"   },
                    { key: "search",    label: "SEARCH"    },
                    { key: "playlists", label: "PLAYLISTS" }
                ]

                delegate: Item {
                    readonly property bool isActive: root.activeTab === modelData.key
                    width:  tabText.implicitWidth
                    height: parent.height

                    Text {
                        id: tabText
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr(modelData.label)
                        font.family: Theme.fontFamilyBody
                        font.pixelSize:    Theme.labelLg
                        font.weight:       isActive ? Font.Bold : Font.Medium
                        font.letterSpacing: Theme.lsWidest
                        color: isActive                 ? Theme.primary
                             : tabHover.containsMouse    ? Theme.fgSurface
                             :                              Theme.fgSurfaceVariant
                    }

                    // Active underline
                    Rectangle {
                        visible: isActive
                        anchors {
                            left: tabText.left; right: tabText.right
                            bottom: parent.bottom; bottomMargin: 4
                        }
                        height: 2
                        color: Theme.primary
                    }

                    MouseArea {
                        id: tabHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.key === "library")   root.librarySelected()
                            else if (modelData.key === "playlists") root.playlistsSelected()
                            else if (modelData.key === "search")    root.searchSelected()
                        }
                    }
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

            // About Topaz — rightmost (first from the right), deliberately a
            // bit bigger than the other icons (38×38 vs. their 32×32, tight
            // 3px image margin) so it stands out as the "info" affordance.
            // Row centers each child individually via anchors.verticalCenter
            // (not a RowLayout), so this doesn't affect the 64px bar height.
            Item {
                id: aboutButton
                width:  38
                height: 38
                anchors.verticalCenter: parent.verticalCenter

                // Background-highlight hover feedback (not a text-recolor)
                // since a raster PNG can't be recolored via `color:` the way
                // the gear glyph is — same technique as the volume button.
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusMd
                    color:  Theme.p10
                    visible: hoverAbout.containsMouse
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: 3
                    source: "qrc:/Topaz/InfoAbout.png"
                    sourceSize.width:  width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: hoverAbout
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.aboutRequested()
                }
            }
        }
    }
}
