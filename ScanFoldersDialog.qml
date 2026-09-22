import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts

// ── ScanFoldersDialog ─────────────────────────────────────────────────────
// Opt-in visual feedback for a library scan (Setup > MISC "Visual Folder
// Scanning", default off) -- shows the folder currently being walked, a
// short "recently scanned" file feed, and a progress bar. Unlike every
// other dialog in this app, nothing ever calls .open() on this directly:
// it watches libraryModel.scanning itself and opens/closes on its own,
// covering every scan trigger uniformly (manual SCAN FOLDERS click, the
// startup stat-check, the debounced filesystem-watcher auto-rescan, UC-31's
// scoped rescan) since they all funnel through that one property.
//
// The ✕ close button stays visible even while scanning (unlike
// MilkdropCleanupDialog.qml/ExportPlaylistDialog.qml, which hide it during
// their own run) -- this dialog is a passive viewer, not a controller.
// There is no cancel-scan path exposed to QML, so closing early doesn't
// stop anything; the scan just keeps running invisibly, exactly like
// before this dialog existed.
//
// Usage in Main.qml:
//   ScanFoldersDialog { libraryModel: libraryModel; appConfig: appConfig }
Popup {
    id: root

    property LibraryModel libraryModel: null
    property AppConfig    appConfig: null

    Connections {
        target: root.libraryModel
        function onScanningChanged() {
            if (!root.libraryModel) return
            if (root.libraryModel.scanning) {
                if (root.appConfig && root.appConfig.visualFolderScanning) root.open()
            } else {
                root.close()
            }
        }
    }

    anchors.centerIn: Overlay.overlay
    width:  560
    height: 460
    padding: 0
    modal: true
    closePolicy: Popup.NoAutoClose

    Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.72) }
    background: Rectangle { color: Theme.surfaceContainerLow; radius: Theme.radiusLg }

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
                    text: "SCAN FOLDERS"
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
        ColumnLayout {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            Layout.margins: 24
            spacing: 16

            Item { Layout.fillHeight: true }

            // Swaps to a "finalizing" message once the folder/file-read
            // phase ends -- resolveCoverArt()/LibraryCache::save() still
            // follow (see LibraryModel::onScanProgress()'s doc comment) and
            // would otherwise leave this label frozen on the last folder
            // while the scan keeps running. finalizingScan is a real
            // LibraryModel member (qmllint --ignore-settings reports 0) --
            // see CLAUDE.md's "Editor diagnostics" note.
            // qmllint disable missing-property
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: (root.libraryModel && root.libraryModel.finalizingScan)
                      ? "Finalizing scan (resolving cover art, saving library)…"
                      : "Now scanning: " + (root.libraryModel && root.libraryModel.currentScanFolder.length > 0
                                             ? root.libraryModel.currentScanFolder : "…")
                elide: Text.ElideMiddle
                font.family:    Theme.fontFamilyMono
                font.pixelSize: Theme.monoLg
                color: Theme.fgSurface
            }
            // qmllint enable missing-property

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
                           * (root.libraryModel ? root.libraryModel.scanProgress : 0)
                           / 100
                    Behavior on width { NumberAnimation { duration: 120 } }
                }
            }

            Item { Layout.fillHeight: true }
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
                    color: closeFooterHover.containsMouse
                           ? Theme.primaryContainer : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("CLOSE")
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: closeFooterHover.containsMouse
                               ? Theme.fgPrimaryContainer : Theme.primary
                    }
                    MouseArea {
                        id: closeFooterHover
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
