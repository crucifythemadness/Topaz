import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ── SetupDialog ──────────────────────────────────────────────────────────
// Modal setup window with two tabs:
//   • GENRES        — add/delete genre names that drive GenreBar buttons
//   • FILE MONITORING — add/delete monitored folders (with subfolders toggle)
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

    // ── Geometry ─────────────────────────────────────────────────────────
    anchors.centerIn: Overlay.overlay
    width:  780
    height: 560
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
                    model: ["GENRES", "FILE MONITORING"]

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

                        // Chip flow
                        ScrollView {
                            anchors.fill: parent
                            visible: root.appConfig !== null && root.appConfig.genres.length > 0
                            clip: true

                            Flow {
                                width:   parent.width
                                spacing: 6

                                Repeater {
                                    model: root.appConfig ? root.appConfig.genres : []

                                    delegate: Rectangle {
                                        width:  chipText.implicitWidth + 24
                                        height: 32
                                        radius: Theme.radiusSm

                                        readonly property bool isSelected:
                                            root.selectedGenreIndex === index

                                        color: isSelected
                                               ? Theme.secondaryContainer
                                               : chipHover.containsMouse
                                                 ? Theme.surfaceContainerHighest
                                                 : Theme.surfaceContainerHigh

                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            text: modelData.toUpperCase()
                                            font.family:        Theme.fontFamilyBody
                                            font.pixelSize:     Theme.labelMd
                                            font.letterSpacing: 1.2
                                            color: parent.isSelected
                                                   ? Theme.fgSecondaryContainer
                                                   : Theme.fgSurfaceVariant
                                        }

                                        MouseArea {
                                            id: chipHover
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
                                            font.pixelSize: Theme.monoSm
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

    // ── Helper functions ─────────────────────────────────────────────────
    function doAddGenre() {
        const name = genreInput.text.trim()
        if (name.length > 0 && root.appConfig) {
            root.appConfig.addGenre(name)
            genreInput.text = ""
        }
    }
}
