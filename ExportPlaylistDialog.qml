import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ── ExportPlaylistDialog ─────────────────────────────────────────────────
// Copies the currently-loaded playlist's audio files to a chosen
// destination (typically a USB stick, for listening in a car) with a
// generated "<prefix><index>_<title>.<ext>" filename per track. See UC-26
// in the architecture doc.
//
// Chrome modeled on MilkdropCleanupDialog.qml (header + ✕ close button,
// idle/running/results states in the same body Item).
//
// Usage in Main.qml:
//   ExportPlaylistDialog { id: exportPlaylistDialog
//                          exportController: exportController }
//   ...
//   exportPlaylistDialog.tracks = <track maps, e.g. engine.trackList() or
//                                   playlistsData.selectedRawTracks>
//   exportPlaylistDialog.open()
Popup {
    id: root

    // Track maps to export -- {filePath, title, ...}, the same shape
    // PlaybackEngine.trackList() and PlaylistManager.loadPlaylist()'s
    // "tracks" result both already share. Deliberately NOT bound to
    // `engine` directly: the caller sets this fresh right before open(),
    // so the same dialog can export either the live playback queue
    // (NowPlaying) or a playlist merely selected in the list (PlaylistViewer)
    // without ever touching PlaybackEngine.
    property var tracks: []
    property var exportController: null

    // Ephemeral UI state, reset every time the dialog opens -- never persisted.
    property string destFolder: ""   // "" = none chosen yet
    property var    destInfo: ({})   // last analyzeDestination() result
    property real   requiredBytes: 0
    property string prefixText: ""
    property bool   showResults: false
    property var    lastResults: []

    readonly property bool hasDestination: destFolder.length > 0
    readonly property bool destWritable:   hasDestination && destInfo.writable === true
    readonly property bool enoughSpace:    hasDestination && destInfo.freeBytes !== undefined
                                            && destInfo.freeBytes >= requiredBytes
    readonly property bool goodToGo:       destWritable && enoughSpace
    readonly property bool exporting:      root.exportController && root.exportController.exporting
    readonly property bool canExport:      goodToGo && !exporting

    // ── Left panel / volume-label sizing ──────────────────────────────────
    // Widened (from a 200px base) by however many pixels 8 more characters
    // need at Theme.headlineLg, measured live via FontMetrics rather than
    // guessed. volumeLabelMetrics is deliberately pinned to headlineLg
    // regardless of what size the label Text actually renders at below --
    // it exists only to size the panel/icon per that original "8 more
    // characters" request, so tweaking the label's own displayed font size
    // never again accidentally resizes the panel or the drive icon.
    // The dialog's own width grows by the same amount, so the right column
    // keeps its original width instead of being squeezed.
    readonly property int leftPanelBaseWidth: 200
    readonly property int iconBaseSize: 96
    readonly property int extraLabelWidth: Math.ceil(volumeLabelMetrics.averageCharacterWidth * 8)
    readonly property int leftPanelWidth: leftPanelBaseWidth + extraLabelWidth
    readonly property int iconSize: Math.round(iconBaseSize * leftPanelWidth / leftPanelBaseWidth)

    FontMetrics {
        id: volumeLabelMetrics
        font.family: Theme.fontFamilyHeadline
        font.pixelSize: Theme.headlineLg
        font.bold: true
    }

    // ── Storage & capacity row-height matching ────────────────────────────
    // Shared row height for the "N tracks" caption and the (possibly empty)
    // warning message below each big number, so both columns always reserve
    // the same 3rd-row height regardless of which -- if any -- warning is
    // showing. Measured rather than guessed, same reasoning as above.
    FontMetrics {
        id: tracksCaptionMetrics
        font.family: Theme.fontFamilyMono
        font.pixelSize: Theme.monoLg
    }
    FontMetrics {
        id: storageWarningMetrics
        font.family: Theme.fontFamilyBody
        font.pixelSize: Theme.labelMd
        font.bold: true
    }
    readonly property int storageCaptionRowHeight:
        Math.ceil(Math.max(tracksCaptionMetrics.height, storageWarningMetrics.height))

    // ── Total playtime (for the "N tracks | <playtime>" caption) ──────────
    readonly property int totalTracksDurationMs:
        root.tracks.reduce(function (sum, t) { return sum + (t.durationMs || 0) }, 0)

    // M:SS under 100 total minutes, H:MM:SS from 100 minutes up -- lets a
    // playlist's fit against an 80-minute Minidisc (or anything under
    // ~100 min) stay readable as plain minutes rather than always showing
    // an hours digit.
    function formatTotalDuration(ms) {
        const totalSecs = Math.floor(ms / 1000)
        const totalMins = Math.floor(totalSecs / 60)
        const secs = totalSecs % 60
        if (totalMins < 100)
            return totalMins + ":" + String(secs).padStart(2, "0")
        const hours = Math.floor(totalMins / 60)
        const mins  = totalMins % 60
        return hours + ":" + String(mins).padStart(2, "0") + ":" + String(secs).padStart(2, "0")
    }

    // Deliberately NOT anchors.centerIn: Popup's anchors.centerIn is backed
    // by QQuickPopupAnchors, which keeps reasserting x/y from C++ (not a
    // plain QML binding) — it fights the header drag MouseArea below and
    // the popup never visibly moves. Plain x/y bindings behave like normal
    // Item bindings and get cleanly overridden by the drag's direct
    // assignment, same as SetupDialog.qml.
    x: Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
    y: Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
    width:  760 + extraLabelWidth
    height: 480
    padding: 0

    modal: true
    closePolicy: Popup.NoAutoClose

    onOpened: {
        // Dragging the header (below) moves this Popup via direct x/y
        // assignment, which breaks the bindings above — recompute them here
        // on every open so the dialog always reopens centered.
        x = Overlay.overlay ? (Overlay.overlay.width  - width)  / 2 : 0
        y = Overlay.overlay ? (Overlay.overlay.height - height) / 2 : 0
        destFolder   = ""
        destInfo     = {}
        prefixText   = ""
        showResults  = false
        lastResults  = []
        if (root.exportController && root.tracks.length > 0) {
            const paths = root.tracks.map(function (t) { return t.filePath })
            requiredBytes = root.exportController.computeRequiredBytes(paths)
        } else {
            requiredBytes = 0
        }
    }

    Connections {
        target: root.exportController
        function onExportFinished(results) {
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

    // ── Native folder picker ─────────────────────────────────────────────
    FolderDialog {
        id: destFolderDialog
        title: qsTr("Select Export Destination")
        onAccepted: {
            let s = destFolderDialog.selectedFolder.toString()
            if (s.indexOf("file:///") === 0)      s = s.substring(8)
            else if (s.indexOf("file://") === 0)  s = s.substring(7)
            root.destFolder = decodeURIComponent(s)
            root.refreshDestInfo()
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

            // Drag-to-move — declared first so it sits underneath the close
            // button's own MouseArea below (later siblings win input in
            // overlapping regions), leaving the ✕ click unaffected. Same
            // idiom as SetupDialog.qml.
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
                    text: "EXPORT PLAYLIST"
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }

                Item { Layout.fillWidth: true }

                // ✕ close button -- hidden while an export is running, same
                // reasoning as MilkdropCleanupDialog's veto: there's no safe
                // way to tear the dialog down mid-copy.
                Rectangle {
                    visible: !root.exporting
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
            RowLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 20
                visible: !root.showResults && !root.exporting

                // Left panel: drive-type icon
                Rectangle {
                    Layout.preferredWidth: root.leftPanelWidth
                    Layout.fillHeight: true
                    color:  Theme.surfaceContainerLowest
                    radius: Theme.radiusMd

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 8

                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            source: root.hasDestination && root.destInfo.isRemovable
                                    ? "qrc:/Topaz/UsbStick_Icon.svg"
                                    : "qrc:/Topaz/Harddisk_Icon.svg"
                            sourceSize.width:  root.iconSize
                            sourceSize.height: root.iconSize
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.maximumWidth: root.leftPanelWidth - 24
                            horizontalAlignment: Text.AlignHCenter
                            // NoWrap (not WordWrap) is the actual fix for
                            // "no line break": WordWrap only elides once the
                            // wrapped text also overflows a constrained
                            // height, which this Text never has, so it was
                            // free to wrap to a second line instead of
                            // eliding. NoWrap forces a single line and lets
                            // elide take over immediately once it's too long.
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            text: root.hasDestination
                                  ? (root.destInfo.volumeLabel && root.destInfo.volumeLabel.length > 0
                                     ? root.destInfo.volumeLabel : qsTr("UNNAMED VOLUME"))
                                  : qsTr("NO DESTINATION")
                            font.family:    Theme.fontFamilyHeadline
                            font.pixelSize: Theme.headlineSm
                            font.weight:    Font.Bold
                            color: Theme.fgSurface
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: root.hasDestination
                            text: root.hasDestination && root.destInfo.isRemovable
                                  ? qsTr("USB Storage Drive") : qsTr("Fixed Disk")
                            font.family:    Theme.fontFamilyBody
                            font.pixelSize: Theme.labelLg
                            color: Theme.fgSurfaceVariant
                        }
                    }
                }

                // Right column
                ColumnLayout {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    spacing: 16

                    // ── Destination folder ───────────────────────────────
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

                    // ── Storage & capacity ───────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: storageCol.implicitHeight + 24
                        color:  Theme.surfaceContainer
                        radius: Theme.radiusMd

                        ColumnLayout {
                            id: storageCol
                            anchors { fill: parent; margins: 12 }
                            spacing: 10

                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "STORAGE & CAPACITY"
                                    font.family:        Theme.fontFamilyBody
                                    font.pixelSize:     Theme.labelMd
                                    font.weight:        Font.Bold
                                    font.letterSpacing: Theme.lsWidest
                                    color: Theme.fgSurfaceVariant
                                }
                                Item { Layout.fillWidth: true }
                                // Good-to-go / not-enough-space indicator --
                                // same literal colors as BottomBar's AUTO
                                // PLAY button, reused here per explicit
                                // request (Theme.qml has no green/red tokens).
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: !root.hasDestination ? Theme.outlineVariant
                                           : (root.goodToGo ? "#00C853" : "#FF1744")
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 24

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: qsTr("PLAYLIST REQUIRED SPACE")
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelMd
                                        color: Theme.fgSurfaceVariant
                                    }
                                    Text {
                                        text: root.formatRequiredBytes(root.requiredBytes)
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoDisplay
                                        font.weight:    Font.Bold
                                        color: Theme.primary
                                    }
                                    Text {
                                        Layout.preferredHeight: root.storageCaptionRowHeight
                                        text: root.tracks.length + qsTr(" tracks | ")
                                              + root.formatTotalDuration(root.totalTracksDurationMs)
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoLg
                                        color: Theme.fgSurfaceVariant
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text {
                                        text: qsTr("DESTINATION AVAILABLE SPACE")
                                        font.family:    Theme.fontFamilyBody
                                        font.pixelSize: Theme.labelMd
                                        color: Theme.fgSurfaceVariant
                                    }
                                    Text {
                                        text: root.hasDestination ? root.formatBytes(root.destInfo.freeBytes || 0) : "—"
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoDisplay
                                        font.weight:    Font.Bold
                                        color: Theme.secondary
                                    }
                                    // Mutually-exclusive warning messages
                                    // merged into one always-present Text
                                    // (rather than two visible:-toggled
                                    // Texts) with a shared, measured row
                                    // height -- an invisible item is
                                    // excluded from Layout sizing entirely,
                                    // which used to make this column
                                    // collapse to 2 rows whenever neither
                                    // warning applied, pulling its number up
                                    // out of alignment with the REQUIRED
                                    // SPACE column's always-3-row layout.
                                    Text {
                                        Layout.preferredHeight: root.storageCaptionRowHeight
                                        text: !root.hasDestination ? ""
                                              : (!root.destWritable ? qsTr("DESTINATION NOT WRITABLE")
                                                 : (!root.enoughSpace ? qsTr("NOT ENOUGH FREE SPACE") : ""))
                                        font.family:        Theme.fontFamilyBody
                                        font.pixelSize:     Theme.labelMd
                                        font.weight:        Font.Bold
                                        color: Theme.error
                                    }
                                }
                            }
                        }
                    }

                    // ── Track prefix ──────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "FILE NAMING / TRACK PREFIX (OPTIONAL)"
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
                            border.color: prefixInput.activeFocus ? Theme.primary : "transparent"
                            border.width: 1

                            Text {
                                anchors { fill: prefixInput }
                                visible: prefixInput.text.length === 0 && !prefixInput.activeFocus
                                verticalAlignment: Text.AlignVCenter
                                text: qsTr("e.g. TPZ_")
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.monoLg
                                color: Theme.fgSurfaceVariant
                            }
                            TextInput {
                                id: prefixInput
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                font.family:    Theme.fontFamilyMono
                                font.pixelSize: Theme.monoLg
                                color:          Theme.fgSurface
                                clip:           true
                                selectByMouse:  true
                                onTextChanged:  root.prefixText = text
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            text: root.previewFileName().length > 0
                                  ? qsTr("Preview: ") + root.previewFileName() : ""
                            font.family:    Theme.fontFamilyMono
                            font.pixelSize: Theme.monoLg
                            color: Theme.secondary
                        }
                    }
                }
            }

            // ── Running: progress bar + current-file label ───────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 16
                visible: root.exporting

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Exporting: ") + (root.exportController ? root.exportController.currentFileName : "")
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
                               * (root.exportController ? root.exportController.exportProgress : 0)
                               / 100
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }

                Item { Layout.fillHeight: true }
            }

            // ── Done: results summary ────────────────────────────────────
            ColumnLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 12
                visible: root.showResults && !root.exporting

                Text {
                    text: {
                        const ok = root.lastResults.filter(function (r) { return r.success }).length
                        return qsTr("Export complete: %1 of %2 tracks copied.")
                               .arg(ok).arg(root.lastResults.length)
                    }
                    font.family:    Theme.fontFamilyBody
                    font.pixelSize: Theme.titleMd
                    font.weight:    Font.Bold
                    color: Theme.fgSurface
                }

                ScrollView {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    clip: true
                    visible: root.lastResults.some(function (r) { return !r.success })

                    ColumnLayout {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: root.lastResults

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                visible: !modelData.success
                                height: visible ? 40 : 0
                                radius: Theme.radiusSm
                                color:  Theme.surfaceContainer

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 12
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.sourcePath
                                        elide: Text.ElideMiddle
                                        font.family:    Theme.fontFamilyMono
                                        font.pixelSize: Theme.monoSm
                                        color: Theme.error
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

                // CANCEL / STOP
                Rectangle {
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: cancelHover.containsMouse ? Theme.surfaceContainerHighest
                                                     : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: root.exporting ? qsTr("STOP") : qsTr("CANCEL")
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
                        onClicked: {
                            if (root.exporting) {
                                if (root.exportController) root.exportController.cancelExport()
                            } else {
                                root.close()
                            }
                        }
                    }
                }

                // EXPORT
                Rectangle {
                    visible: !root.showResults
                    width: 130; height: 36
                    radius: Theme.radiusSm
                    opacity: root.canExport ? 1.0 : 0.35
                    color: exportHover.containsMouse && root.canExport
                           ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("EXPORT")
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: exportHover.containsMouse && root.canExport
                               ? Theme.fgPrimaryContainer : Theme.primary
                    }
                    MouseArea {
                        id: exportHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: root.canExport ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked:   root.tryExport()
                    }
                }

                // CLOSE (results state)
                Rectangle {
                    visible: root.showResults
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: closeResultsHover.containsMouse
                           ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("CLOSE")
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

    // ── Logic ─────────────────────────────────────────────────────────────
    function refreshDestInfo() {
        if (!root.exportController || !root.hasDestination) {
            root.destInfo = {}
            return
        }
        root.destInfo = root.exportController.analyzeDestination(root.destFolder)
    }

    function formatBytes(bytes) {
        const gb = bytes / (1024 * 1024 * 1024)
        return gb.toFixed(2) + " GB"
    }

    // PLAYLIST REQUIRED SPACE only -- shows MB for small playlists rather
    // than an unhelpfully-tiny "0.23 GB". DESTINATION AVAILABLE SPACE keeps
    // using formatBytes() above since real drives are essentially always
    // multi-GB.
    function formatRequiredBytes(bytes) {
        const mib = bytes / (1024 * 1024)
        if (mib < 1000)
            return mib.toFixed(2) + " MB"
        return root.formatBytes(bytes)
    }

    function previewFileName() {
        const tracks = root.tracks
        if (tracks.length === 0) return ""
        const digitWidth = Math.max(2, String(tracks.length).length)
        const idx = "1".padStart(digitWidth, "0")
        const first = tracks[0]
        const dot = first.filePath.lastIndexOf(".")
        const ext = dot >= 0 ? first.filePath.substring(dot + 1) : ""
        const title = (first.title || "").replace(/[\\/:*?"<>|]/g, "")
        return root.prefixText + idx + "_" + title + (ext.length > 0 ? "." + ext : "")
    }

    function tryExport() {
        if (!root.canExport || !root.exportController) return
        const tracks = root.tracks.map(function (t) {
            return { filePath: t.filePath, title: t.title }
        })
        root.exportController.startExport(tracks, root.destFolder, root.prefixText)
    }
}
