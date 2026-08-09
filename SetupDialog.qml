import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ── SetupDialog ──────────────────────────────────────────────────────────
// Modal setup window with four tabs:
//   • GENRES        — add/delete genre names that drive GenreBar buttons
//   • FILE MONITORING — add/delete monitored folders (with subfolders toggle)
//   • CROSSFADE     — enable/disable crossfade and set its length (see UC-15)
//   • AUTO PLAY     — settings for the still-unimplemented AUTO PLAY feature:
//                     Queue Horizon lookahead, Consider Genre, and Consider
//                     Rating + Minimum Rating (see UC-14)
//
// Usage in Main.qml:
//   SetupDialog { id: setupDialog; appConfig: appConfig }
//   ...
//   setupDialog.open()

Popup {
    id: root

    // Required: bind to the AppConfig instance declared in Main.qml
    property AppConfig appConfig: null

    // ── Internal selection state ─────────────────────────────────────────
    property int selectedGenreIndex:  -1
    property int selectedFolderIndex: -1
    property int selectedMilkdropFolderIndex: -1

    // ── Geometry ─────────────────────────────────────────────────────────
    anchors.centerIn: Overlay.overlay
    width:  920   // widened so genreManageGrid's cells grow ~20% for longer genre names
    height: 760   // grown to fit the AUTO PLAY tab's 8th settings row (Exceptions,
                  // a single-row 3-option radio group)
    padding: 0

    modal: true
    closePolicy: Popup.NoAutoClose

    // Dark scrim behind the dialog
    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    // Dialog surface
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

            // Square off the bottom corners so they sit flush against content
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                spacing: 0

                Text {
                    text: "SETUP"
                    font.family:      Theme.fontFamilyHeadline
                    font.pixelSize:   Theme.headlineSm
                    font.weight:      Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                // Close ✕ button
                Rectangle {
                    width: 32; height: 32
                    radius: Theme.radiusFull
                    color: closeHover.containsMouse
                           ? Theme.surfaceContainerHighest : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"   // ✕
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

        // ── Tab bar ──────────────────────────────────────────────────────
        Item {
            id: tabBar
            Layout.fillWidth: true
            height: 44

            property int currentTab: 0

            Row {
                anchors { left: parent.left; leftMargin: 24 }
                height: parent.height
                spacing: 0

                Repeater {
                    model: ["GENRES", "FILE MONITORING", "CROSSFADE", "AUTO PLAY", "AUDIO VISUALIZER", "MILKDROP"]

                    delegate: Item {
                        width:  tabLabel.implicitWidth + 32
                        height: tabBar.height

                        readonly property bool isActive: tabBar.currentTab === index

                        Text {
                            id: tabLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        isActive ? Font.Bold : Font.Medium
                            font.letterSpacing: Theme.lsWidest
                            color: isActive ? Theme.primary : Theme.fgSurfaceVariant
                        }

                        // Active underline
                        Rectangle {
                            visible: isActive
                            anchors {
                                bottom: parent.bottom
                                horizontalCenter: parent.horizontalCenter
                            }
                            width:  tabLabel.implicitWidth
                            height: 2
                            color:  Theme.primary
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape:  Qt.PointingHandCursor
                            onClicked: {
                                tabBar.currentTab       = index
                                root.selectedGenreIndex  = -1
                                root.selectedFolderIndex = -1
                                root.selectedMilkdropFolderIndex = -1
                            }
                        }
                    }
                }
            }

            // Ghost bottom divider
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color:  Theme.ov10
            }
        }

        // ── Content area (both panels overlap; only one visible) ─────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // ────────────────────────────────────────────────────────────
            // PANEL 1 — GENRES
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 0

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 12

                    // Genre chips — scrollable area
                    Item {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true

                        // Empty-state hint
                        Text {
                            anchors.centerIn: parent
                            visible: !root.appConfig || root.appConfig.genres.length === 0
                            text: "No genres configured.\nType a genre name below and click ADD."
                            horizontalAlignment: Text.AlignHCenter
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }

                        // Fixed no-scroll grid — sized to hold up to 30 genres
                        // (6 columns × 5 rows), mirroring GenreBar's own
                        // fixed-capacity "Grid 30" pattern.
                        Grid {
                            id: genreManageGrid
                            anchors.fill: parent
                            visible: root.appConfig !== null && root.appConfig.genres.length > 0
                            clip: true              // defensive: beyond 30 genres, extra
                                                     // rows clip rather than overflow —
                                                     // same ceiling GenreBar accepts
                            columns: 6
                            rowSpacing:    8
                            columnSpacing: 8

                            Repeater {
                                model: root.appConfig ? root.appConfig.genres : []

                                delegate: Rectangle {
                                    id: genreCell
                                    width:  (genreManageGrid.width
                                             - (genreManageGrid.columns - 1) * genreManageGrid.columnSpacing)
                                            / genreManageGrid.columns
                                    height: 48
                                    radius: Theme.radiusSm

                                    readonly property bool isSelected:
                                        root.selectedGenreIndex === index

                                    color: isSelected
                                           ? Theme.secondaryContainer
                                           : cellHover.containsMouse
                                             ? Theme.surfaceContainerHighest
                                             : Theme.surfaceContainerHigh

                                    // Hover glow — matches GenreBar's micro-slab rule
                                    Rectangle {
                                        anchors { left: parent.left; right: parent.right; top: parent.top }
                                        height: 2
                                        color: Theme.primary
                                        visible: cellHover.containsMouse && !genreCell.isSelected
                                        radius: Theme.radiusSm
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.toUpperCase()
                                        font.family:        Theme.fontFamilyBody
                                        font.pixelSize:     Theme.labelMd
                                        font.letterSpacing: 1.2
                                        elide: Text.ElideRight
                                        width: parent.width - 12
                                        horizontalAlignment: Text.AlignHCenter
                                        color: genreCell.isSelected
                                               ? Theme.fgSecondaryContainer
                                               : Theme.fgSurfaceVariant
                                    }

                                    MouseArea {
                                        id: cellHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: root.selectedGenreIndex =
                                            (root.selectedGenreIndex === index) ? -1 : index
                                    }
                                }
                            }
                        }
                    }

                    // ── Add genre input row ──────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // Text input
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            color:  Theme.surfaceContainerHigh
                            radius: Theme.radiusSm
                            border.color: genreInput.activeFocus
                                          ? Theme.primary : "transparent"
                            border.width: 1

                            // Placeholder text
                            Text {
                                anchors { fill: genreInput }
                                visible: genreInput.text.length === 0
                                         && !genreInput.activeFocus
                                verticalAlignment: Text.AlignVCenter
                                text: "Type genre name and press Enter or ADD\u2026"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.labelLg
                                color: Theme.fgSurfaceVariant
                            }

                            TextInput {
                                id: genreInput
                                anchors {
                                    fill: parent
                                    leftMargin: 12; rightMargin: 12
                                }
                                verticalAlignment: TextInput.AlignVCenter
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.labelLg
                                color:      Theme.fgSurface
                                clip:       true
                                selectByMouse: true
                                Keys.onReturnPressed: root.doAddGenre()
                            }
                        }

                        // ADD button
                        Rectangle {
                            width: 80; height: 36
                            radius: Theme.radiusSm
                            color: addGHover.containsMouse
                                   ? Theme.primaryContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "ADD"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: addGHover.containsMouse
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: addGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    root.doAddGenre()
                            }
                        }
                    }

                    // ── Genre action buttons row ─────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }

                        // DELETE SELECTED
                        Rectangle {
                            width: 162; height: 32
                            radius: Theme.radiusSm
                            opacity: root.selectedGenreIndex >= 0 ? 1.0 : 0.35
                            color: delGHover.containsMouse
                                   && root.selectedGenreIndex >= 0
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE SELECTED"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  root.selectedGenreIndex >= 0
                                              ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.selectedGenreIndex >= 0 && root.appConfig) {
                                        root.appConfig.removeGenreAt(root.selectedGenreIndex)
                                        root.selectedGenreIndex = -1
                                    }
                                }
                            }
                        }

                        // DELETE ALL
                        Rectangle {
                            width: 120; height: 32
                            radius: Theme.radiusSm
                            color: delAllGHover.containsMouse
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE ALL"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delAllGHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig) {
                                        root.appConfig.clearGenres()
                                        root.selectedGenreIndex = -1
                                    }
                                }
                            }
                        }
                    }
                }
            } // end GENRES panel

            // ────────────────────────────────────────────────────────────
            // PANEL 2 — FILE MONITORING
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 1

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 12

                    // Column header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30
                        color:  Theme.surfaceContainerHigh
                        radius: Theme.radiusSm

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            Text {
                                Layout.fillWidth: true
                                text: "FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                            }
                            Text {
                                width: 100
                                text: "SUBFOLDERS"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelXs
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWidest
                                color: Theme.fgSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    // Folder list
                    Item {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true

                        // Empty-state hint
                        Text {
                            anchors.centerIn: parent
                            visible: !root.appConfig || root.appConfig.folders.length === 0
                            text: "No folders configured.\nClick ADD FOLDER to add a music directory."
                            horizontalAlignment: Text.AlignHCenter
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }

                        ScrollView {
                            anchors.fill: parent
                            visible: root.appConfig !== null
                                     && root.appConfig.folders.length > 0
                            clip: true

                            ListView {
                                id: folderList
                                model: root.appConfig ? root.appConfig.folders : []
                                spacing: 3

                                delegate: Rectangle {
                                    width:  folderList.width
                                    height: 38
                                    radius: Theme.radiusSm

                                    readonly property bool isSelected:
                                        root.selectedFolderIndex === index

                                    color: isSelected
                                           ? Theme.p10
                                           : rowHover.containsMouse
                                             ? Theme.surfaceContainerHigh
                                             : Theme.surfaceContainer

                                    RowLayout {
                                        anchors {
                                            fill: parent
                                            leftMargin: 12; rightMargin: 12
                                        }
                                        spacing: 8

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.path
                                            font.family:    Theme.fontFamilyMono
                                            font.pixelSize: Theme.monoLg
                                            color: Theme.fgSurface
                                            elide: Text.ElideMiddle
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        // Subfolders checkbox cell
                                        Item {
                                            width:  100
                                            height: parent.height

                                            Rectangle {
                                                width: 18; height: 18
                                                anchors.centerIn: parent
                                                radius: 3
                                                color: modelData.includeSubfolders
                                                       ? Theme.secondaryContainer
                                                       : "transparent"
                                                border.width: modelData.includeSubfolders ? 0 : 1
                                                border.color: Theme.outlineVariant

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: modelData.includeSubfolders
                                                    text: "\u2713"   // ✓
                                                    font.pixelSize: 11
                                                    font.weight:    Font.Bold
                                                    color: Theme.fgSecondaryContainer
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape:  Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (root.appConfig)
                                                            root.appConfig.setFolderSubfolders(
                                                                index,
                                                                !modelData.includeSubfolders)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Row-level click (select / deselect)
                                    MouseArea {
                                        id: rowHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        z: -1   // checkbox MouseArea sits on top
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedFolderIndex =
                                            (root.selectedFolderIndex === index) ? -1 : index
                                    }
                                }
                            }
                        }
                    }

                    // ── Folder action buttons row ────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        // ADD FOLDER
                        Rectangle {
                            width: 130; height: 32
                            radius: Theme.radiusSm
                            color: addFHover.containsMouse
                                   ? Theme.primaryContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "ADD FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: addFHover.containsMouse
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: addFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    folderDialog.open()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // DELETE SELECTED
                        Rectangle {
                            width: 162; height: 32
                            radius: Theme.radiusSm
                            opacity: root.selectedFolderIndex >= 0 ? 1.0 : 0.35
                            color: delFHover.containsMouse
                                   && root.selectedFolderIndex >= 0
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE SELECTED"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  root.selectedFolderIndex >= 0
                                              ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.selectedFolderIndex >= 0 && root.appConfig) {
                                        root.appConfig.removeFolderAt(root.selectedFolderIndex)
                                        root.selectedFolderIndex = -1
                                    }
                                }
                            }
                        }

                        // DELETE ALL
                        Rectangle {
                            width: 120; height: 32
                            radius: Theme.radiusSm
                            color: delAllFHover.containsMouse
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE ALL"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delAllFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig) {
                                        root.appConfig.clearFolders()
                                        root.selectedFolderIndex = -1
                                    }
                                }
                            }
                        }
                    }
                }
            } // end FILE MONITORING panel

            // ────────────────────────────────────────────────────────────
            // PANEL 3 — CROSSFADE
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 2

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 40

                    readonly property bool crossfadeOn:
                        root.appConfig !== null && root.appConfig.crossfadeEnabled

                    // ── Crossfade on/off row ──────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Crossfade"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Activate/Deactivate linear Fading-In/Fading-Out")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as PlaybackQueue's
                        // LOCK PLAYLIST toggle, scaled up (48×24 / 18×18) for more
                        // prominence in this dialog.
                        Rectangle {
                            id: crossfadeTrack

                            readonly property bool crossfadeOn:
                                root.appConfig !== null && root.appConfig.crossfadeEnabled

                            width: 48; height: 24
                            radius: 12
                            color: crossfadeOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: crossfadeTrack.crossfadeOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setCrossfadeEnabled(
                                            !root.appConfig.crossfadeEnabled)
                                }
                            }
                        }
                    }

                    // ── Length row ─────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        spacing: 8
                        opacity: parent.crossfadeOn ? 1.0 : 0.35

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Length"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("Time duration of Fading-In the next Track whilst Fading-Out the actual Track")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: crossfadeSlider.value.toFixed(1) + " s"
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
                                text: "2.0 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: crossfadeSlider
                                Layout.fillWidth: true
                                enabled: root.appConfig !== null
                                         && root.appConfig.crossfadeEnabled
                                from: 2.0
                                to:   10.0
                                stepSize: 0.5
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.crossfadeSeconds : 5.0

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setCrossfadeSeconds(value)
                                }

                                background: Rectangle {
                                    x: crossfadeSlider.leftPadding
                                    y: crossfadeSlider.topPadding
                                       + crossfadeSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  crossfadeSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  crossfadeSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: crossfadeSlider.leftPadding
                                       + crossfadeSlider.visualPosition
                                         * (crossfadeSlider.availableWidth - width)
                                    y: crossfadeSlider.topPadding
                                       + crossfadeSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "10.0 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end CROSSFADE panel

            // ────────────────────────────────────────────────────────────
            // PANEL 4 — AUTO PLAY
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 3

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 40

                    // ── Queue Horizon row ─────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Queue Horizon"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How many Tracks are pre-loaded with AUTO PLAY")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(queueHorizonSlider.value) + " tracks"
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
                                text: "1"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: queueHorizonSlider
                                Layout.fillWidth: true
                                from: 1
                                to:   15
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.autoPlayQueueHorizon : 5

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayQueueHorizon(
                                            Math.round(value))
                                }

                                background: Rectangle {
                                    x: queueHorizonSlider.leftPadding
                                    y: queueHorizonSlider.topPadding
                                       + queueHorizonSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  queueHorizonSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  queueHorizonSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: queueHorizonSlider.leftPadding
                                       + queueHorizonSlider.visualPosition
                                         * (queueHorizonSlider.availableWidth - width)
                                    y: queueHorizonSlider.topPadding
                                       + queueHorizonSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "15"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Title Adding row ──────────────────────────────
                    // Polling interval AUTO PLAY will use to add one new track at
                    // a time to the queue (see UC-14 design note).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Title Adding"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("Interval until the next Track will be added")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(titleAddingSlider.value) + " s"
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
                                text: "5 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: titleAddingSlider
                                Layout.fillWidth: true
                                from: 5
                                to:   90
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.autoPlayTitleAddingIntervalSeconds : 30

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayTitleAddingIntervalSeconds(
                                            Math.round(value))
                                }

                                background: Rectangle {
                                    x: titleAddingSlider.leftPadding
                                    y: titleAddingSlider.topPadding
                                       + titleAddingSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  titleAddingSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  titleAddingSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: titleAddingSlider.leftPadding
                                       + titleAddingSlider.visualPosition
                                         * (titleAddingSlider.availableWidth - width)
                                    y: titleAddingSlider.topPadding
                                       + titleAddingSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "90 s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Consider Genre row ────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Consider Genre"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the CROSSFADE tab's
                        // on/off toggle.
                        Rectangle {
                            id: considerGenreTrack

                            readonly property bool considerGenreOn:
                                root.appConfig !== null && root.appConfig.autoPlayConsiderGenre

                            width: 48; height: 24
                            radius: 12
                            color: considerGenreOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: considerGenreTrack.considerGenreOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayConsiderGenre(
                                            !root.appConfig.autoPlayConsiderGenre)
                                }
                            }
                        }
                    }

                    // ── Consider Rating row ───────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Consider Rating"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the CROSSFADE tab's
                        // and Consider Genre's on/off toggle.
                        Rectangle {
                            id: considerRatingTrack

                            readonly property bool considerRatingOn:
                                root.appConfig !== null && root.appConfig.autoPlayConsiderRating

                            width: 48; height: 24
                            radius: 12
                            color: considerRatingOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: considerRatingTrack.considerRatingOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayConsiderRating(
                                            !root.appConfig.autoPlayConsiderRating)
                                }
                            }
                        }
                    }

                    // ── Minimum Rating row ─────────────────────────────
                    // Enabled/visible-strength only while Consider Rating is on.
                    // Stars mirror NowPlaying.qml's rating-star Repeater — same
                    // glyph, size, and blue palette — but drive
                    // appConfig.autoPlayMinimumRating instead of the currently
                    // playing track's rating. A plain Item (not RowLayout) is used
                    // so the star Row can be explicitly positioned against
                    // queueHorizonSlider's right edge above — Layout-managed items
                    // can't carry anchors, and Qt Quick anchors only work between
                    // siblings/parent anyway (queueHorizonSlider is neither), hence
                    // the explicit x binding below instead of anchors.right.
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(minRatingLabel.implicitHeight, 18)
                        enabled: root.appConfig !== null && root.appConfig.autoPlayConsiderRating
                        opacity: enabled ? 1.0 : 0.35

                        Text {
                            id: minRatingLabel
                            anchors.left: parent.left
                            anchors.leftMargin: 24
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Minimum Rating"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Medium
                            color: Theme.fgSurface
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            x: queueHorizonSlider.x + queueHorizonSlider.width - width
                            spacing: 3

                            Repeater {
                                model: 10

                                delegate: Text {
                                    text: "★"   // ★
                                    font.pixelSize: 18

                                    readonly property bool filled:
                                        root.appConfig && index < root.appConfig.autoPlayMinimumRating

                                    color: filled                    ? "#00A6ED"
                                         : minRatingMA.containsMouse ? Qt.rgba(0, 0.651, 0.929, 0.45)
                                         :                             Theme.outlineVariant

                                    MouseArea {
                                        id: minRatingMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape:  Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAutoPlayMinimumRating(index + 1)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── Allow Manual Modification + Exceptions group ───
                    // Wrapped together (tight spacing: 16) so "Exceptions" reads
                    // clearly as belonging to "Allow Manual Modification" above it,
                    // distinct from the outer panel's spacing: 40 between unrelated
                    // rows/blocks.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 16

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Allow Manual Modification"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the CROSSFADE tab's
                        // and Consider Genre's on/off toggle.
                        Rectangle {
                            id: allowManualModificationTrack

                            readonly property bool allowManualModificationOn:
                                root.appConfig !== null && root.appConfig.autoPlayAllowManualModification

                            width: 48; height: 24
                            radius: 12
                            color: allowManualModificationOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: allowManualModificationTrack.allowManualModificationOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAutoPlayAllowManualModification(
                                            !root.appConfig.autoPlayAllowManualModification)
                                }
                            }
                        }
                    }

                    // ── Exceptions row (dependent on Allow Manual Modification) ──
                    // Only interactive while Allow Manual Modification is OFF —
                    // governs what limited manual interaction (if any) remains
                    // possible during an active AUTO PLAY session. Dimmed/disabled
                    // the opposite way Minimum Rating is: here the row goes inert
                    // when its parent toggle is ON, since it's then moot (full
                    // manual control already applies).
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        spacing: 12
                        enabled: root.appConfig !== null && !root.appConfig.autoPlayAllowManualModification
                        opacity: enabled ? 1.0 : 0.35

                        Text {
                            text: "Exceptions"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Row {
                            Layout.leftMargin: 24
                            spacing: 32

                            Repeater {
                                model: [
                                    { value: "nothing",            label: "Nothing" },
                                    { value: "playPause",          label: "Play/Pause allowed" },
                                    { value: "playPauseAndSelect", label: "Play/Pause & Select another Track allowed" }
                                ]

                                delegate: RowLayout {
                                    spacing: 8

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.autoPlayTransportAccess === modelData.value

                                    Rectangle {
                                        width: 18; height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 2
                                        border.color: selected ? Theme.secondary : Theme.outlineVariant

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10
                                            radius: 5
                                            color: Theme.secondary
                                            visible: selected
                                        }
                                    }

                                    Text {
                                        text: modelData.label
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelLg
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAutoPlayTransportAccess(modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    } // end Allow Manual Modification + Exceptions group

                    // ── Play a Song row ────────────────────────────────
                    // First radio-button control in the app: a single row of
                    // mutually-exclusive song-repeat modes. Circle border/dot
                    // colors match every other AUTO PLAY control's selected/
                    // unselected pairing (Theme.secondary / Theme.outlineVariant).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Play a Title"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Grid {
                            Layout.leftMargin: 24
                            columns: 4
                            rowSpacing:    12
                            columnSpacing: 32

                            Repeater {
                                model: [
                                    { value: "once",                  label: "Once" },
                                    { value: "twice",                 label: "Twice" },
                                    { value: "twiceIfNoneAvailable",  label: "Twice when no other available" },
                                    { value: "several",               label: "Several times" }
                                ]

                                delegate: RowLayout {
                                    spacing: 8

                                    readonly property bool selected:
                                        root.appConfig !== null
                                        && root.appConfig.autoPlaySongRepeat === modelData.value

                                    Rectangle {
                                        width: 18; height: 18
                                        radius: 9
                                        color: "transparent"
                                        border.width: 2
                                        border.color: selected ? Theme.secondary : Theme.outlineVariant

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 10; height: 10
                                            radius: 5
                                            color: Theme.secondary
                                            visible: selected
                                        }
                                    }

                                    Text {
                                        text: modelData.label
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelLg
                                        color: Theme.fgSurface
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAutoPlaySongRepeat(modelData.value)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end AUTO PLAY panel

            // ────────────────────────────────────────────────────────────
            // PANEL 5 — AUDIO VISUALIZER
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 4

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 40

                    // ── Bar Count row ──────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Bar Count"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How many bars the Audio Visualizer pane shows")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(barCountSlider.value) + " bars"
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
                                text: "8"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: barCountSlider
                                Layout.fillWidth: true
                                from: 8
                                to:   64
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerBarCount : 24

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerBarCount(
                                            Math.round(value))
                                }

                                background: Rectangle {
                                    x: barCountSlider.leftPadding
                                    y: barCountSlider.topPadding
                                       + barCountSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  barCountSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  barCountSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: barCountSlider.leftPadding
                                       + barCountSlider.visualPosition
                                         * (barCountSlider.availableWidth - width)
                                    y: barCountSlider.topPadding
                                       + barCountSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "64"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Decay Speed row ────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Decay Speed"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How quickly bars fall after a peak")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: decaySpeedSlider.value.toFixed(2)
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
                                text: "SLOW"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: decaySpeedSlider
                                Layout.fillWidth: true
                                from: 0.0
                                to:   1.0
                                stepSize: 0.05
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerDecaySpeed : 0.5

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerDecaySpeed(value)
                                }

                                background: Rectangle {
                                    x: decaySpeedSlider.leftPadding
                                    y: decaySpeedSlider.topPadding
                                       + decaySpeedSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  decaySpeedSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  decaySpeedSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: decaySpeedSlider.leftPadding
                                       + decaySpeedSlider.visualPosition
                                         * (decaySpeedSlider.availableWidth - width)
                                    y: decaySpeedSlider.topPadding
                                       + decaySpeedSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "FAST"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Sensitivity row ─────────────────────────────────
                    // How high the bars react to a given signal level — gain
                    // offset applied before AudioVisualizerController's dB
                    // normalization. 50% matches the original, unmodified
                    // response; higher pushes bars closer to full height on
                    // loud passages, lower makes them noticeably less reactive.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Sensitivity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How high the bars react to the current signal — 50% matches the default response")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(sensitivitySlider.value) + "%"
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
                                text: "LOW"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: sensitivitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerSensitivity * 100 : 50

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerSensitivity(value / 100)
                                }

                                background: Rectangle {
                                    x: sensitivitySlider.leftPadding
                                    y: sensitivitySlider.topPadding
                                       + sensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  sensitivitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  sensitivitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: sensitivitySlider.leftPadding
                                       + sensitivitySlider.visualPosition
                                         * (sensitivitySlider.availableWidth - width)
                                    y: sensitivitySlider.topPadding
                                       + sensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "HIGH"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Peak Hold row ──────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Peak Hold"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Show a lingering marker at each bar's recent peak")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Toggle switch — same visual pattern as the CROSSFADE
                        // tab's on/off toggle.
                        Rectangle {
                            id: peakHoldTrack

                            readonly property bool peakHoldOn:
                                root.appConfig !== null && root.appConfig.audioVisualizerPeakHoldEnabled

                            width: 48; height: 24
                            radius: 12
                            color: peakHoldOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: peakHoldTrack.peakHoldOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerPeakHoldEnabled(
                                            !root.appConfig.audioVisualizerPeakHoldEnabled)
                                }
                            }
                        }
                    }

                    // ── Pane Opacity row ────────────────────────────────
                    // Background-only opacity — the bars themselves always
                    // stay fully opaque, only the pane's own background fades.
                    // See AudioVisualizerWindow.qml.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Pane Opacity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true

                                    ToolTip.visible: containsMouse
                                    ToolTip.delay:   600
                                    ToolTip.text:    qsTr("How visible the pane's background is — the bars themselves always stay fully visible")
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(paneOpacitySlider.value) + "%"
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
                                text: "0%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: paneOpacitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.audioVisualizerPaneOpacity * 100 : 100

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setAudioVisualizerPaneOpacity(value / 100)
                                }

                                background: Rectangle {
                                    x: paneOpacitySlider.leftPadding
                                    y: paneOpacitySlider.topPadding
                                       + paneOpacitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  paneOpacitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  paneOpacitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: paneOpacitySlider.leftPadding
                                       + paneOpacitySlider.visualPosition
                                         * (paneOpacitySlider.availableWidth - width)
                                    y: paneOpacitySlider.topPadding
                                       + paneOpacitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "100%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Color row ───────────────────────────────────────
                    // Preset swatches rather than a full HSV/RGB picker —
                    // same "Repeater over an options array compared against
                    // one AppConfig value" idiom as the AUTO PLAY radio
                    // groups above, just rendered as color chips instead of
                    // labeled circles.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "Color"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Grid {
                            Layout.leftMargin: 24
                            columns: 16   // 32 swatches → exactly two full rows
                            spacing: 16

                            Repeater {
                                model: [
                                    // Original 8 — kept as-is (4 already match
                                    // Theme tokens: secondary/primary/tertiary/fgSurface)
                                    "#00DAF3", "#44E2CD", "#D0BCFF", "#FFB869",
                                    "#FF6B6B", "#7CFF6B", "#FFE066", "#E5E2E1",
                                    // 24 additional presets — a saturated spread
                                    // across the hue wheel for clear visual
                                    // distinction against the pane's dark background
                                    "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
                                    "#00C7BE", "#30B0C7", "#007AFF", "#5856D6",
                                    "#AF52DE", "#FF2D55", "#FF6482", "#A2845E",
                                    "#8E8E93", "#64D2FF", "#BF5AF2", "#32ADE6",
                                    "#FFD60A", "#4CD964", "#FF7A45", "#C77DFF",
                                    "#06D6A0", "#EF476F", "#FFD166", "#118AB2"
                                ]

                                delegate: Rectangle {
                                    width: 32; height: 32
                                    radius: 16
                                    color: modelData
                                    border.width: (root.appConfig && root.appConfig.audioVisualizerColor === modelData) ? 3 : 1
                                    border.color: (root.appConfig && root.appConfig.audioVisualizerColor === modelData) ? Theme.fgSurface : Theme.outlineVariant

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.appConfig)
                                                root.appConfig.setAudioVisualizerColor(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end AUDIO VISUALIZER panel

            // ────────────────────────────────────────────────────────────
            // PANEL 6 — MILKDROP
            // ────────────────────────────────────────────────────────────
            Item {
                anchors.fill: parent
                visible: tabBar.currentTab === 5

                ColumnLayout {
                    anchors { fill: parent; margins: 24 }
                    spacing: 20

                    // ── Preset folder list ──────────────────────────────
                    Text {
                        text: "Preset Folders"
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.titleMd
                        font.weight:    Font.Bold
                        color: Theme.fgSurface
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140

                        Text {
                            anchors.centerIn: parent
                            visible: !root.appConfig || root.appConfig.milkdropPresetFolders.length === 0
                            text: "No preset folders configured.\nClick ADD FOLDER to point at a downloaded .milk preset pack."
                            horizontalAlignment: Text.AlignHCenter
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }

                        ScrollView {
                            anchors.fill: parent
                            visible: root.appConfig !== null
                                     && root.appConfig.milkdropPresetFolders.length > 0
                            clip: true

                            ListView {
                                id: milkdropFolderList
                                model: root.appConfig ? root.appConfig.milkdropPresetFolders : []
                                spacing: 3

                                delegate: Rectangle {
                                    width:  milkdropFolderList.width
                                    height: 38
                                    radius: Theme.radiusSm

                                    readonly property bool isSelected:
                                        root.selectedMilkdropFolderIndex === index

                                    color: isSelected
                                           ? Theme.p10
                                           : mdRowHover.containsMouse
                                             ? Theme.surfaceContainerHigh
                                             : Theme.surfaceContainer

                                    Text {
                                        anchors {
                                            fill: parent
                                            leftMargin: 12; rightMargin: 12
                                        }
                                        text: modelData
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoLg
                                        color: Theme.fgSurface
                                        elide: Text.ElideMiddle
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    MouseArea {
                                        id: mdRowHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.selectedMilkdropFolderIndex =
                                            (root.selectedMilkdropFolderIndex === index) ? -1 : index
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 130; height: 32
                            radius: Theme.radiusSm
                            color: addMdFHover.containsMouse
                                   ? Theme.primaryContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "ADD FOLDER"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: addMdFHover.containsMouse
                                       ? Theme.fgPrimaryContainer : Theme.primary
                            }
                            MouseArea {
                                id: addMdFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    milkdropFolderDialog.open()
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 162; height: 32
                            radius: Theme.radiusSm
                            opacity: root.selectedMilkdropFolderIndex >= 0 ? 1.0 : 0.35
                            color: delMdFHover.containsMouse
                                   && root.selectedMilkdropFolderIndex >= 0
                                   ? Theme.errorContainer
                                   : Theme.surfaceContainerHigh

                            Text {
                                anchors.centerIn: parent
                                text: "DELETE SELECTED"
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.error
                            }
                            MouseArea {
                                id: delMdFHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  root.selectedMilkdropFolderIndex >= 0
                                              ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.selectedMilkdropFolderIndex >= 0 && root.appConfig) {
                                        root.appConfig.removeMilkdropPresetFolderAt(root.selectedMilkdropFolderIndex)
                                        root.selectedMilkdropFolderIndex = -1
                                    }
                                }
                            }
                        }
                    }

                    // ── Shuffle row ──────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Shuffle Presets"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: shuffleTrack
                            readonly property bool shuffleOn:
                                root.appConfig !== null && root.appConfig.milkdropShuffleEnabled
                            width: 48; height: 24
                            radius: 12
                            color: shuffleOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: shuffleTrack.shuffleOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropShuffleEnabled(
                                            !root.appConfig.milkdropShuffleEnabled)
                                }
                            }
                        }
                    }

                    // ── Preset Duration row ──────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Preset Duration"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(presetDurationSlider.value) + "s"
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
                                text: "5s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: presetDurationSlider
                                Layout.fillWidth: true
                                from: 5
                                to:   120
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.milkdropPresetDuration : 20

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropPresetDuration(value)
                                }

                                background: Rectangle {
                                    x: presetDurationSlider.leftPadding
                                    y: presetDurationSlider.topPadding
                                       + presetDurationSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  presetDurationSlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  presetDurationSlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: presetDurationSlider.leftPadding
                                       + presetDurationSlider.visualPosition
                                         * (presetDurationSlider.availableWidth - width)
                                    y: presetDurationSlider.topPadding
                                       + presetDurationSlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "120s"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Beat Sensitivity row ─────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Beat Sensitivity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: beatSensitivitySlider.value.toFixed(2)
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
                                text: "LOW"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: beatSensitivitySlider
                                Layout.fillWidth: true
                                from: 0.0
                                to:   4.0
                                stepSize: 0.1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.milkdropBeatSensitivity : 1.0

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropBeatSensitivity(value)
                                }

                                background: Rectangle {
                                    x: beatSensitivitySlider.leftPadding
                                    y: beatSensitivitySlider.topPadding
                                       + beatSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  beatSensitivitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  beatSensitivitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: beatSensitivitySlider.leftPadding
                                       + beatSensitivitySlider.visualPosition
                                         * (beatSensitivitySlider.availableWidth - width)
                                    y: beatSensitivitySlider.topPadding
                                       + beatSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "HIGH"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Hard Cuts row ─────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Hard Cuts"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Beat-triggered instant preset changes, instead of always smoothly transitioning")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: hardCutsTrack
                            readonly property bool hardCutsOn:
                                root.appConfig !== null && root.appConfig.milkdropHardCutsEnabled
                            width: 48; height: 24
                            radius: 12
                            color: hardCutsOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: hardCutsTrack.hardCutsOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropHardCutsEnabled(
                                            !root.appConfig.milkdropHardCutsEnabled)
                                }
                            }
                        }
                    }

                    // ── Hard Cut Sensitivity row ──────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "Hard Cut Sensitivity"
                                font.family:    Theme.fontFamilyBody
                                font.pixelSize: Theme.titleMd
                                font.weight:    Font.Medium
                                color: Theme.fgSurface
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: Math.round(hardCutSensitivitySlider.value) + "%"
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
                                text: "0%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }

                            Slider {
                                id: hardCutSensitivitySlider
                                Layout.fillWidth: true
                                from: 0
                                to:   100
                                stepSize: 1
                                snapMode: Slider.SnapAlways
                                value: root.appConfig ? root.appConfig.milkdropHardCutSensitivity * 100 : 60

                                onMoved: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropHardCutSensitivity(value / 100)
                                }

                                background: Rectangle {
                                    x: hardCutSensitivitySlider.leftPadding
                                    y: hardCutSensitivitySlider.topPadding
                                       + hardCutSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  200
                                    implicitHeight: 4
                                    width:  hardCutSensitivitySlider.availableWidth
                                    height: implicitHeight
                                    radius: 2
                                    color:  Theme.surfaceContainerHighest

                                    Rectangle {
                                        width:  hardCutSensitivitySlider.visualPosition * parent.width
                                        height: parent.height
                                        radius: 2
                                        color:  Theme.secondary
                                    }
                                }

                                handle: Rectangle {
                                    x: hardCutSensitivitySlider.leftPadding
                                       + hardCutSensitivitySlider.visualPosition
                                         * (hardCutSensitivitySlider.availableWidth - width)
                                    y: hardCutSensitivitySlider.topPadding
                                       + hardCutSensitivitySlider.availableHeight / 2 - height / 2
                                    implicitWidth:  16
                                    implicitHeight: 16
                                    width:  implicitWidth
                                    height: implicitHeight
                                    radius: 8
                                    color: Theme.secondary
                                }
                            }

                            Text {
                                text: "100%"
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.labelSm
                                color: Theme.fgSurfaceVariant
                            }
                        }
                    }

                    // ── Preset Locked row ─────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Lock Preset"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Disables all automatic preset transitions — stays on the current preset")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: presetLockedTrack
                            readonly property bool lockedOn:
                                root.appConfig !== null && root.appConfig.milkdropPresetLocked
                            width: 48; height: 24
                            radius: 12
                            color: lockedOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: presetLockedTrack.lockedOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropPresetLocked(
                                            !root.appConfig.milkdropPresetLocked)
                                }
                            }
                        }
                    }

                    // ── Show Preset Name row ──────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 16

                        Text {
                            text: "Show Preset Name"
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.titleMd
                            font.weight:    Font.Bold
                            color: Theme.fgSurface

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true

                                ToolTip.visible: containsMouse
                                ToolTip.delay:   600
                                ToolTip.text:    qsTr("Briefly shows the preset name in the pane on every switch, then fades out")
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            id: showPresetNameTrack
                            readonly property bool showOn:
                                root.appConfig !== null && root.appConfig.milkdropShowPresetName
                            width: 48; height: 24
                            radius: 12
                            color: showOn ? Theme.secondary : Theme.outlineVariant

                            Rectangle {
                                width: 18; height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                x: showPresetNameTrack.showOn ? 27 : 3
                                color: Theme.fgSurface
                                Behavior on x { NumberAnimation { duration: 120 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.appConfig)
                                        root.appConfig.setMilkdropShowPresetName(
                                            !root.appConfig.milkdropShowPresetName)
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }   // push content to top
                }
            } // end MILKDROP panel

        } // content Item
    } // contentItem ColumnLayout

    // ── Native folder picker ─────────────────────────────────────────────
    FolderDialog {
        id: folderDialog
        title: "Select Music Folder"
        onAccepted: {
            if (root.appConfig)
                root.appConfig.addFolder(selectedFolder.toString(), true)
        }
    }

    FolderDialog {
        id: milkdropFolderDialog
        title: "Select Preset Folder"
        onAccepted: {
            if (root.appConfig)
                root.appConfig.addMilkdropPresetFolder(selectedFolder.toString())
        }
    }

    // ── Helper functions ─────────────────────────────────────────────────
    function doAddGenre() {
        const name = genreInput.text.trim()
        if (name.length > 0 && root.appConfig) {
            root.appConfig.addGenre(name)
            genreInput.text = ""
        }
    }
}
