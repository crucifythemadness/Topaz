import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
import QtQuick.Controls

// The playlist buttons NEW | LOAD / EXPORT | REMOVE as a dockable pane
// (UC-38). Moved out of NowPlaying.qml with the same gating; a "fixed" pane
// in Main.qml's dock registry: always docked (by default directly below Now
// Playing), never floating, never closed -- only moved to another zone. UI
// only: every button emits a request that Main.qml handles (LOAD goes to
// NowPlaying.openLoadPlaylist(), whose dialog chain must outlive this view:
// it is recreated on every swap / move).
//
// Look: a header (gradient tick, "PLAYLIST", the loaded playlist's name)
// over a 2 x 2 grid of rounded tiles. Each tile has its own accent from the
// Topaz palette -- NEW teal, LOAD violet, EXPORT amber, REMOVE neon pink --
// shown in its icon chip; on hover the border lights up in the accent with
// a soft glow ring and a faint accent tint, pressed it gives a little. The
// tiles share the pane's height (min 2 x 36 px).
Rectangle {
    id: root
    color: Theme.surfaceContainerLow

    // Named `playback`, not `engine`: Main.qml binds it to its own `engine` id
    // (outer-id shadowing, see UC-38).
    property var playback: null
    property var autoPlayController: null

    signal newRequested()
    signal loadRequested()
    signal exportRequested()
    signal removeRequested()

    readonly property bool queueClearAllowed: !root.autoPlayController
                                              || root.autoPlayController.queueClearAllowed
    readonly property string playlistName: root.playback ? root.playback.activePlaylistName : ""
    readonly property bool hasNamedPlaylist: root.playlistName !== ""

    readonly property int pad: 8
    readonly property int gap: 8

    component PlaylistTile: Item {
        id: tile
        property string label: ""
        property string iconName: ""
        property color  accent: Theme.primary
        property bool   active: true
        property string tooltip: ""
        signal activated()

        readonly property bool lit: active && hover.containsMouse
        readonly property color shownAccent: active ? accent : Theme.outline

        opacity: active ? 1.0 : 0.35
        Behavior on opacity { NumberAnimation { duration: 150 } }

        // Soft glow ring around the tile (hover only)
        Rectangle {
            anchors.fill: face
            anchors.margins: -3
            radius: face.radius + 3
            color: "transparent"
            border.width: 3
            border.color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.22)
            scale: face.scale
            opacity: tile.lit ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
        }

        Rectangle {
            id: face
            anchors.fill: parent
            radius: 10
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.surfaceContainerHighest }
                GradientStop { position: 1.0; color: Theme.surfaceContainer }
            }
            border.width: 1
            border.color: tile.lit ? tile.accent : Theme.ov30
            Behavior on border.color { ColorAnimation { duration: 160 } }
            scale: tile.active && hover.pressed ? 0.97 : 1.0
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutQuad } }

            // Faint accent tint over the gradient while hovered
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(tile.accent.r, tile.accent.g, tile.accent.b, 0.08)
                opacity: tile.lit ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }
            }
            // Thin highlight along the top edge
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 1; leftMargin: parent.radius; rightMargin: parent.radius }
                height: 1
                color: Qt.rgba(1, 1, 1, 0.06)
            }

            Row {
                anchors.centerIn: parent
                spacing: 10

                // Icon chip: a circle in the accent at low alpha, the icon in the accent
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    radius: 14
                    color: Qt.rgba(tile.shownAccent.r, tile.shownAccent.g, tile.shownAccent.b,
                                   tile.lit ? 0.26 : 0.14)
                    Behavior on color { ColorAnimation { duration: 160 } }
                    SvgIcon {
                        anchors.centerIn: parent
                        name: tile.iconName
                        size: 16
                        color: tile.shownAccent
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: tile.label
                    font.family:        Theme.fontFamilyHeadline
                    font.pixelSize:     Theme.labelXl
                    font.weight:        Font.Bold
                    font.letterSpacing: Theme.lsWide
                    color: tile.lit ? Theme.fgSurface : Theme.fgSurfaceVariant
                    Behavior on color { ColorAnimation { duration: 160 } }
                }
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tile.active ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tile.active) tile.activated()

            ToolTip.visible: containsMouse && tile.active
            ToolTip.delay:   600
            ToolTip.text:    tile.tooltip
        }
    }

    // ── Header: gradient tick · PLAYLIST · loaded playlist ───────────────
    Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: root.pad; leftMargin: root.pad + 2; rightMargin: root.pad + 2 }
        height: 16

        Rectangle {
            id: tick
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: 12
            radius: 1.5
            gradient: Gradient {
                GradientStop { position: 0.0; color: Theme.primary }
                GradientStop { position: 1.0; color: Theme.secondary }
            }
        }
        Text {
            id: headerLabel
            anchors { left: tick.right; leftMargin: 8; verticalCenter: parent.verticalCenter }
            text: qsTr("PLAYLIST")
            font.family:        Theme.fontFamilyBody
            font.pixelSize:     Theme.labelSm
            font.weight:        Font.Bold
            font.letterSpacing: Theme.lsWidest
            color: Theme.fgSurfaceVariant
            opacity: 0.8
        }
        Text {
            anchors { left: headerLabel.right; leftMargin: 12; right: parent.right
                      verticalCenter: parent.verticalCenter }
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: root.hasNamedPlaylist ? root.playlistName.replace(/\.xml$/i, "")
                                        : qsTr("none loaded")
            font.family:    Theme.fontFamilyBody
            font.pixelSize: Theme.labelMd
            font.weight:    root.hasNamedPlaylist ? Font.DemiBold : Font.Normal
            font.italic:    !root.hasNamedPlaylist
            color: root.hasNamedPlaylist ? Theme.primary : Theme.outline
        }
    }

    // ── 2 x 2 tiles ──────────────────────────────────────────────────────
    Grid {
        id: grid
        anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                  topMargin: 6; leftMargin: root.pad; rightMargin: root.pad; bottomMargin: root.pad }
        columns: 2
        spacing: root.gap
        readonly property real tileW: (width - spacing) / 2
        readonly property real tileH: Math.max(0, (height - spacing) / 2)

        PlaylistTile {
            width: grid.tileW; height: grid.tileH
            label: qsTr("NEW")
            iconName: "playlist-new"
            accent: Theme.secondary
            tooltip: qsTr("NEW PLAYLIST")
            onActivated: root.newRequested()
        }
        PlaylistTile {
            // Clearing/crossfading happens once the new tracks are known
            // (NowPlaying's loadPlaylistDialog.onAccepted, UC-23).
            width: grid.tileW; height: grid.tileH
            label: qsTr("LOAD")
            iconName: "playlist-load"
            accent: Theme.primary
            tooltip: qsTr("LOAD PLAYLIST")
            active: root.queueClearAllowed
            onActivated: root.loadRequested()
        }
        PlaylistTile {
            width: grid.tileW; height: grid.tileH
            label: qsTr("EXPORT")
            iconName: "playlist-export"
            accent: Theme.tertiary
            tooltip: qsTr("EXPORT PLAYLIST")
            active: root.hasNamedPlaylist && root.playback.queueCount > 0
            onActivated: root.exportRequested()
        }
        PlaylistTile {
            width: grid.tileW; height: grid.tileH
            label: qsTr("REMOVE")
            iconName: "playlist-remove"
            accent: Theme.neonPink
            tooltip: qsTr("REMOVE PLAYLIST")
            active: root.hasNamedPlaylist && root.queueClearAllowed
            onActivated: root.removeRequested()
        }
    }
}
