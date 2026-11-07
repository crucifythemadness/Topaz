import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
import QtQuick.Controls
import QtQuick.Layouts

// Header bar: Logo + "TOPAZ JUKEBOX" | Navigation tabs | Loudspeaker (volume
// knob) + Setup + About + Fullscreen/Window toggle, and in full screen (no OS
// title bar) also Minimize + Close.
Rectangle {
    id: root
    height: 76     // = MatryoshkaV2's on-screen bar (56 px × its fontScale 1.35)
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

    // Bound from Main.qml -- true while the main window is Window.FullScreen.
    // Picks the fullscreen/window toggle icon and shows Minimize + Close.
    property bool fullscreen: false

    // Fullscreen/window toggle (same as F11), Minimize and Close -- all
    // handled by Main.qml.
    signal fullscreenToggled()
    signal minimizeRequested()
    signal closeRequested()

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
        Image {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 12
            Layout.preferredWidth:  46   // = MatryoshkaV2's logo (34 px × 1.35)
            Layout.preferredHeight: 46
            // 256 px PNG of the app icon (tools/generate-app-icon.py), not
            // app.ico: an Image doesn't reliably pick the .ico's largest frame.
            source: "qrc:/Topaz/app_icon.png"
            sourceSize: Qt.size(92, 92)
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
        }

        // Neon "TOPAZ JUKEBOX" lettering with glow -- see NeonWordmark.qml
        // (shared with the About dialog).
        NeonWordmark {
            Layout.alignment: Qt.AlignVCenter
            wordHeight: 48
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
            spacing: 8

            // OS Volume (loudspeaker) -- opens a flyout pane with the volume
            // knob (VolumeKnob.qml). Leftmost of the right-side buttons.
            Item {
                id: volumeButton
                width:  46     // same as IconButton's default
                height: 46
                anchors.verticalCenter: parent.verticalCenter

                // Same look as the IconButtons next to it (size, radius,
                // p10 highlight, tinted line icon), but kept as a plain Item +
                // MouseArea: the popup below is parented to it and its close
                // timer reads hoverVolume.containsMouse. The highlight also
                // stays on while the knob pane is open.
                readonly property bool lit: hoverVolume.containsMouse || volumePopup.opened

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radiusMd
                    color:  volumeButton.lit ? Theme.p10 : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                }

                // Thin ring showing the current OS volume (a mini VolumeKnob);
                // live-synced through SystemVolumeController's NOTIFYs.
                VolumeRing {
                    anchors.fill: parent
                    anchors.margins: 2
                    value: root.systemVolume ? root.systemVolume.volume : 0
                    muted: root.systemVolume ? root.systemVolume.muted : false
                }

                SvgIcon {
                    anchors.centerIn: parent
                    size: 21       // ~half the ring's 42 px, so it sits clear inside
                    name: root.systemVolume && root.systemVolume.muted ? "volume-mute" : "volume"
                    color: volumeButton.lit ? Theme.primary : Theme.fgSurfaceVariant
                }

                ToolTip.visible: hoverVolume.containsMouse && !volumePopup.opened
                ToolTip.text: !root.systemVolume ? qsTr("System volume")
                            : root.systemVolume.muted ? qsTr("System volume: muted")
                            : qsTr("System volume: %1 %").arg(root.systemVolume.volume)
                ToolTip.delay: 500

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

                    // Transparent margin around the visible card that still
                    // counts as "inside the pane" for the hover-to-stay-open
                    // logic below, so a pointer that overshoots the card a
                    // little doesn't close it. Left/right/bottom only: the
                    // top one just bridges the 8 px gap under the button --
                    // a full margin there would reach up into the bar and
                    // cover (block clicks on) the Settings gear next door.
                    readonly property int hoverMargin: 32
                    readonly property int gapToButton: 8
                    readonly property int cardSize:    288   // square, 75 % of the old slider pane's ~385 px width

                    parent: volumeButton
                    // Card's right edge lines up with the button's right edge.
                    x: volumeButton.width - width + hoverMargin
                    y: volumeButton.height
                    padding: 0

                    modal: false
                    focus: false
                    closePolicy: Popup.NoAutoClose

                    background: Item {}   // transparent -- only the knob is visible

                    contentItem: Item {
                        implicitWidth:  volumePopup.cardSize + 2 * volumePopup.hoverMargin
                        implicitHeight: volumePopup.gapToButton + volumePopup.cardSize
                                        + volumePopup.hoverMargin

                        // Closes the pane once neither the button nor the
                        // pane (card + hover margin) has been hovered for a
                        // while, and never mid-drag. Debounced generously
                        // (700 ms) so moving the mouse from the button onto
                        // the knob, or briefly overshooting it, doesn't close
                        // the pane under the user.
                        HoverHandler {
                            id: hoverPane
                            onHoveredChanged: volumeCloseTimer.restart()
                        }
                        Timer {
                            id: volumeCloseTimer
                            interval: 700
                            onTriggered: {
                                if (!hoverVolume.containsMouse && !hoverPane.hovered
                                        && !volumeKnob.dragging)
                                    volumePopup.close()
                            }
                        }

                        // Invisible card: only the knob itself is drawn,
                        // floating over the window (user's choice -- no pane
                        // background or border). It still sets the knob's size
                        // and is part of the hover area.
                        Item {
                            x: volumePopup.hoverMargin
                            y: volumePopup.gapToButton
                            width:  volumePopup.cardSize
                            height: volumePopup.cardSize

                            VolumeKnob {
                                id: volumeKnob
                                anchors.fill: parent
                                anchors.margins: 14
                                value: root.systemVolume ? root.systemVolume.volume : 100
                                muted: root.systemVolume ? root.systemVolume.muted : false

                                // A drag that ends outside the pane closes it
                                // normally afterwards (the timer was held off
                                // only while dragging).
                                onDraggingChanged: if (!dragging) volumeCloseTimer.restart()

                                // Changing the level while muted unmutes, like
                                // the OS's own volume flyout.
                                onMoved: (v) => {
                                    if (!root.systemVolume) return
                                    if (root.systemVolume.muted) root.systemVolume.setMuted(false)
                                    root.systemVolume.setVolume(v)
                                }
                                onMuteToggled: {
                                    if (root.systemVolume)
                                        root.systemVolume.setMuted(!root.systemVolume.muted)
                                }
                            }
                        }
                    }
                }
            }

            // Icon buttons (IconButton.qml: tinted line icons from icons/).
            // Row centers each child via anchors.verticalCenter, so their
            // size doesn't affect the 64px bar height.
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "settings"
                tooltip: qsTr("Setup")
                onClicked: root.settingsRequested()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: "info"
                tooltip: qsTr("About Topaz")
                onClicked: root.aboutRequested()
            }
            IconButton {
                anchors.verticalCenter: parent.verticalCenter
                iconName: root.fullscreen ? "windowed" : "fullscreen"
                tooltip: root.fullscreen ? qsTr("Window (F11)") : qsTr("Full screen (F11)")
                onClicked: root.fullscreenToggled()
            }

            // Full screen only (no OS title bar there): divider, Minimize, Close.
            Rectangle {
                visible: root.fullscreen
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 28
                color: Theme.outlineVariant
            }
            IconButton {
                visible: root.fullscreen
                anchors.verticalCenter: parent.verticalCenter
                iconName: "minimize"
                tooltip: qsTr("Minimize")
                onClicked: root.minimizeRequested()
            }
            IconButton {
                visible: root.fullscreen
                anchors.verticalCenter: parent.verticalCenter
                iconName: "close"
                danger: true
                tooltip: qsTr("Close Topaz")
                onClicked: root.closeRequested()
            }
        }
    }
}
