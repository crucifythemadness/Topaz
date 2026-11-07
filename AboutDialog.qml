import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts

// ── AboutDialog ──────────────────────────────────────────────────────────
// "About Topaz" modal with three tabs:
//   • TOPAZ        — app icon, neon lettering (NeonWordmark), version/build-date
//                    and library-statistics chips, description
//   • DEVELOPED BY — people (Claude, CrucifyTheMadness) and the tools used
//   • POWERED BY   — grid of cards for every library/framework/asset Topaz uses,
//                    each opening a details page (version, license, role in
//                    Topaz, description, copyright, links) — no scrolling
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
                        Layout.preferredWidth:  128
                        Layout.preferredHeight: 128
                        // App icon (tools/generate-app-icon.py), PNG rather than
                        // app.ico: an Image doesn't reliably pick the largest frame.
                        source: "qrc:/Topaz/app_icon.png"
                        sourceSize.width:  128
                        sourceSize.height: 128
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }

                    // Neon lettering with glow, same as the top bar's
                    NeonWordmark {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        wordHeight: 48
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
                        text: qsTr("A desktop audio jukebox that supports FLAC, MP3 and OPUS. A simple way to experience music in a different way. Simple yet sophisticated – for music lovers, offline collectors and parties. Developed as a Vibe-Coding project, up to version 1.1.0 using only Claude Sonnet 4.6 and 5.0, to demonstrate just how powerful these LLMs are. Versions newer than 1.1.0 are made with the support of Claude Opus 5.5.")
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
                            text: "LLM: Claude Sonnet 4.6 and 5.0 (up to version 1.1.0)"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            color: Theme.fgSurfaceVariant
                        }

                        Text {
                            text: "LLM: Claude Opus 5.5 (versions newer than 1.1.0)"
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
            // A 2-column grid of cards that always fits without scrolling (the
            // user dislikes scrollbars in dialogs); clicking a card opens its
            // details page in the same panel -- version, license, what it does
            // in Topaz, what it is, copyright, links -- like MatryoshkaV2's
            // "About Qt" page. Back returns to the grid, Next steps through.
            // All facts live in the `libs` model below: to add a library, add
            // an entry (an odd count leaves one grid cell empty; 4 rows of 2
            // fill the panel exactly -- a 9th/10th entry needs a taller dialog
            // or a third column).
            Item {
                id: poweredBy
                anchors.fill: parent
                visible: tabBar.currentTab === 2

                property int detail: -1      // index into libs; -1 = grid
                readonly property var lib: detail >= 0 ? libs[detail] : null

                // Back to the grid whenever the tab is left or the dialog reopens
                onVisibleChanged: if (!visible) detail = -1

                // Versions: Qt from the running library; FFmpeg is the build
                // that ships with Qt Multimedia (read from deploy/avcodec-61.dll
                // -- update together with a Qt upgrade); projectM/GLEW from
                // CMakeLists.txt's FetchContent; miniz from MZ_VERSION.
                readonly property var libs: [
                    {
                        name: "Qt", logo: "qrc:/Topaz/Qt_Logo.png", mark: "",
                        role: qsTr("Application framework"),
                        version: buildInfo.qtVersion, license: "LGPL-3.0",
                        inTopaz: qsTr("The foundation Topaz is built on: the whole user interface (Qt Quick / QML), audio playback and output (Qt Multimedia), library scanning on background threads, folder monitoring, and the JSON settings, library and playlist files."),
                        about: qsTr("Qt is a C++ toolkit for cross-platform application development on all major desktop, embedded and mobile operating systems. Topaz uses the open-source edition under the GNU Lesser General Public License v3."),
                        copyright: qsTr("© The Qt Company Ltd. and other contributors. Qt and the Qt logo are trademarks of The Qt Company Ltd."),
                        links: ["https://www.qt.io/", "https://www.qt.io/licensing/"]
                    },
                    {
                        name: "FFmpeg", logo: "qrc:/Topaz/FFmpeg_Logo.png", mark: "",
                        role: qsTr("Audio decoding"),
                        version: qsTr("7.1.2 (via Qt Multimedia)"), license: "LGPL-2.1+",
                        inTopaz: qsTr("Decodes your FLAC, MP3 and Opus files: Qt Multimedia plays them through its FFmpeg backend, which also delivers the raw audio the visualizers analyse. Export's “Convert to MP3” uses a separate ffmpeg program with the LAME encoder that you supply yourself — it is not included."),
                        about: qsTr("FFmpeg is the leading multimedia framework, able to decode, encode, transcode, stream and filter almost any audio and video format."),
                        copyright: qsTr("© The FFmpeg developers. FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project."),
                        links: ["https://ffmpeg.org/", "https://ffmpeg.org/legal.html"]
                    },
                    {
                        name: "projectM", logo: "qrc:/Topaz/ProjectM_Logo.png", mark: "",
                        role: qsTr("Milkdrop visualizer"),
                        version: "4.1.7", license: "LGPL-2.1",
                        inTopaz: qsTr("Powers the Milkdrop visualizer pane: it renders classic Milkdrop presets in real time with OpenGL, driven by the music that is playing."),
                        about: qsTr("projectM is an open-source, cross-platform reimplementation of Milkdrop, the iconic music visualizer of Winamp."),
                        copyright: qsTr("© The projectM team and contributors."),
                        links: ["https://github.com/projectM-visualizer/projectm"]
                    },
                    {
                        name: "KISS FFT", logo: "", mark: "KISS FFT",
                        role: qsTr("Spectrum analysis"),
                        version: qsTr("bundled source"), license: "BSD-3-Clause",
                        inTopaz: qsTr("Calculates the frequency spectrum of the music (Fast Fourier Transform) for the bars of the audio visualizer pane. Its source code is compiled directly into Topaz."),
                        about: qsTr("“Keep It Simple, Stupid” FFT: a small, fast and portable FFT library written in C, with a deliberately simple interface."),
                        copyright: qsTr("© 2003–2010 Mark Borgerding and contributors."),
                        links: ["https://github.com/mborgerding/kissfft"]
                    },
                    {
                        name: "GLEW", logo: "", mark: "GLEW",
                        role: qsTr("OpenGL loader"),
                        version: "2.2.0", license: "BSD-3-Clause / MIT",
                        inTopaz: qsTr("Loads the OpenGL functions that projectM needs to draw the Milkdrop visualizer pane."),
                        about: qsTr("The OpenGL Extension Wrangler Library: a cross-platform C/C++ library that finds and loads OpenGL extensions and core functions at run time."),
                        copyright: qsTr("© 2002–2007 Milan Ikits, Marcelo E. Magallon, Lev Povalahev, and contributors."),
                        links: ["https://github.com/nigels-com/glew"]
                    },
                    {
                        name: "miniz", logo: "", mark: "MINIZ",
                        role: qsTr("Backup ZIP files"),
                        version: "11.3.2", license: "MIT",
                        inTopaz: qsTr("Writes and reads the ZIP archives of Backup and Restore (settings, ratings, playlists, library and loudness data). Its source code is compiled directly into Topaz."),
                        about: qsTr("A single-file, high-performance replacement for zlib, including ZIP archive reading and writing."),
                        copyright: qsTr("© 2010–2014 Rich Geldreich and Tenacious Software LLC, © 2013–2014 RAD Game Tools and Valve Software."),
                        links: ["https://github.com/richgel999/miniz"]
                    },
                    {
                        name: "BASS", logo: "", mark: "BASS",
                        role: qsTr("Optional audio engine"),
                        version: qsTr("your own copy"), license: qsTr("Proprietary"),
                        inTopaz: qsTr("An alternative playback engine you can choose in Setup instead of FFmpeg. Auto Loudness Correction needs it; its “Consistent Background Music” strategy also uses the BASS_FX add-on. Not included with Topaz — place your own licensed copy next to Topaz."),
                        about: qsTr("BASS is an audio library for Windows, Linux, macOS and mobile platforms, extended with add-ons for formats such as FLAC and Opus. Free for non-commercial use."),
                        copyright: qsTr("© Un4seen Developments Ltd."),
                        links: ["https://www.un4seen.com/"]
                    },
                    {
                        name: "Monoton", logo: "qrc:/Topaz/Topaz_Wordmark_Topaz.svg", mark: "",
                        role: qsTr("Lettering typeface"),
                        version: "Google Fonts", license: "SIL OFL 1.1",
                        inTopaz: qsTr("The neon “TOPAZ JUKEBOX” lettering in the top bar and in this dialog is drawn from Monoton's letter shapes. Only the outlines are used — the font itself is neither installed nor shipped."),
                        about: qsTr("Monoton is a display typeface built from parallel lines, giving letters a retro, neon-tube look."),
                        copyright: qsTr("© Vernon Adams."),
                        links: ["https://fonts.google.com/specimen/Monoton"]
                    }
                ]

                // Logo, or a bold name "wordmark" for projects without one
                component LibLogo: Item {
                    id: libLogo
                    property var entry: null
                    property int size: 56
                    implicitWidth:  size
                    implicitHeight: size
                    Image {
                        anchors.fill: parent
                        visible: libLogo.entry && libLogo.entry.logo !== ""
                        source: libLogo.entry ? libLogo.entry.logo : ""
                        sourceSize.width:  libLogo.size * 2
                        sourceSize.height: libLogo.size * 2
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        mipmap: true
                    }
                    Text {
                        anchors.fill: parent
                        visible: libLogo.entry && libLogo.entry.logo === ""
                        text: libLogo.entry ? libLogo.entry.mark : ""
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment:   Text.AlignVCenter
                        wrapMode: Text.WordWrap
                        font.family:    Theme.fontFamilyHeadline
                        font.pixelSize: Math.round(libLogo.size * 0.3)
                        font.weight:    Font.ExtraBold
                        color: Theme.fgSurface
                    }
                }

                // Small rounded fact chip (version / license)
                component Chip: Rectangle {
                    id: chip
                    property string label
                    property color dot: Theme.secondary
                    implicitHeight: 22
                    implicitWidth:  chipRow.implicitWidth + 20
                    radius: Theme.radiusFull
                    color:  Theme.surfaceContainerHighest
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            color: chip.dot
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: chip.label
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.labelMd
                            color: Theme.fgSurface
                        }
                    }
                }

                // Text button in the dialog's style
                component PanelButton: Rectangle {
                    id: panelButton
                    property string label
                    signal clicked()
                    implicitWidth:  buttonText.implicitWidth + 32
                    implicitHeight: 34
                    radius: Theme.radiusMd
                    color: buttonArea.containsMouse ? Theme.p20 : Theme.p10
                    Text {
                        id: buttonText
                        anchors.centerIn: parent
                        text: panelButton.label
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelLg
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWide
                        color: Theme.primary
                    }
                    MouseArea {
                        id: buttonArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panelButton.clicked()
                    }
                }

                // Small uppercase section label on the details page
                component SectionLabel: Text {
                    font.family:        Theme.fontFamilyBody
                    font.pixelSize:     Theme.labelMd
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.primary
                }

                // ── Grid of cards ────────────────────────────────────────
                ColumnLayout {
                    visible: poweredBy.detail < 0
                    anchors { fill: parent; margins: 24 }
                    spacing: 14

                    Text {
                        Layout.fillWidth: true
                        text: qsTr("Topaz is built with these open-source projects and tools. Click one for details.")
                        wrapMode: Text.WordWrap
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.titleMd
                        color: Theme.fgSurfaceVariant
                    }

                    GridLayout {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        columns: 2
                        rowSpacing:    12
                        columnSpacing: 12

                        Repeater {
                            model: poweredBy.libs

                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                required property int index
                                Layout.fillWidth:  true
                                Layout.fillHeight: true
                                Layout.preferredWidth: 1     // equal columns
                                radius: Theme.radiusLg
                                color: cardArea.containsMouse ? Theme.surfaceContainerHighest
                                                              : Theme.surfaceContainerHigh
                                border.width: 1
                                border.color: cardArea.containsMouse ? Theme.primary : Theme.ov10

                                RowLayout {
                                    anchors { fill: parent; margins: 14 }
                                    spacing: 14

                                    LibLogo {
                                        Layout.alignment: Qt.AlignVCenter
                                        entry: card.modelData
                                        size: 56
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth:  true
                                        Layout.fillHeight: true
                                        spacing: 4

                                        Text {
                                            Layout.fillWidth: true
                                            text: card.modelData.name
                                            elide: Text.ElideRight
                                            font.family:    Theme.fontFamilyHeadline
                                            font.pixelSize: Theme.headlineSm
                                            font.weight:    Font.Bold
                                            color: Theme.fgSurface
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: card.modelData.role
                                            elide: Text.ElideRight
                                            font.family:    Theme.fontFamilyBody
                                            font.pixelSize: Theme.labelXl
                                            color: Theme.fgSurfaceVariant
                                        }
                                        Item { Layout.fillHeight: true }
                                        Chip {
                                            label: card.modelData.license
                                            dot: Theme.tertiary
                                        }
                                        Text {
                                            text: qsTr("DETAILS ›")
                                            font.family:        Theme.fontFamilyBody
                                            font.pixelSize:     Theme.labelMd
                                            font.weight:        Font.Bold
                                            font.letterSpacing: Theme.lsWide
                                            color: cardArea.containsMouse ? Theme.primary
                                                                          : Theme.fgSurfaceVariant
                                        }
                                    }
                                }

                                MouseArea {
                                    id: cardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: poweredBy.detail = card.index
                                }
                            }
                        }
                    }
                }

                // ── Details page ─────────────────────────────────────────
                ColumnLayout {
                    visible: poweredBy.detail >= 0
                    anchors { fill: parent; margins: 32 }
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 20

                        LibLogo {
                            Layout.alignment: Qt.AlignTop
                            entry: poweredBy.lib
                            size: 96
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Text {
                                text: poweredBy.lib ? poweredBy.lib.name : ""
                                font.family:    Theme.fontFamilyHeadline
                                font.pixelSize: Theme.headlineLg
                                font.weight:    Font.Bold
                                color: Theme.fgSurface
                            }
                            Text {
                                text: poweredBy.lib ? poweredBy.lib.role : ""
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                color: Theme.fgSurfaceVariant
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8
                                Chip {
                                    label: poweredBy.lib ? qsTr("VERSION ") + poweredBy.lib.version : ""
                                    dot: Theme.secondary
                                }
                                Chip {
                                    label: poweredBy.lib ? poweredBy.lib.license : ""
                                    dot: Theme.tertiary
                                }
                            }
                        }
                    }

                    SectionLabel { Layout.topMargin: 8; text: qsTr("IN TOPAZ") }
                    Text {
                        Layout.fillWidth: true
                        text: poweredBy.lib ? poweredBy.lib.inTopaz : ""
                        wrapMode: Text.WordWrap
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.titleMd
                        lineHeight: 1.15
                        color: Theme.fgSurface
                    }

                    SectionLabel { Layout.topMargin: 6; text: qsTr("ABOUT") }
                    Text {
                        Layout.fillWidth: true
                        text: poweredBy.lib ? poweredBy.lib.about : ""
                        wrapMode: Text.WordWrap
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.titleMd
                        lineHeight: 1.15
                        color: Theme.fgSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        text: poweredBy.lib ? poweredBy.lib.copyright : ""
                        wrapMode: Text.WordWrap
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.labelLg
                        color: Theme.outline
                    }

                    // Links -- open in the browser
                    Repeater {
                        model: poweredBy.lib ? poweredBy.lib.links : []
                        delegate: Text {
                            required property string modelData
                            text: "↗  " + modelData
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.underline: linkArea.containsMouse
                            color: linkArea.containsMouse ? Theme.fgSurface : Theme.primary
                            MouseArea {
                                id: linkArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(parent.modelData)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        PanelButton {
                            label: qsTr("‹  BACK")
                            onClicked: poweredBy.detail = -1
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: (poweredBy.detail + 1) + " / " + poweredBy.libs.length
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }
                        PanelButton {
                            label: qsTr("NEXT  ›")
                            onClicked: poweredBy.detail = (poweredBy.detail + 1) % poweredBy.libs.length
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
