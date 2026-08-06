import QtQuick
import QtQuick.Controls

// ── TagInfoWindow ────────────────────────────────────────────────────────
// Detachable tag-metadata viewer — see FloatingPane.qml for the movable/
// resizable/right-click-to-close chrome this builds on, and BigCoverWindow.qml
// for the sibling pane it mirrors the wiring pattern of. Opened by clicking
// the "TAG INFORMATION" button in BottomBar.qml (see Main.qml's Loader wiring).
//
// Reuses PlaybackEngine's existing current* metadata properties directly (all
// NOTIFY on currentTrackChanged, same signal NowPlaying.qml's own fields react
// to) — no polling, no local caching, the pane just updates when the track does.
//
// Content-scales-with-pane-size: every font size/padding/spacing below is
// multiplied by scaleFactor, a single ratio derived from how far the pane has
// been resized from its default 460x230. This is what makes the text grow or
// shrink smoothly as the user drags the resize grips, rather than staying
// fixed while empty space grows around it.
//
// Note: the pane's *saved* geometry (Topaz.config's tagInfoPane entry) always
// wins over this default once the user has resized it once — shrinking the
// default here only affects a pane that has never been resized/positioned.
FloatingPane {
    id: tagInfo

    property var engine: null

    title: qsTr("Topaz — Tag Info")
    color: Theme.surfaceContainerLowest

    readonly property real scaleFactor:
        Math.max(0.55, Math.min(2.2, Math.min(width / 460, height / 230)))
    readonly property bool hasTrack: engine && engine.currentTitle.length > 0

    // ── Reusable label-over-value field for the metadata grid ────────────
    component MetadataField: Column {
        id: field
        property string label: ""
        property string value: ""
        property real scale: 1.0
        spacing: 2 * scale

        Text {
            text: field.label
            font.family:        Theme.fontFamilyMono
            font.pixelSize:     Math.max(8, Theme.labelXs * field.scale)
            font.letterSpacing: Theme.lsWide
            font.weight:        Font.Medium
            color: Theme.outline
        }
        Text {
            width: field.width
            text: field.value.length > 0 ? field.value : "—"
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Math.max(10, Theme.titleMd * field.scale)
            color: Theme.fgSurface
            elide: Text.ElideRight

            ToolTip.visible: fieldHover.containsMouse && field.value.length > 0
            ToolTip.text:    field.value
            ToolTip.delay:   500

            MouseArea {
                id: fieldHover
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
        }
    }

    // ── Reusable centered label-over-value cell for the technical-specs box ─
    component SpecField: Column {
        id: spec
        property string label: ""
        property string value: ""
        property real scale: 1.0
        spacing: 2 * scale

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: spec.label
            font.family:        Theme.fontFamilyMono
            font.pixelSize:     Math.max(8, Theme.labelXs * spec.scale)
            font.letterSpacing: Theme.lsWide
            font.weight:        Font.Medium
            color: Theme.outline
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: spec.value
            font.family:    Theme.fontFamilyMono
            font.pixelSize: Math.max(10, Theme.monoMd * spec.scale)
            font.weight:    Font.Medium
            color: Theme.fgSurface
        }
    }

    // ── Placeholder — no track loaded ─────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: !tagInfo.hasTrack
        gradient: Gradient {
            orientation: Gradient.Diagonal
            GradientStop { position: 0.0; color: Theme.surfaceContainerHigh }
            GradientStop { position: 1.0; color: Theme.surfaceBright }
        }
        Text {
            anchors.centerIn: parent
            text: "♫  " + qsTr("NO TRACK")
            font.family:        Theme.fontFamilyHeadline
            font.pixelSize:     22 * tagInfo.scaleFactor
            font.weight:        Font.Bold
            font.letterSpacing: 2
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.30)
        }
    }

    // ── Header strip ───────────────────────────────────────────────────────
    Item {
        id: header
        width:  parent.width
        height: 24 * tagInfo.scaleFactor
        visible: tagInfo.hasTrack

        Row {
            anchors { left: parent.left; leftMargin: 14 * tagInfo.scaleFactor
                      verticalCenter: parent.verticalCenter }
            spacing: 6 * tagInfo.scaleFactor

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ⓘ"
                font.pixelSize: Math.max(10, 13 * tagInfo.scaleFactor)
                color: Theme.fgSurfaceVariant
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("TAG INFORMATION")
                font.family:        Theme.fontFamilyMono
                font.pixelSize:     Math.max(8, Theme.labelXs * tagInfo.scaleFactor)
                font.letterSpacing: Theme.lsWidest
                font.weight:        Font.Medium
                color: Theme.fgSurfaceVariant
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.ov20
        }
    }

    // ── Body ───────────────────────────────────────────────────────────────
    Column {
        id: body
        anchors { top: header.bottom; left: parent.left; right: parent.right }
        visible: tagInfo.hasTrack
        padding: 10 * tagInfo.scaleFactor
        spacing: 6 * tagInfo.scaleFactor

        readonly property real contentWidth: width - leftPadding - rightPadding

        // Title + format badge
        Item {
            width:  body.contentWidth
            height: titleText.implicitHeight

            Text {
                id: titleText
                anchors { left: parent.left; right: formatBadge.left
                          rightMargin: 8 * tagInfo.scaleFactor
                          verticalCenter: parent.verticalCenter }
                text: tagInfo.engine ? tagInfo.engine.currentTitle.toUpperCase() : ""
                font.family:        Theme.fontFamilyHeadline
                font.pixelSize:     Math.max(12, Theme.headlineMd * tagInfo.scaleFactor)
                font.weight:        Font.Black
                font.letterSpacing: Theme.lsTight
                color: Theme.fgSurface
                elide: Text.ElideRight
            }

            Rectangle {
                id: formatBadge
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: tagInfo.engine && tagInfo.engine.currentFormat.length > 0
                height: 22 * tagInfo.scaleFactor
                radius: Theme.radiusFull
                width:  formatLabel.implicitWidth + 16 * tagInfo.scaleFactor
                color:  Theme.surfaceContainerHigh
                border.width: 1
                border.color: Theme.secondary

                Text {
                    id: formatLabel
                    anchors.centerIn: parent
                    text: tagInfo.engine ? tagInfo.engine.currentFormat : ""
                    font.family:    Theme.fontFamilyMono
                    font.pixelSize: Math.max(8, Theme.monoSm * tagInfo.scaleFactor)
                    font.weight:    Font.Bold
                    color: Theme.secondary
                }
            }
        }

        // Artist subtitle
        Text {
            width: body.contentWidth
            text: tagInfo.engine ? tagInfo.engine.currentArtist.toUpperCase() : ""
            font.family:        Theme.fontFamilyBody
            font.pixelSize:     Math.max(10, Theme.labelLg * tagInfo.scaleFactor)
            font.weight:        Font.SemiBold
            font.letterSpacing: Theme.lsWide
            color: Theme.secondary
            elide: Text.ElideRight
        }

        Rectangle {
            width:  body.contentWidth
            height: 1
            color:  Theme.ov20
        }

        // Metadata grid — Album / Album Artist, Genre / Year
        Grid {
            width: body.contentWidth
            columns: 2
            columnSpacing: 24 * tagInfo.scaleFactor
            rowSpacing:    6 * tagInfo.scaleFactor

            readonly property real fieldWidth: (width - columnSpacing) / 2

            MetadataField {
                width: parent.fieldWidth
                label: qsTr("ALBUM")
                value: tagInfo.engine ? tagInfo.engine.currentAlbum : ""
                scale: tagInfo.scaleFactor
            }
            MetadataField {
                width: parent.fieldWidth
                label: qsTr("ALBUM ARTIST")
                value: tagInfo.engine ? tagInfo.engine.currentAlbumArtist : ""
                scale: tagInfo.scaleFactor
            }
            MetadataField {
                width: parent.fieldWidth
                label: qsTr("GENRE")
                value: tagInfo.engine ? tagInfo.engine.currentGenre : ""
                scale: tagInfo.scaleFactor
            }
            MetadataField {
                width: parent.fieldWidth
                label: qsTr("YEAR")
                value: (tagInfo.engine && tagInfo.engine.currentYear > 0)
                       ? String(tagInfo.engine.currentYear) : ""
                scale: tagInfo.scaleFactor
            }
        }

        // Technical specs box — Track / Duration / Bitrate
        Rectangle {
            id: specBox
            width:  body.contentWidth
            height: 48 * tagInfo.scaleFactor
            radius: Theme.radiusMd
            color:  Theme.surfaceContainer
            border.width: 1
            border.color: Theme.ov20

            readonly property real colWidth: width / 3

            Row {
                anchors.fill: parent

                Item {
                    width: specBox.colWidth; height: parent.height
                    SpecField {
                        anchors.centerIn: parent
                        label: qsTr("TRACK")
                        value: (tagInfo.engine && tagInfo.engine.currentTrackNumber > 0)
                               ? String(tagInfo.engine.currentTrackNumber).padStart(2, '0')
                               : "—"
                        scale: tagInfo.scaleFactor
                    }
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom
                                  topMargin: 8 * tagInfo.scaleFactor; bottomMargin: 8 * tagInfo.scaleFactor }
                        width: 1
                        color: Theme.ov20
                    }
                }
                Item {
                    width: specBox.colWidth; height: parent.height
                    SpecField {
                        anchors.centerIn: parent
                        label: qsTr("DURATION")
                        value: tagInfo.engine ? tagInfo.engine.durationString : "0:00"
                        scale: tagInfo.scaleFactor
                    }
                    Rectangle {
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom
                                  topMargin: 8 * tagInfo.scaleFactor; bottomMargin: 8 * tagInfo.scaleFactor }
                        width: 1
                        color: Theme.ov20
                    }
                }
                Item {
                    width: specBox.colWidth; height: parent.height
                    SpecField {
                        anchors.centerIn: parent
                        label: qsTr("BITRATE")
                        value: tagInfo.engine
                               ? (tagInfo.engine.currentBitrate + " KBPS")
                               : ""
                        scale: tagInfo.scaleFactor
                    }
                }
            }
        }
    }
}
