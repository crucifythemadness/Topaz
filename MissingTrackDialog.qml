import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

// Genuine always-on-top top-level Window (not a Popup) for the "MISSING
// TRACK" alert -- see UC-31. A plain Popup anchored inside Main.qml's
// ApplicationWindow Overlay has no guaranteed stacking order against the
// separate top-level Windows Milkdrop/AudioVisualizer/BigCover/TagInfo use
// (all FloatingPane.qml-based, see that file's own doc comment for why a
// Popup can't leave its owning ApplicationWindow's surface); this dialog
// must render above all of those regardless of what's floating. Not built
// on FloatingPane.qml itself -- that base's whole design is drag-to-move +
// resize + right-click-to-close, the wrong interaction model for a fixed,
// OK-only error alert. Styled to match MessageBox.qml's look instead.
//
// Usage (see Main.qml):
//   MissingTrackDialog { id: missingTrackDialog }
//   missingTrackDialog.artistText = "..."; ...
//   missingTrackDialog.openCentered(root)   // root = the main ApplicationWindow
Window {
    id: root

    property string artistText: ""
    property string albumText:  ""
    property string titleText:  ""

    readonly property string composedMessage:
        qsTr("Track could not be found and can not be played") + "\n" +
        qsTr("Artist: ") + root.artistText + "\n" +
        qsTr("Album: ")  + root.albumText  + "\n" +
        qsTr("Track: ")  + root.titleText

    flags:    Qt.Dialog | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    modality: Qt.ApplicationModal
    color:    "transparent"
    width:    460
    height:   card.implicitHeight
    visible:  false

    // Same alpha-capable-surface + DWM-border-removal prep FloatingPane.qml
    // uses -- must run before the window is ever shown. See windowchrome.h.
    Component.onCompleted: WindowChrome.prepareWindow(root)

    // Centers over mainWindow and brings this window to the front of the
    // whole Topaz process, including any floating FloatingPane windows.
    function openCentered(mainWindow) {
        x = mainWindow.x + (mainWindow.width  - width)  / 2
        y = mainWindow.y + (mainWindow.height - height) / 2
        visible = true
        raise()
        requestActivate()
    }

    Rectangle {
        id: card
        width: root.width
        implicitHeight: cardColumn.implicitHeight
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg

        ColumnLayout {
            id: cardColumn
            width: parent.width
            spacing: 0

            // ── Header bar ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                height: 52
                color:  Theme.surfaceContainerHigh
                radius: Theme.radiusLg

                // Square bottom corners so it sits flush against the body
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: Theme.radiusLg
                    color:  parent.color
                }

                Text {
                    anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                    text: qsTr("MISSING TRACK")
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.headlineSm
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWidest
                    color: Theme.fgSurface
                }
            }

            // ── Message body ─────────────────────────────────────────────
            Text {
                Layout.fillWidth:    true
                Layout.topMargin:    24
                Layout.bottomMargin: 24
                Layout.leftMargin:   24
                Layout.rightMargin:  24
                text: root.composedMessage
                wrapMode: Text.Wrap
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelLg
                color: Theme.fgSurface
                lineHeight: 1.4
            }

            // ── Button row: single OK ────────────────────────────────────
            Item {
                Layout.fillWidth:    true
                Layout.bottomMargin: 20
                height: 36

                Rectangle {
                    anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: okHover.containsMouse ? Theme.primaryContainer
                                                 : Theme.surfaceContainerHigh

                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: okHover.containsMouse ? Theme.fgPrimaryContainer : Theme.primary
                    }

                    MouseArea {
                        id: okHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked:    root.visible = false
                    }
                }
            }
        }
    }
}
