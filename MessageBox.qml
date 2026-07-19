import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Themed message box — shows a single message with an OK button.
// Matches the "Technical Monolith" dark theme used throughout Topaz.
//
// Usage:
//   MessageBox { id: mb }
//   mb.message = "Something went wrong."
//   mb.open()
Popup {
    id: root

    property string message: ""

    anchors.centerIn: Overlay.overlay
    width:  460
    padding: 0
    modal:  true
    closePolicy: Popup.NoAutoClose

    // Fixed height derived from content
    implicitHeight: mbColumn.implicitHeight

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    contentItem: ColumnLayout {
        id: mbColumn
        spacing: 0
        width: root.width

        // ── Header bar ───────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 52
            color:  Theme.surfaceContainerHigh
            radius: Theme.radiusLg

            // Square bottom corners so it sits flush against body
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.radiusLg
                color:  parent.color
            }

            Text {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                text: "NOTICE"
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.headlineSm
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurface
            }
        }

        // ── Message body ─────────────────────────────────────────────────
        Text {
            Layout.fillWidth:    true
            Layout.topMargin:    24
            Layout.bottomMargin: 24
            Layout.leftMargin:   24
            Layout.rightMargin:  24
            text: root.message
            wrapMode: Text.Wrap
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelLg
            color: Theme.fgSurface
            lineHeight: 1.4
        }

        // ── OK button row ─────────────────────────────────────────────────
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
                    onClicked:    root.close()
                }
            }
        }
    }
}
