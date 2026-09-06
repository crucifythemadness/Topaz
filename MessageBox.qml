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
    property string title: "NOTICE"
    // Opt-in Yes/No-style mode -- defaults preserve every existing call
    // site's plain single-OK-button behavior exactly. When true, the
    // footer shows CANCEL (just closes) and confirmButtonText (styled as a
    // destructive action, closes AND emits accepted()).
    property bool   confirmMode: false
    property string confirmButtonText: qsTr("CONFIRM")

    // Emitted only when confirmMode is true and the confirm button (not
    // CANCEL) is clicked.
    signal accepted()

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
                text: root.title
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Theme.headlineSm
                font.weight:        Font.Bold
                font.letterSpacing: Theme.lsWidest
                color: Theme.fgSurface
            }
        }

        // ── Message body ─────────────────────────────────────────────────
        // textFormat/onLinkActivated let a caller embed a clickable
        // <a href="..."> in `message` (e.g. a download link) -- a plain
        // message with no markup renders identically to before under
        // RichText, so every existing call site is unaffected.
        Text {
            Layout.fillWidth:    true
            Layout.topMargin:    24
            Layout.bottomMargin: 24
            Layout.leftMargin:   24
            Layout.rightMargin:  24
            text: root.message
            textFormat: Text.RichText
            wrapMode: Text.Wrap
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelLg
            color: Theme.fgSurface
            linkColor: Theme.primary
            lineHeight: 1.4
            onLinkActivated: (link) => Qt.openUrlExternally(link)
        }

        // ── Button row: single OK (default), or CANCEL + confirm ──────────
        Item {
            Layout.fillWidth:    true
            Layout.bottomMargin: 20
            height: 36

            Rectangle {
                visible: !root.confirmMode
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

            Row {
                visible: root.confirmMode
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 8

                Rectangle {
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: cancelHover.containsMouse ? Theme.surfaceContainerHighest
                                                     : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: qsTr("CANCEL")
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
                    width: 100; height: 36
                    radius: Theme.radiusSm
                    color: confirmHover.containsMouse ? Theme.errorContainer
                                                      : Theme.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: root.confirmButtonText
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        Font.Bold
                        font.letterSpacing: Theme.lsWidest
                        color: Theme.error
                    }
                    MouseArea {
                        id: confirmHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            root.accepted()
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
