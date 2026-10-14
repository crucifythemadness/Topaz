import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// Grid of genre toggle buttons, 10 per row, up to 4 rows (40 enabled genres,
// AppConfig.maxEnabledGenres()). The bar's height follows the number of rows.
// Active genres are highlighted with secondaryContainer background.
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

            delegate: Rectangle {
                id: genreBtn
                // Equal width: fill available width across 10 columns with 9 gaps
                width:  (genreGrid.width - 9 * 6) / 10
                height: 34
                radius: Theme.radiusSm

                property bool active: model.active
                property bool hovered: genreHover.containsMouse

                color: {
                    if (active)  return Theme.secondaryContainer
                    if (hovered) return Theme.surfaceContainerHighest
                    return Theme.surfaceContainerHigh
                }

                // "Hover glow" вЂ” 2 px top-edge primary highlight (design: micro-slab rule)
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 2
                    color: Theme.primary
                    visible: genreBtn.hovered && !genreBtn.active
                    radius: Theme.radiusSm
                }

                Text {
                    anchors.centerIn: parent
                    text: model.name.toUpperCase()
                    font.family: Theme.fontFamilyBody
                    font.pixelSize:    Theme.labelSm
                    font.weight:       active ? Font.Bold : Font.Normal
                    font.letterSpacing: 1.2
                    color: active ? Theme.fgSecondaryContainer : Theme.fgSurfaceVariant
                    elide: Text.ElideRight
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
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
