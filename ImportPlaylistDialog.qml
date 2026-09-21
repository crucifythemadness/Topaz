import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts

// ── ImportPlaylistDialog ─────────────────────────────────────────────────
// Opened by NowPlaying's LOAD flow when the user picks an XSPF file that
// isn't already inside the Topaz playlist folder -- copies it in first
// (PlaylistManager.importPlaylistFile()) so PlaylistsPanel/PlaylistViewer's
// convenience (preview, LOAD, EXPORT, DELETE, live "(IN QUEUE)" tracking)
// works for it going forward, exactly like a playlist created in Topaz.
// See UC-30.
//
// The copy itself is synchronous -- a single small XSPF file, the same
// "small file, no worker thread" scale of work MilkdropCleanupController/
// BackupRestoreController already do on the main thread (unlike
// PlaylistExportWorker's dedicated QThread, which exists specifically
// because multi-GB *audio* copies would visibly freeze the UI). Since a
// single QFile::copy() has no meaningful mid-copy progress to sample, the
// bar below is a short fixed-duration cosmetic sweep to 100% -- visually
// matching ExportPlaylistDialog's real byte-progress bar -- rather than a
// literal byte count.
//
// Usage:
//   ImportPlaylistDialog { id: importPlaylistDialog; playlistManager: playlistManager }
//   ...
//   importPlaylistDialog.startImport(sourcePath, fileName)
Popup {
    id: root

    property var    playlistManager: null
    property string fileName: ""
    property int    importProgress: 0   // 0-100, animated by the width Behavior below

    // Emitted once the copy attempt finishes (success or failure), right
    // after this popup has closed itself.
    signal importFinished(bool success, string fileName)

    anchors.centerIn: Overlay.overlay
    width:   460
    padding: 0
    modal:   true
    closePolicy: Popup.NoAutoClose   // no manual close -- auto-closes only

    implicitHeight: col.implicitHeight

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
    background: Rectangle { color: Theme.surfaceContainerLow; radius: Theme.radiusLg }

    // Qt.callLater defers the actual copy one tick so the popup visibly
    // paints at 0% before the sweep starts, instead of opening already full.
    function startImport(sourcePath, fileNameIn) {
        root.fileName       = fileNameIn
        root.importProgress = 0
        root.open()
        Qt.callLater(function() {
            const ok = root.playlistManager
                       ? root.playlistManager.importPlaylistFile(sourcePath, fileNameIn)
                       : false
            root.importProgress = 100   // width Behavior below animates the sweep
            importDoneTimer.ok = ok
            importDoneTimer.start()
        })
    }

    Timer {
        id: importDoneTimer
        property bool ok: false
        interval: 400   // matches the progress-bar width Behavior's duration
        repeat:   false
        onTriggered: {
            root.close()
            root.importFinished(importDoneTimer.ok, root.fileName)
        }
    }

    contentItem: ColumnLayout {
        id: col
        spacing: 0
        width: root.width

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            Text {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: qsTr("IMPORT PLAYLIST")
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.headlineSm
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurface
            }
        }

        // ── Progress bar + name label -- same shape as
        // ExportPlaylistDialog.qml's "Exporting: <file>" running state ────
        ColumnLayout {
            Layout.fillWidth:    true
            Layout.topMargin:    24
            Layout.bottomMargin: 24
            Layout.leftMargin:   24
            Layout.rightMargin:  24
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: qsTr("Importing: ") + root.fileName
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
                color:  Theme.surfaceContainerHigh
                clip:   true

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    color:  Theme.primary
                    width:  parent.width * root.importProgress / 100
                    Behavior on width { NumberAnimation { duration: 400 } }
                }
            }
        }
    }
}
