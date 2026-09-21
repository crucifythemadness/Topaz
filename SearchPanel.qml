import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified

// Replaces LibraryTree in the same SplitView slot when TopBar's SEARCH tab
// is active (see Main.qml's Loader). Entirely independent of LibraryData:
// this file never reads lib.* or calls into LibraryData/LibraryModel's tree
// building — all state lives in SearchData (searchData).
Rectangle {
    id: root
    property SearchData searchData: null
    color: Theme.surfaceContainerLowest

    // Ghost right border -- same chrome as LibraryTree
    Rectangle {
        anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
        width: 1
        color: Theme.ov10
    }

    // ── Header -- matches LibraryTree's "LIBRARY" header exactly ──────────
    Item {
        id: panelHeader
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56

        Text {
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            text: qsTr("SEARCH")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     Theme.labelLg
            font.weight:        Font.Bold
            font.letterSpacing: Theme.lsWidest
            color: Theme.primary
        }
    }

    // ── Query edit -- same Rectangle+TextInput convention as SetupDialog's
    // "add genre" input ────────────────────────────────────────────────────
    Rectangle {
        id: queryBox
        anchors { left: parent.left; right: parent.right; top: panelHeader.bottom }
        anchors { leftMargin: 20; rightMargin: 20; topMargin: 12 }
        height: 36
        color:  Theme.surfaceContainerHigh
        radius: Theme.radiusSm
        border.color: queryInput.activeFocus ? Theme.primary : "transparent"
        border.width: 1

        Text {
            anchors { fill: queryInput }
            visible: queryInput.text.length === 0 && !queryInput.activeFocus
            verticalAlignment: Text.AlignVCenter
            text: qsTr("Search artists, albums, tracks…")
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelLg
            color: Theme.fgSurfaceVariant
        }

        TextInput {
            id: queryInput
            anchors { fill: parent; leftMargin: 12; rightMargin: 32 }
            verticalAlignment: TextInput.AlignVCenter
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelLg
            color:          Theme.fgSurface
            clip:           true
            selectByMouse:  true
            text: root.searchData ? root.searchData.query : ""
            onTextEdited: if (root.searchData) root.searchData.query = text
        }

        // Clear button -- only shown once there's something to clear. Note:
        // queryInput's "text: ..." binding above gets severed by TextInput's
        // own internal edit-handling the moment the user types a first
        // character (any write to a bound property replaces the binding),
        // so clearing must set queryInput.text directly rather than relying
        // on it to follow searchData.query back down to empty.
        Rectangle {
            id: clearButton
            width: 22; height: 22
            radius: Theme.radiusFull
            anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
            visible: queryInput.text.length > 0
            color: clearHover.containsMouse ? Theme.surfaceContainerHighest : "transparent"

            Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 11
                color: Theme.fgSurfaceVariant
            }

            MouseArea {
                id: clearHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape:  Qt.PointingHandCursor
                onClicked: {
                    queryInput.text = ""
                    if (root.searchData) root.searchData.query = ""
                }
            }
        }
    }

    // ── Match whole word checkbox ───────────────────────────────────────────
    Item {
        id: matchWholeWordRow
        anchors { left: parent.left; right: parent.right; top: queryBox.bottom }
        anchors { leftMargin: 20; rightMargin: 20; topMargin: 12 }
        height: 28

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                id: matchWholeWordBox
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: (root.searchData && root.searchData.matchWholeWord)
                       ? Theme.secondaryContainer : "transparent"
                border.width: (root.searchData && root.searchData.matchWholeWord) ? 0 : 1
                border.color: Theme.outlineVariant

                Text {
                    anchors.centerIn: parent
                    visible: root.searchData && root.searchData.matchWholeWord
                    text: "✓"
                    font.pixelSize: 13
                    font.weight:    Font.Bold
                    color: Theme.fgSecondaryContainer
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Match whole word")
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelLg
                color:          Theme.fgSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape:  Qt.PointingHandCursor
            onClicked: if (root.searchData)
                           root.searchData.matchWholeWord = !root.searchData.matchWholeWord
        }
    }

    // ── Consider Genre checkbox ────────────────────────────────────────────
    Item {
        id: considerGenreRow
        anchors { left: parent.left; right: parent.right; top: matchWholeWordRow.bottom }
        anchors { leftMargin: 20; rightMargin: 20; topMargin: 8 }
        height: 28

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Rectangle {
                id: considerGenreBox
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
                radius: 3
                color: (root.searchData && root.searchData.considerGenre)
                       ? Theme.secondaryContainer : "transparent"
                border.width: (root.searchData && root.searchData.considerGenre) ? 0 : 1
                border.color: Theme.outlineVariant

                Text {
                    anchors.centerIn: parent
                    visible: root.searchData && root.searchData.considerGenre
                    text: "✓"
                    font.pixelSize: 13
                    font.weight:    Font.Bold
                    color: Theme.fgSecondaryContainer
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Consider Genre")
                font.family:    Theme.fontFamilyBody
                font.pixelSize: Theme.labelLg
                color:          Theme.fgSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape:  Qt.PointingHandCursor
            onClicked: if (root.searchData)
                           root.searchData.considerGenre = !root.searchData.considerGenre
        }
    }

    // ── Mode toggle buttons -- same tab-button visual language as TopBar,
    // just smaller; only shown once the user has typed something ──────────
    Item {
        id: modeRow
        anchors { left: parent.left; right: parent.right; top: considerGenreRow.bottom }
        anchors { leftMargin: 20; rightMargin: 20; topMargin: 16 }
        height: 24
        visible: root.searchData && root.searchData.query.trim().length > 0

        Row {
            anchors.left: parent.left
            spacing: 16

            Repeater {
                model: [
                    { key: "all",     label: "ALL"     },
                    { key: "artists", label: "ARTISTS" },
                    { key: "albums",  label: "ALBUMS"  },
                    { key: "tracks",  label: "TRACKS"  }
                ]

                delegate: Item {
                    readonly property bool isActive: root.searchData && root.searchData.mode === modelData.key
                    width:  modeLabel.implicitWidth
                    height: modeRow.height

                    Text {
                        id: modeLabel
                        text: modelData.label
                        font.family:        Theme.fontFamilyBody
                        font.pixelSize:     Theme.labelSm
                        font.weight:        isActive ? Font.Bold : Font.Medium
                        font.letterSpacing: Theme.lsWide
                        color: isActive                    ? Theme.primary
                             : modeMA.containsMouse         ? Theme.fgSurface
                             :                                Theme.fgSurfaceVariant
                    }

                    Rectangle {
                        visible: isActive
                        anchors { left: modeLabel.left; right: modeLabel.right; bottom: parent.bottom }
                        height: 2
                        color:  Theme.primary
                    }

                    MouseArea {
                        id: modeMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: if (root.searchData) root.searchData.mode = modelData.key
                    }
                }
            }
        }
    }
}
