import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ── MilkdropCleanupDialog ────────────────────────────────────────────────
// Lists configured Milkdrop preset folders (AppConfig.milkdropPresetFolders)
// with a checkbox + preset count each, then runs MilkdropCleanupController
// against the checked folders -- deleting whatever MilkdropPresetChecker
// flags as incompatible with Topaz's projectM integration. See UC-25.
//
// Chrome modeled on NewPlaylistDialog.qml (header + ✕ close button, fixed
// size, no resize grips -- unlike MissingTracksDialog.qml, this dialog's
// content doesn't need resizing).
//
// Usage in SetupDialog.qml:
//   MilkdropCleanupDialog { id: milkdropCleanupDialog
//                           appConfig: root.appConfig
//                           cleanupController: root.cleanupController }
//   ...
//   milkdropCleanupDialog.open()
Popup {
    id: root

    property AppConfig appConfig: null
    property MilkdropCleanupController cleanupController: null

    // Pure ephemeral UI state -- which folders are checked, and the results
    // screen's data -- never persisted anywhere.
    property int checkedCount: 0
    property bool showResults: false
    property var lastResults: []

    anchors.centerIn: Overlay.overlay
    width:  640
    height: 520
    padding: 0

    modal: true
    closePolicy: Popup.NoAutoClose

    onOpened: {
        showResults = false
        lastResults = []
        checkedCount = 0
        folderListModel.clear()
        if (cleanupController) {
            const folders = cleanupController.presetFolders()
            for (let i = 0; i < folders.length; i++) {
                folderListModel.append({
                    path:        folders[i].path,
                    presetCount: folders[i].presetCount,
                    exists:      folders[i].exists,
                    checked:     true
                })
            }
            checkedCount = folders.length
        }
    }

    Connections {
        target: root.cleanupController
        function onCleanupFinished(results) {
            root.lastResults = results
            root.showResults = true
        }
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    ListModel { id: folderListModel }

    contentItem: ColumnLayout {
        spacing: 0

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 56
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 16 }
                spacing: 0

                Text {
                    text: "MILKDROP PRESETS CLEANUP"
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                // ✕ close button -- hidden while a cleanup is running, same
                // reasoning as Main.qml's onClosing veto: this could be a
                // multi-second-to-tens-of-seconds scan, and there's no safe
                // way to tear the dialog down mid-loop.
                Rectangle {
                    visible: !root.cleanupController || !root.cleanupController.cleaning
                    width: 32; height: 32
                    radius: Theme.radiusFull
                    color: closeHover.containsMouse ? Theme.surfaceContainerHighest
                                                     : "transparent"
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

        // ── Body ─────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth:  true
            Layout.fillHeight: true

            // ── Idle: folder list + CLEANUP button ──────────────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 12
                visible: !root.showResults
                         && (!root.cleanupController || !root.cleanupController.cleaning)

                Text {
                    Layout.fillWidth: true
                    visible: folderListModel.count === 0
                    text: "No Milkdrop preset folders configured.\nAdd one in the MILKDROP tab."
                    wrapMode: Text.WordWrap
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.labelLg
                    color: Theme.fgSurfaceVariant
                }

                ScrollView {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    visible: folderListModel.count > 0
                    clip: true

                    ListView {
                        id: folderListView
                        model: folderListModel
                        spacing: 6

                        delegate: Rectangle {
                            width:  folderListView.width
                            height: 44
                            radius: Theme.radiusSm
                            color:  Theme.surfaceContainer

                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                spacing: 12

                                // Checkbox -- same visual idiom as the GENRES
                                // tab's per-genre enable checkbox.
                                Rectangle {
                                    width: 18; height: 18
                                    radius: 3
                                    color: model.checked ? Theme.secondaryContainer : "transparent"
                                    border.width: model.checked ? 0 : 1
                                    border.color: Theme.outlineVariant

                                    Text {
                                        anchors.centerIn: parent
                                        visible: model.checked
                                        text: "✓"
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        color: Theme.fgSecondaryContainer
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const newChecked = !model.checked
                                            folderListModel.setProperty(index, "checked", newChecked)
                                            root.checkedCount += newChecked ? 1 : -1
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.path
                                    font.family:    Theme.fontFamilyMono
                                    font.pixelSize: Theme.monoLg
                                    color: Theme.fgSurface
                                    elide: Text.ElideMiddle

                                    ToolTip.visible: pathHover.containsMouse
                                    ToolTip.text:    model.path
                                    ToolTip.delay:   500
                                    MouseArea {
                                        id: pathHover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        acceptedButtons: Qt.NoButton
                                    }
                                }

                                Text {
                                    text: model.exists ? (model.presetCount + " presets")
                                                        : "(folder not found)"
                                    font.family:    Theme.fontFamilyMono
                                    font.pixelSize: Theme.monoSm
                                    color: model.exists ? Theme.fgSurfaceVariant : Theme.error
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 120; height: 36
                        radius: Theme.radiusSm
                        opacity: root.checkedCount > 0 ? 1.0 : 0.35
                        color: cleanupHover.containsMouse && root.checkedCount > 0
                               ? Theme.errorContainer : Theme.surfaceContainerHigh

                        Text {
                            anchors.centerIn: parent
                            text: "CLEANUP"
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        Font.Bold
                            font.letterSpacing: Theme.lsWide
                            color: Theme.error
                        }
                        MouseArea {
                            id: cleanupHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.checkedCount > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.checkedCount === 0 || !root.cleanupController) return
                                const paths = []
                                for (let i = 0; i < folderListModel.count; i++) {
                                    const entry = folderListModel.get(i)
                                    if (entry.checked) paths.push(entry.path)
                                }
                                root.cleanupController.startCleanup(paths)
                            }
                        }
                    }
                }
            }

            // ── Running: progress bar + current-file label ──────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 16
                visible: root.cleanupController && root.cleanupController.cleaning

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: "Checking: " + (root.cleanupController ? root.cleanupController.currentFileName : "")
                    elide: Text.ElideMiddle
                    horizontalAlignment: Text.AlignHCenter
                    font.family:    Theme.fontFamilyMono
                    font.pixelSize: Theme.monoLg
                    color: Theme.fgSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 8
                    radius: height / 2
                    color: Theme.surfaceContainerHigh
                    clip: true

                    Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: Theme.primary
                        width: parent.width
                               * (root.cleanupController ? root.cleanupController.cleanupProgress : 0)
                               / 100
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── Done: per-folder results ─────────────────────────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 12
                visible: root.showResults
                         && (!root.cleanupController || !root.cleanupController.cleaning)

                Text {
                    text: "Cleanup complete."
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.titleMd
                    font.weight:    Font.Bold
                    color: Theme.fgSurface
                }

                ScrollView {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.lastResults

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 40
                                radius: Theme.radiusSm
                                color: Theme.surfaceContainer

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 12

                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.path
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoLg
                                        color: Theme.fgSurface
                                        elide: Text.ElideMiddle
                                    }
                                    Text {
                                        text: modelData.removed + " of " + modelData.total + " removed"
                                              + (modelData.failed > 0
                                                 ? " (" + modelData.failed + " failed)" : "")
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoSm
                                        color: modelData.removed > 0 ? Theme.error : Theme.fgSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        width: 100; height: 36
                        radius: Theme.radiusSm
                        color: closeResultsHover.containsMouse
                               ? Theme.primaryContainer : Theme.surfaceContainerHigh
                        Text {
                            anchors.centerIn: parent
                            text: "CLOSE"
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        Font.Bold
                            font.letterSpacing: Theme.lsWidest
                            color: closeResultsHover.containsMouse
                                   ? Theme.fgPrimaryContainer : Theme.primary
                        }
                        MouseArea {
                            id: closeResultsHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked:    root.close()
                        }
                    }
                }
            }
        }
    }
}
