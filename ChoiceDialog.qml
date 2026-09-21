import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
// qmllint disable Quick.layout-positioning
import QtQuick.Controls
import QtQuick.Layouts

// ── ChoiceDialog ──────────────────────────────────────────────────────────
// Generic N-button choice dialog -- MessageBox.qml's confirmMode maxes out
// at exactly 2 buttons by construction (a fixed CANCEL + one styled confirm
// button); this serves the 3- and 4-choice prompts UC-27's RESTORE flow
// needs (PLAYLIST EXISTS: YES/NO/RENAME; RATINGS EXIST: YES/NO/MERGE NEW/
// MERGE ALL) with one reusable component instead of two bespoke dialogs.
//
// Usage:
//   ChoiceDialog { id: cd
//                  title: "PLAYLIST EXISTS"
//                  message: "..."
//                  choices: ["YES", "NO", "RENAME"]
//                  onChoiceMade: (choice) => { ... } }
//   cd.open()
Popup {
    id: root

    property string title:   ""
    property string message: ""
    property var    choices: []   // e.g. ["YES", "NO", "RENAME"]

    // Emitted (then the popup closes) when any choice button is clicked --
    // never for a background/scrim click, since closePolicy is NoAutoClose.
    signal choiceMade(string choice)

    anchors.centerIn: Overlay.overlay
    width:  460
    padding: 0
    modal:  true
    closePolicy: Popup.NoAutoClose

    implicitHeight: dcColumn.implicitHeight

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.72)
    }

    background: Rectangle {
        color:  Theme.surfaceContainerLow
        radius: Theme.radiusLg
    }

    contentItem: ColumnLayout {
        id: dcColumn
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
                text: root.title
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

        // ── Choice buttons ───────────────────────────────────────────────
        Item {
            Layout.fillWidth:    true
            Layout.bottomMargin: 20
            height: 36

            Row {
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 8

                Repeater {
                    model: root.choices

                    delegate: Rectangle {
                        width: choiceLabel.implicitWidth + 32
                        height: 36
                        radius: Theme.radiusSm
                        color: choiceHover.containsMouse ? Theme.surfaceContainerHighest
                                                          : Theme.surfaceContainerHigh

                        Text {
                            id: choiceLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.family:        Theme.fontFamilyBody
                            font.pixelSize:     Theme.labelSm
                            font.weight:        Font.Bold
                            font.letterSpacing: Theme.lsWidest
                            color: Theme.primary
                        }
                        MouseArea {
                            id: choiceHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape:  Qt.PointingHandCursor
                            onClicked: {
                                // Close BEFORE emitting: choiceMade()'s
                                // handler may synchronously reopen this
                                // same dialog instance (e.g. RestoreDialog
                                // advancing to the next queued conflict) --
                                // emitting first meant the close() below
                                // used to run after that reopen and
                                // immediately undo it, silently dropping
                                // every conflict after the first.
                                root.close()
                                root.choiceMade(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
