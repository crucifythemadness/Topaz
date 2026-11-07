import QtQuick

// Thin "mini knob" drawn around TopBar's loudspeaker icon: shows the current
// OS volume at a glance without opening the VolumeKnob pane. Same geometry and
// colours as VolumeKnob.qml (270° arc open at the bottom, 135° -> 405°, track
// in surfaceContainerHighest, value arc secondary -> primary -> tertiary,
// 35 % alpha while muted) so the two read as one control -- keep them in step.
// No glow and no handle: too small for either.
Item {
    id: root

    property int value: 0          // 0..100
    property bool muted: false
    property real lineWidth: 2

    implicitWidth:  32
    implicitHeight: 32

    readonly property real startDeg: 135
    readonly property real sweepDeg: 270

    onValueChanged:  ring.requestPaint()
    onMutedChanged:  ring.requestPaint()
    onWidthChanged:  ring.requestPaint()
    onHeightChanged: ring.requestPaint()

    // Same helpers as VolumeKnob.qml.
    function colorAt(f) {
        const a = f < 0.5 ? Theme.secondary : Theme.primary
        const b = f < 0.5 ? Theme.primary   : Theme.tertiary
        const t = f < 0.5 ? f * 2 : (f - 0.5) * 2
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t, 1)
    }
    function css(c, alpha) {
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + ","
               + Math.round(c.b * 255) + "," + (c.a * alpha) + ")"
    }
    function rad(deg) { return deg * Math.PI / 180 }

    Canvas {
        id: ring
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const cx = width / 2
            const cy = height / 2
            const r  = Math.min(width, height) / 2 - root.lineWidth / 2
            const f  = Math.max(0, Math.min(100, root.value)) / 100
            const alpha = root.muted ? 0.35 : 1.0

            ctx.lineWidth = root.lineWidth
            ctx.lineCap = "round"

            // Track -- the full 270°
            ctx.beginPath()
            ctx.arc(cx, cy, r, root.rad(root.startDeg),
                    root.rad(root.startDeg + root.sweepDeg), false)
            ctx.strokeStyle = root.css(Theme.surfaceContainerHighest, 1)
            ctx.stroke()

            if (f <= 0) return

            // Value arc: short segments with interpolated colours (as in
            // VolumeKnob), overlapped slightly so no hairline seams show.
            ctx.lineCap = "butt"
            const sweep = root.sweepDeg * f
            const stepDeg = 4
            for (let d = 0; d < sweep; d += stepDeg) {
                const d1 = Math.min(d + stepDeg, sweep)
                ctx.beginPath()
                ctx.arc(cx, cy, r, root.rad(root.startDeg + d),
                        root.rad(root.startDeg + Math.min(d1 + 0.6, sweep)), false)
                ctx.strokeStyle = root.css(root.colorAt((d + d1) / 2 / root.sweepDeg), alpha)
                ctx.stroke()
            }

            // Round caps at both ends, in their own colours
            const caps = [[0, 0], [sweep, f]]
            for (let i = 0; i < caps.length; i++) {
                const a = root.rad(root.startDeg + caps[i][0])
                ctx.beginPath()
                ctx.arc(cx + r * Math.cos(a), cy + r * Math.sin(a),
                        root.lineWidth / 2, 0, 2 * Math.PI, false)
                ctx.fillStyle = root.css(root.colorAt(caps[i][1]), alpha)
                ctx.fill()
            }
        }
    }
}
