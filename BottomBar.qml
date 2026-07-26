import QtQuick

// Bottom toolbar: Auto Play | Equalizer | Tag Information | Scan Directories
Rectangle {
    id: root
    height: 56
    color: Theme.surfaceContainerLow

    // Emitted when the user clicks the SCAN DIRECTORIES button.
    signal scanRequested()

    // Set by Main.qml when a scan is running; animates the scan button.
    property bool scanning: false

    // Set by Main.qml (bound to libraryModel.ratingsReady). AUTO PLAY only shows
    // as ready (green) once a scan has completed with rating enrichment applied.
    property bool autoPlayReady: false

    // Local toggle state — whether the user has clicked AUTO PLAY "on" (red) since
    // it became ready. Intentionally not persisted: AUTO PLAY must never auto-start
    // at app launch, so this always resets to false on a fresh BottomBar instance.
    // The AUTO PLAY feature itself is not implemented yet, so this only drives the
    // button's traffic-light color for now — no queue-filling behavior is triggered.
    property bool autoPlayActive: false

    // Ghost top border
    Rectangle {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 1
        color: Theme.ov10
    }

    Row {
        anchors.fill: parent

        Repeater {
            model: [
                { label: "AUTO PLAY",       icon: "\u25B6", active: root.autoPlayReady },
                { label: "EQUALIZER",       icon: "\u2261", active: false },
                { label: "TAG INFORMATION", icon: "\u24D8", active: false },
                { label: "SCAN DIRECTORIES",icon: "\u29C9", active: false }
            ]

            delegate: Item {
                width:  root.width / 4
                height: root.height

                readonly property bool isScanBtn:     modelData.label === "SCAN DIRECTORIES"
                readonly property bool isAutoPlayBtn: modelData.label === "AUTO PLAY"

                // Traffic-light color for AUTO PLAY (grey/green/red); every other
                // button keeps its existing scanning/active/inactive coloring.
                readonly property color btnColor:
                    isAutoPlayBtn
                        ? (!root.autoPlayReady ? Theme.fgSurfaceVariant
                           : root.autoPlayActive ? "#FF1744" : "#00C853")
                        : (isScanBtn && root.scanning)
                            ? Theme.tertiary
                            : modelData.active ? Theme.secondary : Theme.fgSurfaceVariant

                Rectangle {
                    anchors.fill: parent
                    color: bbHover.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                }

                Column {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData.icon
                        font.pixelSize: 16
                        color: btnColor
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: (isScanBtn && root.scanning) ? "SCANNING…" : modelData.label
                        font.family: Theme.fontFamilyBody
                        font.pixelSize:    Theme.labelXs
                        font.weight:       Font.Medium
                        font.letterSpacing: 1.0
                        color: btnColor
                    }
                }

                MouseArea {
                    id: bbHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        if (isScanBtn && !root.scanning)
                            root.scanRequested()
                        else if (isAutoPlayBtn && root.autoPlayReady)
                            root.autoPlayActive = !root.autoPlayActive
                    }
                }
            }
        }
    }
}
