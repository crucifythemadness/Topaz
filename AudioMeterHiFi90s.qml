import QtQuick
// qmllint: style-only hints switched off for this file (see "Editor diagnostics" in CLAUDE.md)
// qmllint disable unqualified
import QtQuick.Effects

// ── AudioMeterHiFi90s ────────────────────────────────────────────────────
// First Audio Meter style (UC-37): a 90s HiFi peak meter. Two rows (L/R) of
// 23 rectangular segments on a dark glass panel, green -> yellow -> orange
// (or the Topaz colours, see colorScheme),
// a peak-hold segment, a digital dBFS scale underneath and a red OVER lamp.
// Unlit segments stay faintly visible like on a real deck; lit segments
// glow (one blurred copy of the lit layer, not one effect per segment).
// Purely a renderer: levels and ballistics come from AudioMeterController.
Item {
    id: root

    property var  meter: null          // AudioMeterController
    property bool peakHold: true
    property real panelOpacity: 1.0    // background only, segments stay opaque
    // "hifi" (default): classic green -> yellow -> orange. "topaz": the app's
    // own colours -- teal (Theme.secondary) -> violet (Theme.primaryContainer)
    // -> neon pink (the TOPAZ lettering's glow). Layout and behaviour are the
    // same; the OVER lamp stays red in both (a warning).
    property string colorScheme: "hifi"
    readonly property bool topaz: colorScheme === "topaz"

    // Segment thresholds (dBFS): a segment lights when the level reaches it.
    // Spaced so every scale label sits exactly under its own segment.
    readonly property var thresholds: [-50, -45, -40, -35, -30, -25, -20, -18, -16, -14,
                                       -12, -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0]
    readonly property var labels: [-50, -40, -20, -12, -8, -6, -4, -2, 0]
    readonly property int count: thresholds.length

    // Named after the classic set; in "topaz" they hold its counterparts.
    readonly property color green:   topaz ? Theme.secondary        : "#3DFF7A"   // low  (<= -20)
    readonly property color yellow:  topaz ? Theme.primaryContainer : "#FFE14A"   // mid  (-8)
    readonly property color orange:  topaz ? "#FF4FB8"              : "#FF8A1F"   // high (-2), scale labels
    readonly property color hot:     topaz ? "#FF2E8A"              : "#FF5A1F"   // 0 dB
    readonly property color overRed: topaz ? Theme.danger           : "#FF2D45"

    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }
    function colorFor(db) {
        if (db <= -20) return green
        if (db <= -8)  return mix(green, yellow, (db + 20) / 12)
        if (db <= -2)  return mix(yellow, orange, (db + 8) / 6)
        return mix(orange, hot, (db + 2) / 2)
    }
    // Highest segment index the given level reaches, -1 = none.
    function indexFor(db) {
        let idx = -1
        for (let i = 0; i < count; ++i)
            if (db >= thresholds[i]) idx = i
        return idx
    }

    readonly property real floorDb: meter ? meter.floorDb : -60
    readonly property int litL:  indexFor(meter ? meter.peakLeftDb  : floorDb)
    readonly property int litR:  indexFor(meter ? meter.peakRightDb : floorDb)
    readonly property int holdL: peakHold ? indexFor(meter ? meter.holdLeftDb  : floorDb) : -1
    readonly property int holdR: peakHold ? indexFor(meter ? meter.holdRightDb : floorDb) : -1
    readonly property bool over: meter ? meter.over : false

    // ── Geometry (everything scales with the pane) ────────────────────────
    readonly property real m:      Math.max(8, Math.min(width, height) * 0.07)
    readonly property real labelW: Math.max(16, height * 0.13)
    readonly property real overW:  Math.max(46, Math.min(width * 0.12, height * 0.6))
    readonly property real colGap: Math.max(6, width * 0.012)
    readonly property real scaleH: Math.max(12, Math.min(18, height * 0.13))
    readonly property real rowGap: Math.max(4, height * 0.05)
    readonly property real segGap: Math.max(2, segArea.width * 0.006)
    readonly property real segW:   (segArea.width - segGap * (count - 1)) / count
    readonly property real rowH:   Math.min(Math.max(6, (segArea.height - rowGap) / 2), segW * 2.6)

    // ── Panel: dark glass with a soft top sheen ───────────────────────────
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 10
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.09, 0.085, 0.115, root.panelOpacity) }
            GradientStop { position: 1.0; color: Qt.rgba(0.035, 0.035, 0.05, root.panelOpacity) }
        }
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.07 * root.panelOpacity)

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            height: parent.height * 0.45
            radius: parent.radius
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06 * root.panelOpacity) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }

    // ── L / R labels ──────────────────────────────────────────────────────
    Repeater {
        model: ["L", "R"]
        Text {
            required property int index
            required property string modelData
            x: root.m
            width: root.labelW
            y: segArea.y + root.rowY(index)
            height: root.rowH
            text: modelData
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.family: Theme.fontFamilyHeadline
            font.weight: Font.Bold
            font.pixelSize: Math.max(9, Math.min(16, root.rowH * 0.8))
            color: Qt.rgba(Theme.fgSurfaceVariant.r, Theme.fgSurfaceVariant.g,
                           Theme.fgSurfaceVariant.b, 0.75)
        }
    }

    function rowY(row) {
        const total = rowH * 2 + rowGap
        const top = (segArea.height - total) / 2
        return top + row * (rowH + rowGap)
    }

    // ── Segment area ──────────────────────────────────────────────────────
    Item {
        id: segArea
        x: root.m + root.labelW + root.colGap
        y: root.m
        width: root.width - x - root.colGap - root.overW - root.m
        height: root.height - 2 * root.m - root.scaleH - 2

        // Unlit segments: the "switched off" deck look.
        Repeater {
            model: root.count * 2
            Rectangle {
                required property int index
                readonly property int seg: index % root.count
                readonly property int row: Math.floor(index / root.count)
                x: seg * (root.segW + root.segGap)
                y: root.rowY(row)
                width: root.segW
                height: root.rowH
                radius: Math.min(2.5, root.segW * 0.2)
                readonly property color c: root.colorFor(root.thresholds[seg])
                color: Qt.rgba(c.r * 0.22, c.g * 0.22, c.b * 0.22, 1)
                border.width: 1
                border.color: Qt.rgba(c.r, c.g, c.b, 0.10)
            }
        }

        // Glow: a blurred copy of the lit layer underneath it.
        MultiEffect {
            anchors.fill: litLayer
            source: litLayer
            blurEnabled: true
            blur: 1.0
            blurMax: 24
            brightness: 0.15
            opacity: 0.85
        }

        Item {
            id: litLayer
            anchors.fill: parent

            Repeater {
                model: root.count * 2
                Rectangle {
                    required property int index
                    readonly property int seg: index % root.count
                    readonly property int row: Math.floor(index / root.count)
                    readonly property int lit:  row === 0 ? root.litL  : root.litR
                    readonly property int hold: row === 0 ? root.holdL : root.holdR
                    readonly property bool isHold: seg === hold && hold > lit
                    readonly property bool on: seg <= lit || isHold
                    x: seg * (root.segW + root.segGap)
                    y: root.rowY(row)
                    width: root.segW
                    height: root.rowH
                    radius: Math.min(2.5, root.segW * 0.2)
                    visible: on
                    readonly property color c: root.colorFor(root.thresholds[seg])
                    color: isHold ? Qt.lighter(c, 1.25) : c

                    // Glass reflection on the upper half of each lit segment.
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                        height: parent.height * 0.45
                        radius: parent.radius
                        color: Qt.rgba(1, 1, 1, 0.28)
                    }
                }
            }
        }
    }

    // ── dBFS scale ────────────────────────────────────────────────────────
    Item {
        id: scaleRow
        x: segArea.x
        y: segArea.y + segArea.height + 2
        width: segArea.width
        height: root.scaleH

        Repeater {
            model: root.labels
            Item {
                required property int modelData
                readonly property int seg: root.thresholds.indexOf(modelData)
                x: seg * (root.segW + root.segGap) + root.segW / 2
                height: parent.height

                Rectangle {   // tick
                    anchors.horizontalCenter: parent.left
                    y: 0
                    width: 1
                    height: Math.max(2, parent.height * 0.18)
                    color: Qt.rgba(Theme.fgSurfaceVariant.r, Theme.fgSurfaceVariant.g,
                                   Theme.fgSurfaceVariant.b, 0.45)
                }
                Text {
                    anchors.horizontalCenter: parent.left
                    anchors.bottom: parent.bottom
                    text: modelData === 0 ? "0" : "−" + Math.abs(modelData)
                    font.family: Theme.fontFamilyMono
                    font.pixelSize: Math.max(8, root.scaleH * 0.62)
                    color: modelData >= -8
                           ? Qt.rgba(root.orange.r, root.orange.g, root.orange.b, 0.80)
                           : Qt.rgba(Theme.fgSurfaceVariant.r, Theme.fgSurfaceVariant.g,
                                     Theme.fgSurfaceVariant.b, 0.70)
                }
            }
        }
    }

    Text {   // unit, under the L/R column
        x: root.m
        width: root.labelW
        y: scaleRow.y
        height: scaleRow.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignBottom
        text: "dB"
        font.family: Theme.fontFamilyMono
        font.pixelSize: Math.max(8, root.scaleH * 0.55)
        color: Qt.rgba(Theme.fgSurfaceVariant.r, Theme.fgSurfaceVariant.g,
                       Theme.fgSurfaceVariant.b, 0.55)
    }

    // ── OVER lamp ─────────────────────────────────────────────────────────
    Item {
        id: overBox
        x: segArea.x + segArea.width + root.colGap
        y: segArea.y + root.rowY(0)
        width: root.overW
        height: root.rowH * 2 + root.rowGap

        MultiEffect {
            anchors.fill: lamp
            source: lamp
            visible: root.over
            shadowEnabled: true
            shadowColor: root.overRed
            shadowBlur: 1.0
            blurMax: 28
            shadowOpacity: 1.0
            shadowScale: 1.08
        }

        Rectangle {
            id: lamp
            anchors.fill: parent
            radius: 4
            gradient: Gradient {
                // Off: the lamp colour darkened (classic: #3A0E15 / #24080D)
                GradientStop { position: 0.0; color: root.over ? Qt.lighter(root.overRed, 1.25)
                                                               : Qt.rgba(root.overRed.r * 0.23, root.overRed.g * 0.23, root.overRed.b * 0.23, 1) }
                GradientStop { position: 1.0; color: root.over ? root.overRed
                                                               : Qt.rgba(root.overRed.r * 0.14, root.overRed.g * 0.14, root.overRed.b * 0.14, 1) }
            }
            border.width: 1
            border.color: root.over ? Qt.lighter(root.overRed, 1.4) : Qt.rgba(1, 0.18, 0.27, 0.25)

            Rectangle {   // glass reflection
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
                height: parent.height * 0.45
                radius: parent.radius
                color: Qt.rgba(1, 1, 1, root.over ? 0.22 : 0.05)
            }
            Text {
                anchors.centerIn: parent
                text: "OVER"
                font.family: Theme.fontFamilyHeadline
                font.weight: Font.Black
                font.letterSpacing: 1
                font.pixelSize: Math.max(9, Math.min(15, parent.width * 0.24, parent.height * 0.4))
                color: root.over ? "#FFFFFF" : Qt.rgba(1, 0.35, 0.42, 0.45)
            }
        }
    }

    Text {   // which source is measuring, under the lamp
        x: overBox.x
        width: overBox.width
        y: scaleRow.y
        height: scaleRow.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignBottom
        text: root.meter ? root.meter.sourceName : ""
        font.family: Theme.fontFamilyMono
        font.pixelSize: Math.max(7, root.scaleH * 0.5)
        font.letterSpacing: 1
        color: Qt.rgba(0x3B / 255, 0xE8 / 255, 1, 0.55)
    }
}
