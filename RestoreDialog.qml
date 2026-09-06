import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ── RestoreDialog ─────────────────────────────────────────────────────────
// Setup → MISC "Restore Topaz Environment" / RESTORE button. Reads a backup
// *.zip via BackupRestoreController -- see UC-27 -- and restores playlists/
// ratings, one conflict decision at a time (a plain JS array + index-cursor
// state machine driving a single reused ChoiceDialog instance per category).
// No config restore -- deliberately excluded (overwriting live app settings
// while Topaz is running is riskier than useful).
//
// Usage in SetupDialog.qml:
//   RestoreDialog { id: restoreDialog; controller: root.backupRestoreController }
//   ...
//   restoreDialog.open()
Popup {
    id: root

    property var controller: null

    property string zipPath: ""

    property var pendingPlaylistConflicts: []   // [fileName, ...]
    property int  conflictCursor: 0
    property bool ratingsConflictPending: false

    property var  resultsLog: []                // [{category, fileName, outcome}, ...]
    property bool showResult: false
    property bool restoring: false

    // Outcome tracking for the summary lines shown on the Done screen --
    // see buildSummaryLines() below.
    property int    playlistsCopiedCount: 0
    property bool   ratingsHandled:      false   // true once a restoreRatings() call actually ran
    property string ratingsOutcomeMode:  ""      // "overwrite" | "skip" | "mergeNew" | "mergeAll"
    property int    ratingsAddedCount:   0
    property int    ratingsUpdatedCount: 0
    property var    summaryLines: []

    readonly property bool hasZip:      zipPath.length > 0
    // Read the checkboxes' own `checked` directly (by id) rather than
    // mirroring it into a separate root property -- a CheckboxRow's
    // checked is toggled by an IMPERATIVE assignment on click
    // (checkboxRow.checked = !checkboxRow.checked), which permanently
    // severs any declarative `checked: root.someProperty` binding the
    // first time it fires. A mirrored root property would silently drift
    // out of sync with the on-screen checkbox after that -- see UC-27's
    // architecture-doc note for the bug this caused.
    readonly property bool anyChecked:  restorePlaylistsCheckbox.checked || restoreRatingsCheckbox.checked
    readonly property bool canRestore:  hasZip && anyChecked && !restoring

    anchors.centerIn: Overlay.overlay
    width:  620
    height: 480
    padding: 0
    modal: true
    closePolicy: Popup.NoAutoClose

    onOpened: {
        restorePlaylistsCheckbox.checked = true
        restoreRatingsCheckbox.checked   = true
        zipPath                 = ""
        pendingPlaylistConflicts = []
        conflictCursor          = 0
        ratingsConflictPending  = false
        resultsLog              = []
        showResult              = false
        restoring               = false
        playlistsCopiedCount    = 0
        ratingsHandled          = false
        ratingsOutcomeMode      = ""
        ratingsAddedCount       = 0
        ratingsUpdatedCount     = 0
        summaryLines            = []
    }

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
    background: Rectangle { color: Theme.surfaceContainerLow; radius: Theme.radiusLg }

    MessageBox {
        id: errorBox
        title: qsTr("RESTORE FAILED")
    }

    FileDialog {
        id: zipFileDialog
        title: qsTr("Select Backup File")
        nameFilters: ["ZIP Archives (*.zip)"]
        fileMode: FileDialog.OpenFile
        onAccepted: {
            let s = zipFileDialog.selectedFile.toString()
            if (s.indexOf("file:///") === 0)      s = s.substring(8)
            else if (s.indexOf("file://") === 0)  s = s.substring(7)
            root.zipPath = decodeURIComponent(s)
        }
    }

    // One instance reused for every playlist conflict, one for the single
    // possible ratings conflict -- see startRestore()/advance() below.
    ChoiceDialog {
        id: playlistConflictDialog
        property string fileName: ""
        title:   qsTr("PLAYLIST EXISTS")
        message: qsTr("A playlist named \"%1\" already exists. What would you like to do?")
                 .arg(playlistConflictDialog.fileName)
        choices: ["YES", "NO", "RENAME"]
        onChoiceMade: (choice) => {
            const action = choice === "YES" ? "overwrite" : choice === "NO" ? "skip" : "rename"
            const r = root.controller.restorePlaylistEntry(root.zipPath, fileName, action)
            if (action !== "skip" && r.success) root.playlistsCopiedCount++
            root.resultsLog.push({
                category: qsTr("Playlist"),
                fileName: r.writtenFileName || fileName,
                outcome: action === "skip" ? qsTr("skipped")
                         : (r.success ? qsTr("copied") : qsTr("failed"))
            })
            root.conflictCursor++
            root.advance()
        }
    }

    ChoiceDialog {
        id: ratingsConflictDialog
        title:   qsTr("RATINGS EXIST")
        message: qsTr("A ratings file already exists locally. What would you like to do?")
        choices: ["YES", "NO", "MERGE NEW", "MERGE ALL"]
        onChoiceMade: (choice) => {
            const mode = choice === "YES" ? "overwrite" : choice === "NO" ? "skip"
                         : choice === "MERGE NEW" ? "mergeNew" : "mergeAll"
            const r = root.controller.restoreRatings(root.zipPath, mode)
            root.ratingsHandled      = true
            root.ratingsOutcomeMode  = mode
            root.ratingsAddedCount   = r.addedCount || 0
            root.ratingsUpdatedCount = r.updatedCount || 0
            root.resultsLog.push({
                category: qsTr("Ratings"),
                fileName: "",
                outcome: mode === "skip" ? qsTr("skipped") : (r.success ? qsTr("copied") : qsTr("failed"))
            })
            root.advance()
        }
    }

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
                    text: "RESTORE"
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
                        text: "RESTORE OPTIONS"
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelMd
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: Theme.fgSurfaceVariant
                    }
                    CheckboxRow {
                        id: restorePlaylistsCheckbox
                        label: qsTr("Restore Playlists")
                        checked: true
                    }
                    CheckboxRow {
                        id: restoreRatingsCheckbox
                        label: qsTr("Restore Ratings")
                        checked: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "BACKUP FILE"
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
                                text: root.hasZip ? root.zipPath : qsTr("No file selected…")
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.monoLg
                                color: root.hasZip ? Theme.fgSurface : Theme.fgSurfaceVariant
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
                                onClicked:    zipFileDialog.open()
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── Done: results ─────────────────────────────────────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 12
                visible: root.showResult

                Text {
                    text: qsTr("Restore complete.")
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.titleMd
                    font.weight:    Font.Bold
                    color: Theme.fgSurface
                }

                Repeater {
                    model: root.summaryLines
                    delegate: Text {
                        Layout.fillWidth: true
                        text: modelData
                        wrapMode: Text.Wrap
                        font.family:    Theme.fontFamilyBody
                        font.pixelSize: Theme.titleMd
                        color: Theme.fgSurface
                    }
                }

                ScrollView {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    clip: true

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.resultsLog

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: 40
                                radius: Theme.radiusSm
                                color: Theme.surfaceContainer

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 12
                                    Text {
                                        text: modelData.category
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelMd
                                        color: Theme.fgSurfaceVariant
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.fileName
                                        elide: Text.ElideMiddle
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoLg
                                        color: Theme.fgSurface
                                    }
                                    Text {
                                        text: modelData.outcome
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoLg
                                        color: modelData.outcome === qsTr("failed") ? Theme.error
                                               : Theme.fgSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
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
                    opacity: root.canRestore ? 1.0 : 0.35
                    color: restoreHover.containsMouse && root.canRestore
                           ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("RESTORE")
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: restoreHover.containsMouse && root.canRestore
                               ? Theme.fgPrimaryContainer : Theme.primary
                    }
                    MouseArea {
                        id: restoreHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.canRestore ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked:   root.startRestore()
                    }
                }
            }
        }
    }

    // ── Logic ─────────────────────────────────────────────────────────────
    function startRestore() {
        if (!root.canRestore || !root.controller) return

        const info = root.controller.inspectZip(root.zipPath)
        if (info.error) {
            errorBox.message = info.error
            errorBox.open()
            return
        }

        root.restoring  = true
        root.resultsLog = []
        root.playlistsCopiedCount = 0
        root.ratingsHandled       = false
        root.ratingsOutcomeMode   = ""
        root.ratingsAddedCount    = 0
        root.ratingsUpdatedCount  = 0
        root.summaryLines         = []

        root.pendingPlaylistConflicts = []
        if (restorePlaylistsCheckbox.checked) {
            for (const p of info.playlists) {
                if (p.conflict) {
                    root.pendingPlaylistConflicts.push(p.fileName)
                } else {
                    const r = root.controller.restorePlaylistEntry(root.zipPath, p.fileName, "overwrite")
                    if (r.success) root.playlistsCopiedCount++
                    root.resultsLog.push({
                        category: qsTr("Playlist"), fileName: p.fileName,
                        outcome: r.success ? qsTr("copied") : qsTr("failed")
                    })
                }
            }
        }

        root.ratingsConflictPending =
            restoreRatingsCheckbox.checked && info.hasRatings && info.ratingsConflict
        if (restoreRatingsCheckbox.checked && info.hasRatings && !info.ratingsConflict) {
            const r = root.controller.restoreRatings(root.zipPath, "overwrite")
            root.ratingsHandled      = true
            root.ratingsOutcomeMode  = "overwrite"
            root.ratingsAddedCount   = r.addedCount || 0
            root.ratingsUpdatedCount = r.updatedCount || 0
            root.resultsLog.push({
                category: qsTr("Ratings"), fileName: "",
                outcome: r.success ? qsTr("copied") : qsTr("failed")
            })
        }

        root.conflictCursor = 0
        root.advance()
    }

    function advance() {
        if (root.conflictCursor < root.pendingPlaylistConflicts.length) {
            playlistConflictDialog.fileName = root.pendingPlaylistConflicts[root.conflictCursor]
            playlistConflictDialog.open()
            return
        }
        if (root.ratingsConflictPending) {
            root.ratingsConflictPending = false
            ratingsConflictDialog.open()
            return
        }
        root.buildSummaryLines()
        root.restoring  = false
        root.showResult = true
    }

    function buildSummaryLines() {
        const lines = []
        if (restorePlaylistsCheckbox.checked) {
            const n = root.playlistsCopiedCount
            lines.push(n === 1
                ? qsTr("1 Playlist File has been copied to the Topaz Playlist Folder.")
                : qsTr("%1 Playlist Files have been copied to the Topaz Playlist Folder.").arg(n))
        }
        if (restoreRatingsCheckbox.checked && root.ratingsHandled) {
            if (root.ratingsOutcomeMode === "overwrite")
                lines.push(qsTr("Topaz Rating File has been overwritten."))
            else if (root.ratingsOutcomeMode === "skip")
                lines.push(qsTr("No updates regarding Topaz Rating File."))
            else
                lines.push(qsTr("%1 Ratings have been updated in the Topaz Rating File.")
                           .arg(root.ratingsAddedCount + root.ratingsUpdatedCount))
        }
        root.summaryLines = lines
    }
}
