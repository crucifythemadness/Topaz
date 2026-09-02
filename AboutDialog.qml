import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ── AboutDialog ──────────────────────────────────────────────────────────
// "About Topaz" modal with three tabs:
//   • TOPAZ        — app mark, name, version + build-date chips, description
//   • DEVELOPED BY — placeholder for now; user fills in real credits later
//   • POWERED BY   — intentionally empty for now; user adds a dependency/
//                    logo list later
//
// Same Popup/header/drag/close chrome as SetupDialog.qml, styled with the
// app's existing Theme.qml tokens throughout (not a one-off palette) so it
// stays visually consistent with every other dialog. Tab bar is bottom-
// placed with icon+label pairs (unlike SetupDialog's top text-only tabs) —
// a deliberate layout choice for this dialog, per the reference mockup.
//
// Usage in Main.qml:
//   AboutDialog { id: aboutDialog }
//   ...
//   aboutDialog.open()

Popup {
    id: root

    property LibraryModel libraryModel: null

    x: Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
    y: Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
    width:  560
    height: 760
    padding: 0

    modal: true
    closePolicy: Popup.NoAutoClose

    onAboutToShow: {
        x = Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
        y = Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                property real pressX: 0
                property real pressY: 0

                onPressed: (mouse) => { pressX = mouse.x; pressY = mouse.y }
                onPositionChanged: (mouse) => {
                    if (pressed) {
                        root.x += mouse.x - pressX
                        root.y += mouse.y - pressY
                    }
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                spacing: 0

                Text {
                    text: "ABOUT TOPAZ"
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusFull
                    color: closeHover.containsMouse
                           ? Theme.surfaceContainerHighest : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
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

        // ── Content area (one panel per tab, only one visible) ────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // PANEL 0 — TOPAZ
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 0

                BuildInfo { id: buildInfo }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 16

                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        source: "qrc:/Topaz/app.ico"
                        sourceSize.width:  128
                        sourceSize.height: 128
                        width:  128
                        height: 128
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        text: "TOPAZ JUKEBOX"
                        font.family:        Theme.fontFamilyHeadline
                        font.pixelSize:     Theme.displayLg
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWide
                        color: Theme.primary
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        spacing: 12

                        // Version chip
                        Rectangle {
                            height: 32
                            width:  versionLabel.implicitWidth + 100
                            radius: Theme.radiusFull
                            color:  Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.secondary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: versionLabel
                                    text: "VERSION " + buildInfo.version
                                    font.family:        Theme.fontFamilyMono
                                    font.pixelSize:     14
                                    font.weight:        Font.Medium
                                    font.letterSpacing: 0.8
                                    color: Theme.fgSurface
                                }
                            }
                        }

                        // Build-date chip
                        Rectangle {
                            height: 32
                            width:  buildDateLabel.implicitWidth + 100
                            radius: Theme.radiusFull
                            color:  Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.tertiary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: buildDateLabel
                                    text: "BUILT " + buildInfo.buildDate.toUpperCase()
                                    font.family:        Theme.fontFamilyMono
                                    font.pixelSize:     14
                                    font.weight:        Font.Medium
                                    font.letterSpacing: 0.8
                                    color: Theme.fgSurface
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        spacing: 12

                        // Track-count chip
                        Rectangle {
                            height: 32
                            width:  trackCountLabel.implicitWidth + 100
                            radius: Theme.radiusFull
                            color:  Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: trackCountLabel
                                    text: (root.libraryModel ? root.libraryModel.trackCount : 0) + " TRACKS"
                                    font.family:        Theme.fontFamilyMono
                                    font.pixelSize:     14
                                    font.weight:        Font.Medium
                                    font.letterSpacing: 0.8
                                    color: Theme.fgSurface
                                }
                            }
                        }

                        // Album-count chip
                        Rectangle {
                            height: 32
                            width:  albumCountLabel.implicitWidth + 100
                            radius: Theme.radiusFull
                            color:  Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.secondary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: albumCountLabel
                                    text: (root.libraryModel ? root.libraryModel.albumCount : 0) + " ALBUMS"
                                    font.family:        Theme.fontFamilyMono
                                    font.pixelSize:     14
                                    font.weight:        Font.Medium
                                    font.letterSpacing: 0.8
                                    color: Theme.fgSurface
                                }
                            }
                        }

                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 12
                        spacing: 12

                        // Rating-count chip
                        Rectangle {
                            height: 32
                            width:  ratingCountLabel.implicitWidth + 100
                            radius: Theme.radiusFull
                            color:  Theme.surfaceContainerHigh

                            Row {
                                anchors.centerIn: parent
                                spacing: 8

                                Rectangle {
                                    width: 10; height: 10
                                    radius: 5
                                    color: Theme.error
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    id: ratingCountLabel
                                    text: (root.libraryModel ? root.libraryModel.ratingCount : 0) + " RATINGS"
                                    font.family:        Theme.fontFamilyMono
                                    font.pixelSize:     14
                                    font.weight:        Font.Medium
                                    font.letterSpacing: 0.8
                                    color: Theme.fgSurface
                                }
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                        Layout.preferredWidth: 440
                        text: qsTr("A desktop audio jukebox that supports FLAC, MP3 and OPUS. A simple way to experience music in a different way. Simple yet sophisticated – for music lovers, offline collectors and parties. Developed as a Vibe-Coding project, using only Claude Sonnet 4.6 and 5.0, to demonstrate just how powerful these LLMs are.")
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.titleMd
                        color: Theme.fgSurfaceVariant
                    }
                }
            }

            // PANEL 1 — DEVELOPED BY
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 1

                ColumnLayout {
                    anchors { top: parent.top; left: parent.left; margins: 40 }
                    spacing: 40

                    // Claude
                    RowLayout {
                        Layout.alignment: Qt.AlignLeft
                        spacing: 20

                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: "qrc:/Topaz/Claude_Logo.png"
                            sourceSize.width:  128
                            sourceSize.height: 128
                            width:  128
                            height: 128
                            fillMode: Image.PreserveAspectFit
                        }

                        Text {
                            Layout.alignment: Qt.AlignVCenter
                            text: "https://claude.ai/"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            color: linkHoverClaude.containsMouse
                                   ? Theme.primary : Theme.fgSurfaceVariant

                            MouseArea {
                                id: linkHoverClaude
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://claude.ai/")
                            }
                        }
                    }

                    // CrucifyTheMadness
                    RowLayout {
                        Layout.alignment: Qt.AlignLeft
                        spacing: 20

                        Image {
                            Layout.alignment: Qt.AlignVCenter
                            source: "qrc:/Topaz/CrucifyTheMadness_Logo.png"
                            sourceSize.width:  128
                            sourceSize.height: 128
                            width:  128
                            height: 128
                            fillMode: Image.PreserveAspectFit
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 6

                            Text {
                                text: "https://github.com/crucifythemadness"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverGithub.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverGithub
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/crucifythemadness")
                                }
                            }

                            Text {
                                text: "https://m.twitch.tv/crucifythemadness/home"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverTwitch.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverTwitch
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://m.twitch.tv/crucifythemadness/home")
                                }
                            }

                            Text {
                                text: "https://bandcamp.com/crucifythemadness"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverBandcamp.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverBandcamp
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://bandcamp.com/crucifythemadness")
                                }
                            }
                        }
                    }

                    // Development process notes (first draft -- more to
                    // come; the dialog is sized with slack below this block
                    // for that).
                    ColumnLayout {
                        Layout.alignment: Qt.AlignLeft
                        Layout.topMargin: 16
                        spacing: 8

                        Text {
                            text: "Technology: C++ Qt (https://www.qt.io/)"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            color: linkHoverQt.containsMouse
                                   ? Theme.primary : Theme.fgSurfaceVariant

                            MouseArea {
                                id: linkHoverQt
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://www.qt.io/")
                            }
                        }

                        Text {
                            text: "IDE: Visual Studio Code with Qt Extensions and Claude Code Integration"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            text: "GUI Design: Google Stitch (https://stitch.withgoogle.com/)"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            color: linkHoverStitch.containsMouse
                                   ? Theme.primary : Theme.fgSurfaceVariant

                            MouseArea {
                                id: linkHoverStitch
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally("https://stitch.withgoogle.com/")
                            }
                        }

                        Text {
                            text: "LLM: Claude Sonnet 4.6 and 5.0"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            Layout.topMargin: 4
                            text: "Vibe Coding"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.italic:    true
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }
            }

            // PANEL 2 — POWERED BY
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 2

                // Scrollable (unlike DEVELOPED BY): more libraries may be
                // added here over time, so this panel scrolls instead of
                // needing the dialog resized each time.
                ScrollView {
                    id: poweredByScroll
                    anchors.fill: parent
                    anchors.margins: 40
                    clip: true

                    ColumnLayout {
                        width: poweredByScroll.availableWidth
                        spacing: 40

                        // Qt
                        RowLayout {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 20

                            Image {
                                Layout.alignment: Qt.AlignVCenter
                                source: "qrc:/Topaz/Qt_Logo.png"
                                sourceSize.width:  128
                                sourceSize.height: 128
                                width:  128
                                height: 128
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "https://www.qt.io/"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverQtLib.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverQtLib
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://www.qt.io/")
                                }
                            }
                        }

                        // FFmpeg
                        RowLayout {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 20

                            Image {
                                Layout.alignment: Qt.AlignVCenter
                                source: "qrc:/Topaz/FFmpeg_Logo.png"
                                sourceSize.width:  128
                                sourceSize.height: 128
                                width:  128
                                height: 128
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "https://ffmpeg.org/"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverFFmpeg.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverFFmpeg
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://ffmpeg.org/")
                                }
                            }
                        }

                        // ProjectM
                        RowLayout {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 20

                            Image {
                                Layout.alignment: Qt.AlignVCenter
                                source: "qrc:/Topaz/ProjectM_Logo.png"
                                sourceSize.width:  128
                                sourceSize.height: 128
                                width:  128
                                height: 128
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "https://github.com/projectM-visualizer/projectm"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverProjectM.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverProjectM
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/projectM-visualizer/projectm")
                                }
                            }
                        }

                        // KISS FFT -- no logo exists for this project, so a
                        // wordmark-style Text fills the same 128px-wide slot
                        // the logos occupy in the rows above, keeping the
                        // link column aligned across all four rows.
                        RowLayout {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 20

                            Text {
                                Layout.preferredWidth: 128
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: "KISS FFT"
                                font.family:    Theme.fontFamilyHeadline
                                font.pixelSize: Theme.headlineMd
                                font.weight:    Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "https://github.com/mborgerding/kissfft"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverKissFFT.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverKissFFT
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/mborgerding/kissfft")
                                }
                            }
                        }

                        // GLEW -- also no real logo, same wordmark treatment
                        // as KISS FFT above.
                        RowLayout {
                            Layout.alignment: Qt.AlignLeft
                            spacing: 20

                            Text {
                                Layout.preferredWidth: 128
                                Layout.alignment: Qt.AlignVCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: "GLEW"
                                font.family:    Theme.fontFamilyHeadline
                                font.pixelSize: Theme.headlineMd
                                font.weight:    Font.Bold
                                color: Theme.fgSurface
                            }

                            Text {
                                Layout.alignment: Qt.AlignVCenter
                                text: "https://github.com/nigels-com/glew"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: linkHoverGlew.containsMouse
                                       ? Theme.primary : Theme.fgSurfaceVariant

                                MouseArea {
                                    id: linkHoverGlew
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Qt.openUrlExternally("https://github.com/nigels-com/glew")
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Bottom tab bar ─────────────────────────────────────────────────
        Item {
            id: tabBar
            Layout.fillWidth: true
            height: 64

            property int currentTab: 0

            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: 1
                color:  Theme.ov10
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                Repeater {
                    model: [
                        { label: "TOPAZ",        icon: "◆" },
                        { label: "DEVELOPED BY", icon: "{ }"    },
                        { label: "POWERED BY",   icon: "▲" }
                    ]

                    delegate: Item {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true

                        readonly property bool isActive: tabBar.currentTab === index

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: Theme.radiusMd
                            color:  isActive ? Theme.p10 : "transparent"
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.icon
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: 16
                                color: isActive ? Theme.primary : Theme.fgSurfaceVariant
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        isActive ? Font.Bold : Font.Medium
                                font.letterSpacing: Theme.lsWide
                                color: isActive ? Theme.primary : Theme.fgSurfaceVariant
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    tabBar.currentTab = index
                        }
                    }
                }
            }
        }
    }
}
