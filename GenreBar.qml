import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// Grid of genre toggle buttons, 10 per row, up to 4 rows (40 enabled genres,
// AppConfig.maxEnabledGenres()). The bar's height follows the number of rows.
// Buttons use the PlaylistButtonsView tile style (teal accent; active genres
// keep the accent border, tint, glow and a bold teal label).
// lib.genreModel drives the button states; lib.toggleGenre() handles clicks.
Rectangle {
    id: root
    property var lib: null
    color: Theme.surfaceContainerLow

    // Auto-size height to fit the grid rows + vertical padding
    implicitHeight: genreGrid.implicitHeight + 24

    // Ghost bottom border
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 1
        color: Theme.ov10
    }

    // genreModel is now owned by LibraryData and passed via lib.genreModel.

    Grid {
        id: genreGrid
        anchors {
            left: parent.left; right: parent.right
            top: parent.top
            leftMargin: 24; rightMargin: 24; topMargin: 12
        }
        columns: 10
        rowSpacing:    6
        columnSpacing: 6

        Repeater {
            model: lib ? lib.genreModel : null

            // Same tile style as PlaylistButtonsView (without the icon chip):
            // rounded dark gradient, 1 px border, accent glow ring + tint on
            // hover, small press-in. Accent = Theme.secondary (teal). Active
            // genres keep the accent border, a stronger tint, a fainter glow
            // ring and a bold teal label, so on/off reads at a glance.
            delegate: Item {
                id: genreBtn
                // Equal width: fill available width across 10 columns with 9 gaps
                width:  (genreGrid.width - 9 * 6) / 10
                height: 34

                property bool active: model.active
                property bool hovered: genreHover.containsMouse
                readonly property color accent: Theme.secondary

                // Glow ring (fits the 6 px grid gap)
                Rectangle {
                    anchors.fill: face
                    anchors.margins: -3
                    radius: face.radius + 3
                    color: "transparent"
                    border.width: 3
                    border.color: Qt.rgba(genreBtn.accent.r, genreBtn.accent.g, genreBtn.accent.b,
                                          genreBtn.hovered ? 0.22 : 0.12)
                    scale: face.scale
                    opacity: (genreBtn.hovered || genreBtn.active) ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                Rectangle {
                    id: face
                    anchors.fill: parent
                    radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Theme.surfaceContainerHighest }
                        GradientStop { position: 1.0; color: Theme.surfaceContainer }
                    }
                    border.width: 1
                    border.color: genreBtn.active  ? genreBtn.accent
                                : genreBtn.hovered ? Qt.rgba(genreBtn.accent.r, genreBtn.accent.g,
                                                             genreBtn.accent.b, 0.7)
                                :                    Theme.ov30
                    Behavior on border.color { ColorAnimation { duration: 160 } }
                    scale: genreHover.pressed ? 0.96 : 1.0
                    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

                    // Accent tint: stronger while active
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Qt.rgba(genreBtn.accent.r, genreBtn.accent.g, genreBtn.accent.b,
                                       genreBtn.active ? (genreBtn.hovered ? 0.22 : 0.16) : 0.08)
                        opacity: (genreBtn.active || genreBtn.hovered) ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                    // Thin highlight along the top edge
                    Rectangle {
                        anchors { top: parent.top; left: parent.left; right: parent.right
                                  topMargin: 1; leftMargin: parent.radius; rightMargin: parent.radius }
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.06)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: model.name.toUpperCase()
                        font.family:        Theme.fontFamilyHeadline
                        font.pixelSize:     Theme.labelSm
                        font.weight:        genreBtn.active ? Font.Bold : Font.DemiBold
                        font.letterSpacing: 1.2
                        color: genreBtn.active  ? genreBtn.accent
                             : genreBtn.hovered ? Theme.fgSurface
                             :                    Theme.fgSurfaceVariant
                        Behavior on color { ColorAnimation { duration: 160 } }
                        elide: Text.ElideRight
                        width: parent.width - 8
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MouseArea {
                    id: genreHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: { if (lib) lib.toggleGenre(index) }
                }
            }
        }
    }
}
