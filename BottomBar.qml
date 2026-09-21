import QtQuick

// Bottom toolbar: Auto Play | Audio Visualizer | Milkdrop | Tag Information | Scan Folders
Rectangle {
    id: root
    height: 56
    color: Theme.surfaceContainerLow

    // Emitted when the user clicks the SCAN FOLDERS button.
    signal scanRequested()

    // Emitted when the user clicks the TAG INFORMATION button — Main.qml owns
    // the actual open/closed state (see tagInfoPaneOpen below) and flips it in
    // response, same "dumb button, owner decides" split as scanRequested().
    signal tagInfoToggleRequested()

    // Same split as tagInfoToggleRequested/tagInfoPaneOpen, for the AUDIO
    // VISUALIZER button.
    signal audioVisualizerToggleRequested()

    // Same split again, for the MILKDROP button.
    signal milkdropToggleRequested()

    // Set by Main.qml when a scan is running; animates the scan button.
    property bool scanning: false

    // Set by Main.qml (bound to root.tagInfoPaneOpen) — drives the TAG
    // INFORMATION button's on/off color, mirroring the pane's actual state.
    property bool tagInfoPaneOpen: false

    // Set by Main.qml (bound to root.audioVisualizerPaneOpen) — drives the
    // AUDIO VISUALIZER button's on/off color, mirroring the pane's actual state.
    property bool audioVisualizerPaneOpen: false

    // Same split again, for the MILKDROP button.
    property bool milkdropPaneOpen: false

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
                { label: "MILKDROP",        icon: "\u2733", active: false },
                { label: "TAG INFORMATION", icon: "\u24D8", active: false },
                { label: "SCAN FOLDERS",    icon: "\u29C9", active: false }
            ]

            delegate: Item {
                width:  root.width / 5
                height: root.height

                readonly property bool isScanBtn:     modelData.label === "SCAN FOLDERS"
                readonly property bool isAutoPlayBtn: modelData.label === "AUTO PLAY"
                readonly property bool isTagInfoBtn:  modelData.label === "TAG INFORMATION"
                readonly property bool isAudioVisualizerBtn: modelData.label === "AUDIO VISUALIZER"
                readonly property bool isMilkdropBtn: modelData.label === "MILKDROP"

                // AUTO PLAY is only ready once the library scan has completed
                // AND its criteria leave something to play: (when Consider
                // Genre is on) at least one genre is active, and (when Consider
                // Rating is on) at least one track passes the rating filter --
                // otherwise AUTO PLAY could never find a single eligible
                // candidate. The two criteria only guard STARTING a session: a
                // running session always keeps its button live, so it can
                // still be stopped if the criteria stop being met mid-session
                // (all genres untoggled, a rating deleted, the minimum raised);
                // the session then starves by itself at the next top-up.
                readonly property bool autoPlayGated:
                    root.autoPlayReady && (!root.autoPlay || root.autoPlay.active
                        || (root.autoPlay.genreRequirementMet && root.autoPlay.ratingRequirementMet))

                // Traffic-light color for AUTO PLAY (grey/green/red); every other
                // button keeps its existing scanning/active/inactive coloring.
                readonly property color btnColor:
                    isAutoPlayBtn
                        ? (!autoPlayGated ? Theme.fgSurfaceVariant
                           : (root.autoPlay && root.autoPlay.active) ? "#FF1744" : "#00C853")
                        : (isScanBtn && root.scanning)
                            ? Theme.tertiary
                            : (isTagInfoBtn && root.tagInfoPaneOpen)
                                ? Theme.tertiary
                                : (isAudioVisualizerBtn && root.audioVisualizerPaneOpen)
                                    ? Theme.tertiary
                                    : (isMilkdropBtn && root.milkdropPaneOpen)
                                        ? Theme.tertiary
                                        : modelData.active ? Theme.secondary : Theme.fgSurfaceVariant

                Rectangle {
                    anchors.fill: parent
                    color: bbHover.containsMouse ? Theme.surfaceContainerHigh : "transparent"
                }

                Column {
                    id: btnContent
                    anchors.centerIn: parent
                    spacing: 3

                    // Blinks the red "AUTO PLAY is active" state for
                    // attention -- never affects any other button.
                    readonly property bool blinkingActive:
                        isAutoPlayBtn && root.autoPlay && root.autoPlay.active

                    SequentialAnimation on opacity {
                        running: btnContent.blinkingActive
                        loops: Animation.Infinite
                        NumberAnimation { from: 1.0; to: 0.3; duration: 500 }
                        NumberAnimation { from: 0.3; to: 1.0; duration: 500 }
                    }
                    onBlinkingActiveChanged: if (!blinkingActive) opacity = 1.0   // animation.stop() can land mid-fade

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
                        else if (isMilkdropBtn)
                            root.milkdropToggleRequested()
                    }
                }
            }
        }
    }
}
