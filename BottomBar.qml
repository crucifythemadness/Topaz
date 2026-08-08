import QtQuick

// Bottom toolbar: Auto Play | Audio Visualizer | Tag Information | Scan Directories
Rectangle {
    id: root
    height: 56
    color: Theme.surfaceContainerLow

    // Emitted when the user clicks the SCAN DIRECTORIES button.
    signal scanRequested()

    // Emitted when the user clicks the TAG INFORMATION button — Main.qml owns
    // the actual open/closed state (see tagInfoPaneOpen below) and flips it in
    // response, same "dumb button, owner decides" split as scanRequested().
    signal tagInfoToggleRequested()

    // Same split as tagInfoToggleRequested/tagInfoPaneOpen, for the AUDIO
    // VISUALIZER button.
    signal audioVisualizerToggleRequested()

    // Set by Main.qml when a scan is running; animates the scan button.
    property bool scanning: false

    // Set by Main.qml (bound to root.tagInfoPaneOpen) — drives the TAG
    // INFORMATION button's on/off color, mirroring the pane's actual state.
    property bool tagInfoPaneOpen: false

    // Set by Main.qml (bound to root.audioVisualizerPaneOpen) — drives the
    // AUDIO VISUALIZER button's on/off color, mirroring the pane's actual state.
    property bool audioVisualizerPaneOpen: false

    // Set by Main.qml (bound to libraryModel.ratingsReady). AUTO PLAY only shows
    // as ready (green) once a scan has completed with rating enrichment applied.
    property bool autoPlayReady: false

    // Bound from Main.qml — the real AUTO PLAY session/policy controller.
    // root.autoPlay.active drives the button's red/green traffic-light state;
    // clicking calls root.autoPlay.toggle(). Never persisted: AutoPlayController
    // always starts inactive, so AUTO PLAY never auto-starts at app launch.
    property var autoPlay: null

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
                { label: "AUDIO VISUALIZER", icon: "\u2261", active: false },
                { label: "TAG INFORMATION", icon: "\u24D8", active: false },
                { label: "SCAN DIRECTORIES",icon: "\u29C9", active: false }
            ]

            delegate: Item {
                width:  root.width / 4
                height: root.height

                readonly property bool isScanBtn:     modelData.label === "SCAN DIRECTORIES"
                readonly property bool isAutoPlayBtn: modelData.label === "AUTO PLAY"
                readonly property bool isTagInfoBtn:  modelData.label === "TAG INFORMATION"
                readonly property bool isAudioVisualizerBtn: modelData.label === "AUDIO VISUALIZER"

                // AUTO PLAY is only ready once the library scan has completed
                // AND (when Consider Genre is on) at least one genre is active
                // — with Consider Genre on and zero active genres, AUTO PLAY
                // could never find a single eligible candidate.
                readonly property bool autoPlayGated:
                    root.autoPlayReady && (!root.autoPlay || root.autoPlay.genreRequirementMet)

                // Traffic-light color for AUTO PLAY (grey/green/red); every other
                // button keeps its existing scanning/active/inactive coloring.
                readonly property color btnColor:
                    isAutoPlayBtn
                        ? (!autoPlayGated ? Theme.fgSurfaceVariant
                           : (root.autoPlay && root.autoPlay.active) ? "#FF1744" : "#00C853")
                        : (isScanBtn && root.scanning)
                            ? Theme.tertiary
                            : (isTagInfoBtn && root.tagInfoPaneOpen)
                                ? Theme.secondary
                                : (isAudioVisualizerBtn && root.audioVisualizerPaneOpen)
                                    ? Theme.secondary
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
                        else if (isAutoPlayBtn && autoPlayGated && root.autoPlay)
                            root.autoPlay.toggle()
                        else if (isTagInfoBtn)
                            root.tagInfoToggleRequested()
                        else if (isAudioVisualizerBtn)
                            root.audioVisualizerToggleRequested()
                    }
                }
            }
        }
    }
}
