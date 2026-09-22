import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ── BackupDialog ──────────────────────────────────────────────────────────
// Setup → MISC "Backup Topaz Environment" / BACKUP button. Zips the
// selected categories (config/playlists/ratings) into a single *.zip via
// BackupRestoreController -- see UC-27. Purely synchronous (small text
// files only), so there's no progress state, just idle -> done.
//
// Usage in SetupDialog.qml:
//   BackupDialog { id: backupDialog; controller: root.backupRestoreController }
//   ...
//   backupDialog.open()
Popup {
    id: root

    property var controller: null

    property string destFolder: ""
    property string zipFileName: ""

    property bool showResult: false
    property var  lastResult: ({})

    readonly property bool hasDestination: destFolder.length > 0
    readonly property bool hasFileName:    zipFileName.trim().length > 0
    // Read the checkboxes' own `checked` directly (by id) rather than
    // mirroring it into a separate root property -- a CheckboxRow's
    // checked is toggled by an IMPERATIVE assignment on click
    // (checkboxRow.checked = !checkboxRow.checked), which permanently
    // severs any declarative `checked: root.someProperty` binding the
    // first time it fires. A mirrored root property would silently drift
    // out of sync with the on-screen checkbox after that -- see UC-27's
    // architecture-doc note for the bug this caused in RestoreDialog.qml.
    readonly property bool anyChecked: backupLibraryCheckbox.checked
                                        || backupConfigCheckbox.checked
                                        || backupPlaylistsCheckbox.checked
                                        || backupRatingsCheckbox.checked
                                        || backupVolumeNormalizationCheckbox.checked
    readonly property bool canBackup:      hasDestination && hasFileName && anyChecked

    anchors.centerIn: Overlay.overlay
    width:  620
    height: 480
    padding: 0
    modal: true
    closePolicy: Popup.NoAutoClose

    onOpened: {
        backupLibraryCheckbox.checked   = true
        backupConfigCheckbox.checked    = true
        backupPlaylistsCheckbox.checked = true
        backupRatingsCheckbox.checked   = true
        backupVolumeNormalizationCheckbox.checked = true
        destFolder      = ""
        showResult      = false
        lastResult      = {}
        const today = new Date()
        const y = today.getFullYear()
        const m = String(today.getMonth() + 1).padStart(2, "0")
        const d = String(today.getDate()).padStart(2, "0")
        zipFileName = "TopazBackup_" + y + m + d + ".zip"
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
    background: Rectangle { color: Theme.surfaceContainerLow; radius: Theme.radiusLg }

    // Overwrite-confirmation + error reporting
    MessageBox {
        id: overwriteConfirmBox
        title: qsTr("FILE EXISTS")
        message: qsTr("A file with that name already exists in the destination folder. Overwrite it?")
        confirmMode: true
        confirmButtonText: qsTr("OVERWRITE")
        onAccepted: root.performBackup()
    }
    MessageBox {
        id: errorBox
        title: qsTr("BACKUP FAILED")
    }

    FolderDialog {
        id: destFolderDialog
        title: qsTr("Select Backup Destination")
        onAccepted: {
            let s = destFolderDialog.selectedFolder.toString()
            // file:///C:/x -> C:/x (Windows); file:///home/x -> /home/x (Linux) --
            // only drop the third slash when a drive letter follows it.
            s = s.replace(/^file:\/\/(\/(?=[A-Za-z]:))?/, "")
            root.destFolder = decodeURIComponent(s)
        }
    }

    // Local reusable checkbox row -- same visual idiom
    // MilkdropCleanupDialog.qml's folder checkboxes use, applied to a fixed
    // set of named toggles instead of a scanned ListModel.
    // A plain Item (not RowLayout) so its MouseArea -- a direct child, not
    // nested inside the checkbox Rectangle -- isn't itself layout-managed
    // (Qt Quick Layouts only tolerate anchors on non-direct-children).
    component CheckboxRow: Item {
        id: checkboxRow
        property bool checked: false
        property string label: ""
        implicitWidth:  rowContent.implicitWidth
        implicitHeight: rowContent.implicitHeight

        Row {
            id: rowContent
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                radius: 3
                color: checkboxRow.checked ? Theme.secondaryContainer : "transparent"
                border.width: checkboxRow.checked ? 0 : 1
                border.color: Theme.outlineVariant

                Text {
                    anchors.centerIn: parent
                    visible: checkboxRow.checked
                    text: "✓"
                    font.pixelSize: 11
                    font.weight: Font.Bold
                    color: Theme.fgSecondaryContainer
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: checkboxRow.label
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.titleMd
                color: Theme.fgSurface
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: checkboxRow.checked = !checkboxRow.checked
        }
    }

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
                    text: "BACKUP"
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
                    color: closeHover.containsMouse ? Theme.surfaceContainerHighest : "transparent"
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

            // ── Idle / configuration state ───────────────────────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 20
                visible: !root.showResult

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "BACKUP OPTIONS"
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelMd
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: Theme.fgSurfaceVariant
                    }
                    CheckboxRow {
                        id: backupLibraryCheckbox
                        label: qsTr("Backup Topaz Library")
                        checked: true
                    }
                    CheckboxRow {
                        id: backupConfigCheckbox
                        label: qsTr("Backup Topaz Config")
                        checked: true
                    }
                    CheckboxRow {
                        id: backupPlaylistsCheckbox
                        label: qsTr("Backup Playlists")
                        checked: true
                    }
                    CheckboxRow {
                        id: backupRatingsCheckbox
                        label: qsTr("Backup Ratings")
                        checked: true
                    }
                    CheckboxRow {
                        id: backupVolumeNormalizationCheckbox
                        label: qsTr("Backup Volume Normalization")
                        checked: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "DESTINATION FOLDER"
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelMd
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: Theme.fgSurfaceVariant
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            Layout.fillWidth: true
                            height: 40
                            color:  Theme.surfaceContainerHigh
                            radius: Theme.radiusSm
                            Text {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: Text.AlignVCenter
                                elide: Text.ElideMiddle
                                text: root.hasDestination ? root.destFolder : qsTr("No folder selected…")
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.monoLg
                                color: root.hasDestination ? Theme.fgSurface : Theme.fgSurfaceVariant
                            }
                        }
                        Rectangle {
                            width: 110; height: 40
                            radius: Theme.radiusSm
                            color: browseHover.containsMouse ? Theme.surfaceContainerHighest
                                                              : Theme.surfaceContainerHigh
                            Text {
                                anchors.centerIn: parent
                                text: qsTr("BROWSE…")
                                font.family:        Theme.fontFamilyBody
                                font.pixelSize:     Theme.labelSm
                                font.weight:        Font.Bold
                                font.letterSpacing: Theme.lsWide
                                color: Theme.primary
                            }
                            MouseArea {
                                id: browseHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape:  Qt.PointingHandCursor
                                onClicked:    destFolderDialog.open()
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "OUTPUT FILENAME"
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelMd
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: Theme.fgSurfaceVariant
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        height: 40
                        color:  Theme.surfaceContainerHigh
                        radius: Theme.radiusSm
                        border.color: zipNameInput.activeFocus ? Theme.primary : "transparent"
                        border.width: 1

                        TextInput {
                            id: zipNameInput
                            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.zipFileName
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoLg
                            color:          Theme.fgSurface
                            clip:           true
                            selectByMouse:  true
                            onTextChanged:  root.zipFileName = text
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── Done: result ──────────────────────────────────────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 12
                visible: root.showResult

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.lastResult.success
                          ? qsTr("Backup complete: %1 file(s) written to\n%2")
                            .arg(root.lastResult.fileCount).arg(root.lastResult.zipPath)
                          : qsTr("Backup failed: %1").arg(root.lastResult.error || "")
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.titleMd
                    font.weight:    Font.Bold
                    color: root.lastResult.success ? Theme.fgSurface : Theme.error
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── Footer ───────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 64
            color:  Theme.surfaceContainerLow

            RowLayout {
                anchors { fill: parent; leftMargin: 24; rightMargin: 24 }
                spacing: 8
                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: cancelHover.containsMouse ? Theme.surfaceContainerHighest
                                                      : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: root.showResult ? qsTr("CLOSE") : qsTr("CANCEL")
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

                Rectangle {
                    visible: !root.showResult
                    width: 120; height: 36
                    radius: Theme.radiusSm
                    opacity: root.canBackup ? 1.0 : 0.35
                    color: backupHover.containsMouse && root.canBackup
                           ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("BACKUP")
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: backupHover.containsMouse && root.canBackup
                               ? Theme.fgPrimaryContainer : Theme.primary
                    }
                    MouseArea {
                        id: backupHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.canBackup ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked:   root.tryBackup()
                    }
                }
            }
        }
    }

    // ── Logic ─────────────────────────────────────────────────────────────
    function tryBackup() {
        if (!root.canBackup || !root.controller) return
        if (root.controller.backupTargetExists(root.destFolder, root.zipFileName)) {
            overwriteConfirmBox.open()
        } else {
            performBackup()
        }
    }

    function performBackup() {
        const categories = []
        if (backupLibraryCheckbox.checked)   categories.push("library")
        if (backupConfigCheckbox.checked)    categories.push("config")
        if (backupPlaylistsCheckbox.checked) categories.push("playlists")
        if (backupRatingsCheckbox.checked)   categories.push("ratings")
        if (backupVolumeNormalizationCheckbox.checked) categories.push("volumeNormalization")

        const result = root.controller.runBackup(categories, root.destFolder, root.zipFileName)
        root.lastResult = result
        root.showResult = true
    }
}
